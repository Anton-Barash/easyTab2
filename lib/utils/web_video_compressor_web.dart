import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'web_video_compressor.dart';

/// JS-функция сжатия видео в Web Worker (см. web/ffmpeg-loader.js).
@JS('compressVideoInWorker')
external JSPromise<JSUint8Array> _compressVideoInWorker(
  JSUint8Array bytes,
  JSObject config,
  JSFunction onProgress,
);

/// JS-функция: проверка, загружен ли ffmpeg.wasm в память.
@JS('isFfmpegLoaded')
external bool _isFfmpegLoaded();

/// Web-реализация сжатия видео через ffmpeg.wasm в Dedicated Worker.
///
/// Сжатие выполняется в фоновом потоке, поэтому UI Flutter не блокируется.
/// ffmpeg-core.js и ffmpeg-core.wasm кэшируются внутри Worker через Cache API.
class WebVideoCompressorImpl implements WebVideoCompressor {
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  bool _initialized = false;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  bool get isLoaded {
    try {
      return _isFfmpegLoaded();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    // Worker и ffmpeg.wasm инициализируются скриптом web/ffmpeg-loader.js.
    _initialized = true;
  }

  @override
  Future<Uint8List?> compressVideo(
    Uint8List videoBytes, {
    int qualityLevel = 3,
  }) async {
    final cfg = VideoCompressionConfig.byLevel(qualityLevel);
    final config = JSObject()
      ..setProperty('crf'.toJS, cfg.crf.toJS)
      ..setProperty('width'.toJS, cfg.width.toJS)
      ..setProperty('height'.toJS, cfg.height.toJS)
      ..setProperty('fps'.toJS, cfg.fps.toJS);

    final onProgress = (JSAny event) {
      if (event.isA<JSNumber>()) {
        final progress = (event as JSNumber).toDartDouble;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
    }.toJS;

    try {
      final result = await _compressVideoInWorker(
        videoBytes.toJS,
        config,
        onProgress,
      ).toDart;
      return result.toDart;
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() => _progressController.close();
}
