// ============================================================
// Native (dart:io) файловые операции, недоступные на web.
//
// Импортировать через conditional import:
//   import 'package:easy_tab/utils/native_file_ops.dart'
//       if (dart.library.html) 'package:easy_tab/utils/native_file_ops_web.dart';
//
// Инкапсулирует вызовы API, требующие dart:io.File, чтобы на web
// использовалась stub-реализация и код компилировался.
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

/// Создаёт VideoPlayerController.file (native only).
/// На web .file-конструктор недоступен (требует dart:io.File).
VideoPlayerController createFileVideoController(String path) =>
    VideoPlayerController.file(File(path));

/// Создаёт VideoPlayerController из байтов (web: blob URL, native: unsupported).
/// Используется для просмотра видео до загрузки на KS3.
VideoPlayerController createVideoControllerFromBytes(
  Uint8List bytes,
  String mimeType,
) => throw UnsupportedError(
  'createVideoControllerFromBytes не доступно на native',
);

/// Освобождает ресурсы, связанные с видео-контроллером из байтов.
/// На web — revoke blob URL. На native — no-op.
void disposeVideoBytesController(VideoPlayerController? controller) {
  // no-op на native
}

/// Добавляет файл в ZIP-архив (native only).
/// encoder — ZipFileEncoder из package:archive/archive_io.dart.
/// На web ZIP-экспорт локальных файлов не поддерживается.
void zipAddFile(dynamic encoder, String filePath, String relativePath) {
  encoder.addFile(File(filePath), relativePath);
}
