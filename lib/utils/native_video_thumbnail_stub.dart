import 'dart:typed_data';

/// Заглушка для web: нативная генерация превью не используется.
Future<Uint8List?> generateNativeVideoThumbnail(
  String videoPath, {
  required int maxWidth,
  required int maxHeight,
  required int quality,
}) async => null;
