import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'api_result.dart';

String _mimeTypeFromFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'html':
    case 'htm':
      return 'text/html';
    case 'json':
      return 'application/json';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'avi':
      return 'video/x-msvideo';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    default:
      return 'application/octet-stream';
  }
}

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
  final mimeType = _mimeTypeFromFilename(filename);
  final builder = BytesBuilder();

  void _addField(String name, String value) {
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
  _addField('relativePath', relativePath);
  if (reportId != null) {
    _addField('reportId', reportId.toString());
  }
  if (ks3Folder != null) {
    _addField('ks3Folder', ks3Folder);
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
      completer.complete(_parseResponseString(
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

ApiResult _parseResponseString(String responseText, int statusCode) {
  try {
    final body = jsonDecode(responseText) as Map<String, dynamic>;

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResult(
        success: body['success'] == true,
        data: body,
        token: body['token'] as String?,
        user: body['user'] as Map<String, dynamic>?,
        error: body['success'] == true
            ? null
            : (body['error'] as String?) ?? 'Неизвестная ошибка',
      );
    }

    return ApiResult(
      success: false,
      error: (body['error'] as String?) ?? 'Ошибка $statusCode',
    );
  } catch (e) {
    return ApiResult(
      success: false,
      error: 'Некорректный ответ сервера: $statusCode',
    );
  }
}
