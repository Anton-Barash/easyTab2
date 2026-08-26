import 'dart:typed_data';

import 'web_video_compressor_stub.dart'
    if (dart.library.html) 'web_video_compressor_web.dart';

// VideoCompressionConfig живёт в media_quality.dart как единый
// источник истины для UI (login_screen) + WebVideoCompressor.
export 'package:easy_tab/utils/media_quality.dart' show VideoCompressionConfig;

/// Абстракция для сжатия видео на вебе через ffmpeg.wasm.
///
/// На mobile/desktop реализация — заглушка, чтобы web-only код не попадал
/// в нативную сборку.
abstract class WebVideoCompressor {
  /// Поток прогресса сжатия (0.0–1.0).
  Stream<double> get progressStream;

  /// Инициализировать ffmpeg.wasm (при первом вызове скачивает ~25 МБ).
  Future<void> initialize();

  /// Сжать видео. Возвращает сжатые байты или null при ошибке.
  ///
  /// [qualityLevel]: 1 — high, 2 — medium, 3 — low (default).
  Future<Uint8List?> compressVideo(
    Uint8List videoBytes, {
    int qualityLevel = 3,
  });

  /// true, если ffmpeg.wasm уже загружен в память (не нужно скачивать).
  /// Используется для пропуска диалога-предупреждения о трафике.
  bool get isLoaded;

  /// Освободить ресурсы.
  void dispose();

  /// Фабрика: возвращает web-реализацию на web и заглушку на остальных платформах.
  factory WebVideoCompressor.create() = WebVideoCompressorImpl;
}
