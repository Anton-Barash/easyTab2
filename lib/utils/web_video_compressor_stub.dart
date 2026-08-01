import 'dart:typed_data';

import 'web_video_compressor.dart';

/// Заглушка для mobile/desktop.
class WebVideoCompressorImpl implements WebVideoCompressor {
  @override
  Stream<double> get progressStream => const Stream<double>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> compressVideo(Uint8List videoBytes) async => null;

  @override
  bool get isLoaded => false;

  @override
  void dispose() {}
}
