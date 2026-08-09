import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Генерирует превью видео на нативных платформах.
Future<Uint8List?> generateNativeVideoThumbnail(
  String videoPath, {
  required int maxWidth,
  required int maxHeight,
  required int quality,
}) async {
  return VideoThumbnail.thumbnailData(
    video: videoPath,
    imageFormat: ImageFormat.JPEG,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    quality: quality,
  );
}
