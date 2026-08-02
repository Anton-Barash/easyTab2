// ============================================================
// Web-stub для native_file_ops — позволяет коду компилироваться на web.
// Реальные вызовы защищены kIsWeb-проверками и до сюда не доходят.
// ============================================================

import 'dart:typed_data';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:video_player/video_player.dart';

/// На web .file-конструктор недоступен. Никогда не вызывается (kIsWeb guard).
VideoPlayerController createFileVideoController(String path) =>
    throw UnsupportedError('VideoPlayerController.file не доступно на web');

/// Создаёт VideoPlayerController из байтов через blob URL.
/// Используется в FullMediaViewerScreen для просмотра видео до загрузки на KS3.
VideoPlayerController createVideoControllerFromBytes(
  Uint8List bytes,
  String mimeType,
) {
  final blob = html.Blob([bytes], mimeType);
  final blobUrl = html.Url.createObjectUrl(blob);
  return VideoPlayerController.networkUrl(Uri.parse(blobUrl));
}

/// Revoke blob URL, созданный в createVideoControllerFromBytes.
void disposeVideoBytesController(VideoPlayerController? controller) {
  if (controller == null) return;
  final ds = controller.dataSource;
  if (ds.startsWith('blob:')) {
    try {
      html.Url.revokeObjectUrl(ds);
    } catch (_) {}
  }
}

/// На web ZIP-экспорт локальных файлов не поддерживается. No-op.
void zipAddFile(dynamic encoder, String filePath, String relativePath) {
  // no-op на web
}
