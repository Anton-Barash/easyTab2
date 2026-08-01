import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_result.dart';
import 'api_response_parser.dart';
import 'mime_utils.dart';

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
  try {
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);

    final mimeType = mimeTypeFromFilename(filename);

    request.fields['relativePath'] = relativePath;
    if (reportId != null) {
      request.fields['reportId'] = reportId.toString();
    }
    if (ks3Folder != null) {
      request.fields['ks3Folder'] = ks3Folder;
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

    return parseApiResponse(response.body, response.statusCode);
  } on SocketException {
    return const ApiResult(success: false, error: 'Нет соединения с сервером');
  } catch (e) {
    return ApiResult(success: false, error: 'Ошибка загрузки: $e');
  }
}

/// Stub для native — прямая загрузка в KS3 не поддерживается.
/// На native всегда используется серверная загрузка через multipart.
Future<dynamic> uploadToPresignedUrl({
  required String uploadUrl,
  required Uint8List bytes,
  void Function(double progress)? onUploadProgress,
}) async {
  throw UnsupportedError('uploadToPresignedUrl is only available on web');
}
