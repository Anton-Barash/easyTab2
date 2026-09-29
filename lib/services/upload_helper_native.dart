import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../l10n/app_localizations.dart';
import 'api_result.dart';
import 'api_response_parser.dart';
import 'mime_utils.dart';
import 'upload_result.dart';

Future<ApiResult> uploadFileFromBytesWithProgress({
  required Uri uri,
  required Uint8List bytes,
  required String filename,
  required String relativePath,
  required Map<String, String> headers,
  int? reportId,
  void Function(double progress)? onUploadProgress,
  AppLocalizations? loc,
}) async {
  try {
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);

    final mimeType = mimeTypeFromFilename(filename);

    request.fields['relativePath'] = relativePath;
    if (reportId != null) {
      request.fields['reportId'] = reportId.toString();
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    );

    // Native-клиент (dart:io) не даёт прогресса отправки через http API,
    // поэтому сообщаем только старт и завершение.
    onUploadProgress?.call(0.1);
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 300),
    );
    final response = await http.Response.fromStream(streamedResponse);
    onUploadProgress?.call(1.0);

    return parseApiResponse(response.body, response.statusCode, loc: loc);
  } on SocketException {
    return ApiResult(
      success: false,
      error: loc?.noServerConnection ?? 'Нет соединения с сервером',
    );
  } catch (e) {
    return ApiResult(
      success: false,
      error: loc?.uploadErrorDetail(e.toString()) ?? 'Ошибка загрузки: $e',
    );
  }
}

/// Прямая загрузка файла в KS3 по presigned PUT URL (native).
///
/// Используется в share-режиме: владельческий /files/upload требует, чтобы
/// JWT-пользователь был создателем отчёта, и возвращает анониму 403.
/// PUT уходит сразу в KS3, Content-Type намеренно НЕ задаётся — presign
/// подписан без него, и установка заголовка ломает подпись.
Future<dynamic> uploadToPresignedUrl({
  required String uploadUrl,
  required Uint8List bytes,
  void Function(double progress)? onUploadProgress,
  AppLocalizations? loc,
}) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final request = await client.putUrl(Uri.parse(uploadUrl));
    request.contentLength = bytes.length;
    request.add(bytes);
    onUploadProgress?.call(0.1);

    final response = await request.close().timeout(
      const Duration(seconds: 300),
    );
    // Тело ответа не нужно, но поток обязателен к завершению.
    await response.drain<void>();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      onUploadProgress?.call(1.0);
      return true;
    }
    return 'KS3 upload failed: ${response.statusCode} '
        '${response.reasonPhrase}';
  } catch (e) {
    return 'KS3 upload error: $e';
  } finally {
    client?.close(force: true);
  }
}

/// Stub для native — прямая загрузка с прогрессом не поддерживается.
/// На native видео загружается через серверный multipart.
Future<UploadResult> uploadWithProgress({
  required Uint8List fileBytes,
  required String fileName,
  required String mimeType,
  required String relativePath,
  int? reportId,
  String? shareToken,
  void Function(double progress)? onProgress,
  void Function(String fileId)? onPresigned,
}) async {
  throw UnsupportedError('uploadWithProgress is only available on web');
}
