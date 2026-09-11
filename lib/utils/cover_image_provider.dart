// ============================================================
// Cover image provider (native-реализация).
//
// Использование (conditional import):
//   import 'package:easy_tab/utils/cover_image_provider.dart'
//       if (dart.library.html) 'package:easy_tab/utils/cover_image_provider_web.dart';
//
// На native (Android/iOS/Windows/macOS/Linux) — FileImage из dart:io.
// На web — вернёт null (там обложка берётся с сервера /cover).
//
// Отдельный файл нужен, чтобы не подмешивать dart:io.File в web-сборку:
// FileImage требует именно dart:io.File, а на web File подменяется
// stub'ом из platform_io_web.dart.
// ============================================================

import 'dart:io';

import 'package:flutter/widgets.dart';

/// Строит ImageProvider из локального файла-обложки.
/// Возвращает null, если пути нет.
ImageProvider? localCoverImageProvider(String? path) {
  if (path == null) return null;
  return FileImage(File(path));
}