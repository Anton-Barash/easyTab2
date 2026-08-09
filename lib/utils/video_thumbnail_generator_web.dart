import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'video_thumbnail_generator.dart';

/// Web-реализация генерации превью видео через HTML video + canvas.
class VideoThumbnailGeneratorImpl implements VideoThumbnailGenerator {
  @override
  Future<Uint8List?> generateThumbnail(
    Uint8List videoBytes, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  }) async {
    if (videoBytes.isEmpty) return null;

    final blob = _createBlob(videoBytes.toJS, 'video/mp4'.toJS);
    final url = _createObjectUrl(blob);
    if (url.isEmpty) return null;

    try {
      return await _captureFromUrl(
        url,
        timeMs: timeMs,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
      );
    } catch (e) {
      return null;
    } finally {
      _revokeObjectUrl(url);
    }
  }

  @override
  Future<Uint8List?> generateThumbnailFromUrl(
    String videoUrl, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  }) async {
    if (videoUrl.isEmpty) return null;
    return _captureFromUrl(
      videoUrl,
      timeMs: timeMs,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
  }

  Future<Uint8List?> _captureFromUrl(
    String url, {
    required int timeMs,
    required int maxWidth,
    required int maxHeight,
    required int quality,
  }) async {
    final completer = Completer<Uint8List?>();

    final video = _createVideoElement();
    video.setAttribute('src', url.toJS);
    video.setAttribute('preload', 'auto'.toJS);
    video.setAttribute('crossOrigin', 'anonymous'.toJS);
    video.setAttribute('muted', 'true'.toJS);
    video.setAttribute('playsinline', 'true'.toJS);

    // ignore: avoid_js_rounded_ints
    final seekTime = (timeMs / 1000).toJS;

    void captureFrame() {
      try {
        final width = video.videoWidth.toDouble();
        final height = video.videoHeight.toDouble();
        if (width <= 0 || height <= 0) {
          completer.complete(null);
          return;
        }

        final scale = _calculateScale(width, height, maxWidth, maxHeight);
        final canvasWidth = (width * scale).round();
        final canvasHeight = (height * scale).round();

        final canvas = _createCanvasElement(canvasWidth, canvasHeight);
        final ctx = canvas.getContext('2d') as JSObject?;
        if (ctx == null) {
          completer.complete(null);
          return;
        }

        _drawImage(ctx, video, 0, 0, canvasWidth, canvasHeight);
        final dataUrl = _canvasToDataURL(canvas, 'image/jpeg', quality);
        if (dataUrl == null || dataUrl.isEmpty) {
          completer.complete(null);
          return;
        }

        final bytes = _dataUrlToBytes(dataUrl);
        completer.complete(bytes);
      } catch (e) {
        completer.complete(null);
      }
    }

    _addEventListener(video as JSObject, 'loadeddata', () {
      video.currentTime = seekTime;
    }.toJS);

    _addEventListener(video as JSObject, 'seeked', captureFrame.toJS);

    _addEventListener(video as JSObject, 'error', () {
      completer.complete(null);
    }.toJS);

    // Таймаут на случай, если видео не загрузится.
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  double _calculateScale(double width, double height, int maxW, int maxH) {
    final scaleW = maxW / width;
    final scaleH = maxH / height;
    return scaleW < scaleH ? scaleW : scaleH;
  }

  Uint8List? _dataUrlToBytes(String dataUrl) {
    try {
      final header = 'data:image/jpeg;base64,';
      if (!dataUrl.startsWith(header)) return null;
      final base64 = dataUrl.substring(header.length);
      return base64Decode(base64);
    } catch (e) {
      return null;
    }
  }
}

// JS interop helpers
@JS('URL.createObjectURL')
external String _createObjectUrl(Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('Blob')
@staticInterop
class Blob {
  external factory Blob(JSArray parts, JSObject options);
}

@JS('document.createElement')
external JSObject _createElement(String tag);

@JS()
@staticInterop
class HTMLVideoElement {}

extension HTMLVideoElementExt on HTMLVideoElement {
  external set src(String value);
  external set preload(String value);
  external set crossOrigin(String value);
  external set muted(String value);
  external set playsinline(String value);
  external set currentTime(JSNumber value);
  external int get videoWidth;
  external int get videoHeight;
  external void setAttribute(String name, JSAny value);
}

@JS()
@staticInterop
class HTMLCanvasElement {}

extension HTMLCanvasElementExt on HTMLCanvasElement {
  external JSObject getContext(String contextType);
  external String toDataURL(String type, JSNumber quality);
}

@JS()
@staticInterop
class CanvasRenderingContext2D {}

extension CanvasRenderingContext2DExt on CanvasRenderingContext2D {
  external void drawImage(
    JSObject image,
    int sx,
    int sy,
    int sWidth,
    int sHeight,
  );
}

Blob _createBlob(JSUint8Array bytes, JSString type) {
  return Blob(
    [bytes].toJS as JSArray,
    JSObject()..setProperty('type'.toJS, type),
  );
}

HTMLVideoElement _createVideoElement() {
  return _createElement('video') as HTMLVideoElement;
}

HTMLCanvasElement _createCanvasElement(int width, int height) {
  final canvas = _createElement('canvas') as HTMLCanvasElement;
  (canvas as JSObject).setProperty('width'.toJS, width.toJS);
  (canvas as JSObject).setProperty('height'.toJS, height.toJS);
  return canvas;
}

String? _canvasToDataURL(HTMLCanvasElement canvas, String type, int quality) {
  final q = (quality / 100).toJS;
  return canvas.toDataURL(type, q);
}

void _drawImage(
  JSObject ctx,
  HTMLVideoElement video,
  int x,
  int y,
  int width,
  int height,
) {
  (ctx as CanvasRenderingContext2D).drawImage(
    video as JSObject,
    x,
    y,
    width,
    height,
  );
}

void _addEventListener(JSObject element, String event, JSFunction handler) {
  element.callMethod('addEventListener'.toJS, [event.toJS, handler].toJS);
}

// base64 decode helper (dart:convert нельзя использовать напрямую в некоторых
// конфигурациях, реализуем простой decoder)
Uint8List base64Decode(String input) {
  const codec = _Base64Codec();
  return codec.decode(input);
}

class _Base64Codec {
  const _Base64Codec();

  Uint8List decode(String input) {
    final normalized = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    final length = normalized.length;
    if (length % 4 != 0) return Uint8List(0);

    final outputLength = (length * 3 ~/ 4) -
        (normalized.endsWith('==') ? 2 : (normalized.endsWith('=') ? 1 : 0));
    final result = Uint8List(outputLength);

    var j = 0;
    for (var i = 0; i < length; i += 4) {
      final a = _decodeChar(normalized[i]);
      final b = _decodeChar(normalized[i + 1]);
      final c = _decodeChar(normalized[i + 2]);
      final d = _decodeChar(normalized[i + 3]);

      final triple = (a << 18) | (b << 12) | (c << 6) | d;

      if (j < outputLength) result[j++] = (triple >> 16) & 0xFF;
      if (c != 64 && j < outputLength) result[j++] = (triple >> 8) & 0xFF;
      if (d != 64 && j < outputLength) result[j++] = triple & 0xFF;
    }

    return result;
  }

  int _decodeChar(String ch) {
    final code = ch.codeUnitAt(0);
    if (code >= 65 && code <= 90) return code - 65; // A-Z
    if (code >= 97 && code <= 122) return code - 97 + 26; // a-z
    if (code >= 48 && code <= 57) return code - 48 + 52; // 0-9
    if (ch == '+') return 62;
    if (ch == '/') return 63;
    return 64; // padding '='
  }
}
