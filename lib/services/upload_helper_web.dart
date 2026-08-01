import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'api_result.dart';
import 'api_response_parser.dart';
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
