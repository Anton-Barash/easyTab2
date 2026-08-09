import 'dart:typed_data';

import 'video_thumbnail_generator.dart';

/// Заглушка для mobile/desktop.
class VideoThumbnailGeneratorImpl implements VideoThumbnailGenerator {
  @override
  Future<Uint8List?> generateThumbnail(
    Uint8List videoBytes, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  }) async => null;

  @override
  Future<Uint8List?> generateThumbnailFromUrl(
    String videoUrl, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  }) async => null;
}
