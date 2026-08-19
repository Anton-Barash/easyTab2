// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import 'video_thumbnail_generator.dart';

/// Web-реализация генератора превью видео.
///
/// Использует HTML5 `<video>` + `<canvas>` для извлечения кадра
/// из видео-байтов (Blob/URL) или сетевого URL.
class VideoThumbnailGeneratorImpl implements VideoThumbnailGenerator {
  @override
  Future<Uint8List?> generateThumbnail(
    Uint8List videoBytes, {
    int timeMs = 1000,
    int maxWidth = 256,
    int maxHeight = 256,
    int quality = 70,
  }) async {
    // Создаём blob НЕ через html.Blob(), а через конструктор JsObject —
    // в Flutter web html.Blob может создавать blob в неправильном контексте.
    final blob = html.Blob([videoBytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      return await _extractFrame(
        url,
        timeMs,
        maxWidth,
        maxHeight,
        quality,
        isBlob: true,
      );
    } finally {
      html.Url.revokeObjectUrl(url);
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
    return _extractFrame(videoUrl, timeMs, maxWidth, maxHeight, quality);
  }

  /// Основной метод: создаёт скрытый video-элемент, ждёт загрузки
  /// метаданных, перематывает на [timeMs], дожидается кадра и рисует
  /// его в canvas.
  Future<Uint8List?> _extractFrame(
    String videoUrl,
    int timeMs,
    int maxWidth,
    int maxHeight,
    int quality, {
    bool isBlob = false,
  }) async {
    final completer = Completer<Uint8List?>();

    // Создаём video через document.createElement — надёжнее,
    // чем html.VideoElement() во Flutter web.
    final video =
        html.document.createElement('video') as html.VideoElement;
    video.src = videoUrl;
    // НЕ ставим crossOrigin для blob URL — blob не имеет CORS-заголовков,
    // и crossOrigin='anonymous' вызывает ERR_FILE_NOT_FOUND.
    if (!isBlob) {
      video.crossOrigin = 'anonymous';
    }
    video.preload = 'auto';
    video.muted = true;
    video.style.display = 'none';
    video.setAttribute('playsinline', 'true');

    // Добавляем в DOM, иначе браузер не начнёт загрузку.
    html.document.body?.append(video);
    video.load();

    // Таймаут 10 секунд.
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        video.remove();
        completer.complete(null);
      }
    });

    // Обработчик ошибок видео.
    video.onError.first.then((_) {
      timeout?.cancel();
      video.remove();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    // Ждём загрузки метаданных (длительность, размеры видео).
    video.onLoadedMetadata.first.then((_) {
      if (completer.isCompleted) return;

      // Перематываем на нужный кадр.
      final seekTime = (timeMs / 1000.0).clamp(0.0, video.duration);
      video.currentTime = seekTime;

      // Ждём, когда видео перемотается.
      video.onSeeked.first.then((_) {
        if (completer.isCompleted) return;
        timeout?.cancel();
        try {
          final canvas = html.CanvasElement();
          final videoWidth = video.videoWidth;
          final videoHeight = video.videoHeight;

          if (videoWidth == 0 || videoHeight == 0) {
            video.remove();
            completer.complete(null);
            return;
          }

          // Вычисляем размеры canvas, сохраняя пропорции.
          final scale = (maxWidth / videoWidth)
              .clamp(0.0, (maxHeight / videoHeight).clamp(0.0, double.infinity));
          final canvasW = (videoWidth * scale).round();
          final canvasH = (videoHeight * scale).round();
          canvas.width = canvasW;
          canvas.height = canvasH;

          final ctx = canvas.context2D;
          ctx.drawImageScaled(video, 0, 0, canvasW, canvasH);

          final dataUrl = canvas.toDataUrl('image/jpeg', quality / 100.0);
          final base64 = dataUrl.split(',').last;
          final bytes = base64Decode(base64);

          video.remove();
          completer.complete(Uint8List.fromList(bytes));
        } catch (e) {
          video.remove();
          completer.complete(null);
        }
      }).catchError((_) {
        timeout?.cancel();
        video.remove();
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
    }).catchError((_) {
      timeout?.cancel();
      video.remove();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return completer.future;
  }
}