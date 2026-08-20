import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:v_video_compressor/v_video_compressor.dart';

// ============================================================
// NativeVideoCompressService — сжатие видео на нативных
// платформах через v_video_compressor.
//
// Выделено в отдельный модуль для deferred loading:
// плагин v_video_compressor тяжёлый и не нужен в основном
// бандле до первого явного запроса сжатия от пользователя.
// ============================================================

/// Результат успешного сжатия одного видео.
class NativeCompressResult {
  /// Относительный путь видео внутри папки отчёта.
  final String relativePath;

  /// Размер сжатого файла в байтах.
  final int compressedSize;

  const NativeCompressResult(this.relativePath, this.compressedSize);
}

/// Сжимает один видеофайл поверх оригинала.
///
/// [qualityLevel]: 1 — высокое качество, 2 — среднее, 3 — низкое
/// (максимальное сжатие).
///
/// Возвращает [NativeCompressResult] при успехе и `null`, если файл
/// пропущен (не существует, ≤ 5 МБ) или сжатие завершилось ошибкой.
Future<NativeCompressResult?> compressNativeVideo({
  required String absolutePath,
  required String relativePath,
  required int qualityLevel,
}) async {
  final config = switch (qualityLevel) {
    1 => const VVideoCompressionConfig.high(),
    2 => const VVideoCompressionConfig.medium(),
    _ => const VVideoCompressionConfig.low(),
  };

  try {
    final file = File(absolutePath);
    if (!await file.exists()) return null;
    // Маленькие видео сжимать бессмысленно.
    if (await file.length() <= 5 * 1024 * 1024) return null;

    final compressor = VVideoCompressor();
    final result = await compressor.compressVideo(
      absolutePath,
      config,
      onProgress: (progress) {},
    );
    if (result == null) return null;

    final compressedFile = File(result.compressedFilePath);
    if (!await compressedFile.exists()) return null;

    final compressedSize = await compressedFile.length();
    try {
      // Не заменяем оригинал пустым файлом (0 байт при сбое кодека).
      if (compressedSize <= 0) return null;
      await compressedFile.copy(absolutePath);
      return NativeCompressResult(relativePath, compressedSize);
    } finally {
      if (await compressedFile.exists()) {
        await compressedFile.delete();
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint('Error compressing video: $e');
    return null;
  }
}
