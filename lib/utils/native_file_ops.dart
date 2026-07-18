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
import 'package:video_player/video_player.dart';

/// Создаёт VideoPlayerController.file (native only).
/// На web .file-конструктор недоступен (требует dart:io.File).
VideoPlayerController createFileVideoController(String path) =>
    VideoPlayerController.file(File(path));

/// Добавляет файл в ZIP-архив (native only).
/// encoder — ZipFileEncoder из package:archive/archive_io.dart.
/// На web ZIP-экспорт локальных файлов не поддерживается.
void zipAddFile(dynamic encoder, String filePath, String relativePath) {
  encoder.addFile(File(filePath), relativePath);
}
