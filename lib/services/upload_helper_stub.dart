import 'dart:typed_data';

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
