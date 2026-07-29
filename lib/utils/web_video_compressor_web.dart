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
  Future<void> initialize() async {
    if (_initialized) return;
    // Worker и ffmpeg.wasm инициализируются скриптом web/ffmpeg-loader.js.
    _initialized = true;
  }

  @override
  Future<Uint8List?> compressVideo(Uint8List videoBytes) async {
    final config = JSObject()
      ..setProperty('crf'.toJS, 28.toJS)
      ..setProperty('width'.toJS, 1280.toJS)
      ..setProperty('height'.toJS, 720.toJS)
      ..setProperty('fps'.toJS, 24.toJS);

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
