import 'dart:typed_data';

import 'web_video_compressor_stub.dart'
    if (dart.library.html) 'web_video_compressor_web.dart';

/// Абстракция для сжатия видео на вебе через ffmpeg.wasm.
///
/// На mobile/desktop реализация — заглушка, чтобы пакет video_web_compressor,
/// который поддерживает только web, не попадал в сборку.
abstract class WebVideoCompressor {
  /// Поток прогресса сжатия (0.0–1.0).
  Stream<double> get progressStream;

  /// Инициализировать ffmpeg.wasm (при первом вызове скачивает ~25 МБ).
  Future<void> initialize();

  /// Сжать видео. Возвращает сжатые байты или null при ошибке.
  Future<Uint8List?> compressVideo(Uint8List videoBytes);

  /// Освободить ресурсы.
  void dispose();

  /// Фабрика: возвращает web-реализацию на web и заглушку на остальных платформах.
  factory WebVideoCompressor.create() = WebVideoCompressorImpl;
}
