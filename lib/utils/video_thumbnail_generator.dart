import 'dart:typed_data';

import 'video_thumbnail_generator_stub.dart'
    if (dart.library.html) 'video_thumbnail_generator_web.dart';

/// Абстракция для генерации превью (стоп-кадра) видео.
///
/// На web использует HTML video + canvas.
/// На mobile/desktop — заглушка (там используется пакет video_thumbnail).
abstract class VideoThumbnailGenerator {
  /// Сгенерировать JPEG-превью из видео-байтов.
  ///
  /// [videoBytes] — байты видео.
  /// [timeMs] — время кадра в миллисекундах (по умолчанию 1000).
  /// [maxWidth] / [maxHeight] — максимальные размеры превью.
  /// [quality] — качество JPEG (0–100).
  ///
  /// Возвращает null при ошибке.
  Future<Uint8List?> generateThumbnail(
    Uint8List videoBytes, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  });

  /// Сгенерировать JPEG-превью из URL видео (web-only).
  ///
  /// Используется для медиа, загруженных на сервер, когда в памяти
  /// нет исходных байтов, но есть presigned URL.
  Future<Uint8List?> generateThumbnailFromUrl(
    String videoUrl, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  });

  factory VideoThumbnailGenerator.create() = VideoThumbnailGeneratorImpl;
}
