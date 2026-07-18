// ============================================================
// Web-stub для native_file_ops — позволяет коду компилироваться на web.
// Реальные вызовы защищены kIsWeb-проверками и до сюда не доходят.
// ============================================================

import 'package:video_player/video_player.dart';

/// На web .file-конструктор недоступен. Никогда не вызывается (kIsWeb guard).
VideoPlayerController createFileVideoController(String path) =>
    throw UnsupportedError('VideoPlayerController.file не доступно на web');

/// На web ZIP-экспорт локальных файлов не поддерживается. No-op.
void zipAddFile(dynamic encoder, String filePath, String relativePath) {
  // no-op на web
}
