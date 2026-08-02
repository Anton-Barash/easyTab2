import 'dart:async';
import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'api_result.dart';
import 'api_response_parser.dart';
import 'api_service.dart';
import 'mime_utils.dart';

// Примечание: dart:convert всё ещё нужен для utf8.encode при сборке multipart-тела.

Future<ApiResult> uploadFileFromBytesWithProgress({
  required Uri uri,
  required Uint8List bytes,
  required String filename,
  required String relativePath,
  required Map<String, String> headers,
  int? reportId,
  String? ks3Folder,
  void Function(double progress)? onUploadProgress,
}) async {
  final completer = Completer<ApiResult>();

  // P3-55: формируем multipart/form-data вручную, чтобы браузер знал
  // Content-Length и отдавал корректный прогресс загрузки.
  final boundary = '----dart-boundary-${DateTime.now().millisecondsSinceEpoch}';
  final mimeType = mimeTypeFromFilename(filename);
  final builder = BytesBuilder();

  void addField(String name, String value) {
    builder.add(utf8.encode('--$boundary\r\n'));
    builder.add(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
    builder.add(utf8.encode(value));
    builder.add(utf8.encode('\r\n'));
  }

  // file field
  builder.add(utf8.encode('--$boundary\r\n'));
  builder.add(utf8.encode('Content-Disposition: form-data; name="file"; filename="$filename"\r\n'));
  builder.add(utf8.encode('Content-Type: $mimeType\r\n\r\n'));
  builder.add(bytes);
  builder.add(utf8.encode('\r\n'));

  // text fields
  addField('relativePath', relativePath);
  if (reportId != null) {
    addField('reportId', reportId.toString());
  }
  if (ks3Folder != null) {
    addField('ks3Folder', ks3Folder);
  }

  builder.add(utf8.encode('--$boundary--\r\n'));

  final body = builder.toBytes();

  final request = html.HttpRequest();
  request.open('POST', uri.toString());
  headers.forEach(request.setRequestHeader);
  request.setRequestHeader('Content-Type', 'multipart/form-data; boundary=$boundary');

  request.upload.onProgress.listen((event) {
    if (event.lengthComputable && onUploadProgress != null && event.total != null && event.total! > 0) {
      final progress = event.loaded!.toDouble() / event.total!.toDouble();
      // ignore: avoid_print
      print('[UploadHelperWeb] progress $progress (${event.loaded}/${event.total})');
      onUploadProgress(progress);
    } else {
      // ignore: avoid_print
      print('[UploadHelperWeb] progress event not computable: loaded=${event.loaded}, total=${event.total}');
    }
  });

  request.onLoadEnd.listen((_) {
    if (request.status != null &&
        request.status! >= 200 &&
        request.status! < 300) {
      completer.complete(parseApiResponse(
        request.responseText ?? '',
        request.status!,
      ));
    } else {
      completer.complete(ApiResult(
        success: false,
        error: request.statusText ?? 'Upload failed (${request.status})',
      ));
    }
  });

  request.onError.listen((_) {
    completer.complete(const ApiResult(success: false, error: 'Upload error'));
  });

  request.onTimeout.listen((_) {
    completer.complete(const ApiResult(success: false, error: 'Upload timeout'));
  });

  request.send(body);
  return completer.future.timeout(const Duration(seconds: 300));
}

/// Прямая загрузка файла в KS3 по presigned PUT URL.
///
/// Браузер отправляет PUT-запрос напрямую в KS3, минуя сервер.
/// Прогресс отслеживается через XMLHttpRequest.upload.onProgress.
///
/// [uploadUrl] — presigned PUT URL, полученный через ApiService.presignUpload().
/// [bytes] — содержимое файла.
/// [onUploadProgress] — callback с прогрессом (0.0 - 1.0).
///
/// Возвращает true при успехе, String с ошибкой при неудаче.
Future<dynamic> uploadToPresignedUrl({
  required String uploadUrl,
  required Uint8List bytes,
  void Function(double progress)? onUploadProgress,
}) async {
  final completer = Completer<dynamic>();

  final request = html.HttpRequest();
  request.open('PUT', uploadUrl);

  // Не устанавливаем Content-Type — KS3 presigned URL подписан без него.
  // Установка Content-Type приведёт к ошибке подписи (SignatureDoesNotMatch).

  request.upload.onProgress.listen((event) {
    if (event.lengthComputable && onUploadProgress != null && event.total != null && event.total! > 0) {
      final progress = event.loaded!.toDouble() / event.total!.toDouble();
      onUploadProgress(progress);
    }
  });

  request.onLoadEnd.listen((_) {
    if (request.status != null && request.status! >= 200 && request.status! < 300) {
      completer.complete(true);
    } else {
      final errMsg = request.responseText ?? '';
      completer.complete('KS3 upload failed: ${request.status} ${request.statusText} $errMsg');
    }
  });

  request.onError.listen((_) {
    completer.complete('KS3 upload network error');
  });

  request.onTimeout.listen((_) {
    completer.complete('KS3 upload timeout');
  });

  request.send(bytes);
  return completer.future.timeout(const Duration(seconds: 300));
}

/// Результат загрузки файла через [UploadHelperWeb.uploadWithProgress].
class UploadResult {
  final bool success;
  final String? error;
  final String? serverFileId;
  final String? webUrl;

  UploadResult({
    required this.success,
    this.error,
    this.serverFileId,
    this.webUrl,
  });
}

/// Прямая загрузка файла в KS3 через presigned URL (web only).
///
/// Flow:
///   1. POST /files/presign-upload → получаем presigned URL + fileId
///   2. PUT directly to KS3 → загружаем байты
///   3. POST /files/confirm-upload → создаём запись в БД
///
/// Возвращает [UploadResult] с [serverFileId] при успехе.
Future<UploadResult> uploadWithProgress({
  required Uint8List fileBytes,
  required String fileName,
  required String mimeType,
  required String relativePath,
  int? reportId,
  void Function(double progress)? onProgress,
  void Function(String fileId)? onPresigned,
}) async {
  // Шаг 1: presign
  final presignResult = await ApiService.presignUpload(
    fileName: fileName,
    relativePath: relativePath,
    reportId: reportId,
  );

  if (!presignResult.success) {
    return UploadResult(
      success: false,
      error: presignResult.error ?? 'presign failed',
    );
  }

  final data = presignResult.data!;
  final uploadUrl = data['uploadUrl'] as String;
  final fileId = data['fileId'] as String;
  final storageKey = data['storageKey'] as String;
  final serverMimeType = data['mimeType'] as String? ?? mimeType;
  final relPath = data['relPath'] as String? ?? relativePath;

  // Сообщаем вызывающему коду fileId как можно раньше — это позволяет
  // удалить файл с сервера, если пользователь отменит загрузку.
  onPresigned?.call(fileId);

  // Шаг 2: прямая загрузка в KS3
  final uploadResult = await uploadToPresignedUrl(
    uploadUrl: uploadUrl,
    bytes: fileBytes,
    onUploadProgress: onProgress,
  );

  if (uploadResult != true) {
    return UploadResult(
      success: false,
      error: uploadResult.toString(),
    );
  }

  // Шаг 3: подтвердить загрузку — создать запись в БД
  final confirmResult = await ApiService.confirmUpload(
    fileId: fileId,
    storageKey: storageKey,
    fileName: fileName,
    size: fileBytes.length,
    mimeType: serverMimeType,
    relPath: relPath,
    reportId: reportId,
  );

  if (!confirmResult.success) {
    return UploadResult(
      success: false,
      error: confirmResult.error ?? 'confirm failed',
    );
  }

  return UploadResult(
    success: true,
    serverFileId: fileId,
    webUrl: confirmResult.data?['url'] as String?,
  );
}
