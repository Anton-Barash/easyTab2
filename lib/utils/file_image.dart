// ============================================================
// Native (dart:io) реализация file-image хелперов.
//
// Импортировать через conditional import:
//   import 'package:easy_tab/utils/file_image.dart'
//       if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
//
// Проблема: Flutter's Image.file / FileImage требуют dart:io.File.
// На web условный import даёт stub-File из platform_io_web.dart,
// который НЕ является dart:io.File → ошибка типов.
// Эти хелперы инкапсулируют работу с dart:io.File, чтобы на web
// использовалась web-реализация (placeholder) и код компилировался.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';

/// Виджет-изображение из локального файла (native only).
Widget fileImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

/// ImageProvider из локального файла (native only).
ImageProvider fileImageProvider(String path) => FileImage(File(path));
