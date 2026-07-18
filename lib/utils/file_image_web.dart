// ============================================================
// Web-реализация file-image хелперов (placeholder).
//
// На web локальные файлы недоступны (dart:io.File не существует),
// поэтому возвращаем безопасные placeholder'ы. Реальные вызовы
// защищены kIsWeb-проверками и до сюда не доходят.
// ============================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 1x1 прозрачный PNG — валидный ImageProvider, не падает при отрисовке.
final Uint8List _transparent1x1 = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// На web — пустой placeholder (никогда не вызывается, код защищён kIsWeb).
Widget fileImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return const SizedBox.shrink();
}

/// На web — прозрачный 1x1 ImageProvider (не падает при отрисовке).
ImageProvider fileImageProvider(String path) => MemoryImage(_transparent1x1);
