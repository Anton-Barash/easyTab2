import 'dart:typed_data';

import 'api_result.dart';
import 'upload_result.dart';

export 'upload_result.dart';

/// Заглушка для загрузки файлов на non-web платформах.
///
/// VideoUploadQueue используется только на web, поэтому стаб
/// никогда не должен вызываться.
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

/// Заглушка для multipart-загрузки байтов (не используется на stub-платформах).
Future<ApiResult> uploadFileFromBytesWithProgress({
  required Uri uri,
  required Uint8List bytes,
  required String filename,
  required String relativePath,
  required Map<String, String> headers,
  int? reportId,
  void Function(double progress)? onUploadProgress,
}) async {
  throw UnsupportedError(
    'uploadFileFromBytesWithProgress is not available on this platform',
  );
}

/// Заглушка для прямой загрузки по presigned URL.
Future<dynamic> uploadToPresignedUrl({
  required String uploadUrl,
  required Uint8List bytes,
  void Function(double progress)? onUploadProgress,
}) async {
  throw UnsupportedError(
    'uploadToPresignedUrl is not available on this platform',
  );
}
