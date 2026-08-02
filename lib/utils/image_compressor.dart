import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Утилиты для сжатия изображений.
///
/// Поддерживает форматы: PNG, JPEG, WebP.
/// Автоматически определяет формат по сигнатуре файла.
class ImageCompressor {
  ImageCompressor._();

  /// Проверить, является ли файл PNG.
  static bool isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  /// Проверить, является ли файл WebP.
  static bool isWebp(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }

  /// Сжать изображение (уменьшить размер, если больше maxSize).
  ///
  /// Если изображение больше maxSize по любой стороне, оно масштабируется
  /// с сохранением пропорций. PNG сохраняется как PNG, остальные форматы
  /// конвертируются в JPEG с качеством 90%.
  ///
  /// Возвращает оригинальные байты, если:
  /// - Изображение уже меньше maxSize
  /// - Не удалось декодировать
  /// - Сжатый файл пустой
  static Uint8List compress(Uint8List bytes, int maxSize) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) {
        if (kDebugMode) debugPrint('Error: Could not decode image');
        return bytes;
      }

      int width = image.width;
      int height = image.height;

      if (width <= maxSize && height <= maxSize) {
        return bytes;
      }

      double scale = maxSize / (width > height ? width : height);
      width = (width * scale).toInt();
      height = (height * scale).toInt();

      if (width < 1) width = 1;
      if (height < 1) height = 1;

      final resized = img.copyResize(image, width: width, height: height);

      Uint8List result;
      if (isPng(bytes)) {
        result = img.encodePng(resized);
      } else if (isWebp(bytes)) {
        result = img.encodeJpg(resized, quality: 90);
      } else {
        result = img.encodeJpg(resized, quality: 90);
      }

      if (result.isEmpty) {
        if (kDebugMode) debugPrint('Error: Compressed image is empty');
        return bytes;
      }

      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Error compressing image: $e');
      return bytes;
    }
  }
}
