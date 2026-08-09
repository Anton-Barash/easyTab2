import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/report_models.dart';
import '../utils/web_video_compressor.dart';
import 'upload_helper_web.dart' if (dart.library.io) 'upload_helper_stub.dart';

// ============================================================
// VideoUploadQueue — фоновая очередь сжатия и загрузки видео.
//
// Обрабатывает видео строго по одному:
//   1. Инициализирует ffmpeg.wasm (lazy, один раз).
//   2. Сжимает видео.
//   3. Загружает сжатый файл на сервер (KS3).
//
// UI подписывается на [progressStream] и обновляет миниатюры.
// ============================================================

/// Фаза обработки видео.
enum VideoProcessingPhase {
  /// Сжатие ffmpeg.wasm.
  compressing,

  /// Прямая загрузка в KS3.
  uploading,
}

/// Прогресс обработки одного видео.
class VideoUploadProgress {
  final String mediaId;
  final VideoProcessingPhase phase;
  final double value;

  const VideoUploadProgress({
    required this.mediaId,
    required this.phase,
    required this.value,
  });
}

/// Задача на обработку видео.
class _VideoUploadTask {
  final MediaItem media;
  final Uint8List originalBytes;
  final String fileName;
  final String mimeType;
  final String relativePath;
  final int? reportId;
  final String? shareToken;

  _VideoUploadTask({
    required this.media,
    required this.originalBytes,
    required this.fileName,
    required this.mimeType,
    required this.relativePath,
    this.reportId,
    this.shareToken,
  });
}

class VideoUploadQueue {
  final WebVideoCompressor _compressor = WebVideoCompressor.create();
  final List<_VideoUploadTask> _tasks = [];
  final Set<MediaItem> _cancelled = <MediaItem>{};
  final StreamController<VideoUploadProgress> _progressController =
      StreamController<VideoUploadProgress>.broadcast();

  bool _isProcessing = false;
  bool _trafficWarningShown = false;

  Stream<VideoUploadProgress> get progressStream => _progressController.stream;

  /// Добавить видео в очередь.
  ///
  /// Если очередь пуста — запускает обработку. Видео обрабатываются
  /// строго по одному: сначала сжатие, затем загрузка.
  Future<void> enqueue({
    required MediaItem media,
    required Uint8List originalBytes,
    required String fileName,
    required String mimeType,
    required String relativePath,
    int? reportId,
    String? shareToken,
    void Function(String error)? onError,
  }) async {
    // Если медиа ранее помечалось отменённым — снимаем отметку,
    // потому что пользователь снова его добавил.
    _cancelled.remove(media);

    final task = _VideoUploadTask(
      media: media,
      originalBytes: originalBytes,
      fileName: fileName,
      mimeType: mimeType,
      relativePath: relativePath,
      reportId: reportId,
      shareToken: shareToken,
    );
    _tasks.add(task);

    unawaited(_processNext(onError: onError));
  }

  /// Отменить обработку медиа.
  ///
  /// Удаляет из очереди задачи, которые ещё не начали обрабатываться.
  /// Активно выполняющуюся сжатие прервать нельзя (ffmpeg.wasm не
  /// поддерживает прерывание), поэтому помечаем медиа как отменённое:
  /// после завершения сжатия результат загружен не будет.
  ///
  /// Возвращает true, если медиа было найдено в очереди.
  /// Активно обрабатывающееся медиа тоже считается отменённым, даже если
  /// метод вернул false.
  bool cancel(MediaItem media) {
    final before = _tasks.length;
    _tasks.removeWhere((task) => task.media == media);
    final removedFromQueue = before - _tasks.length;
    _cancelled.add(media);
    return removedFromQueue > 0;
  }

  /// Освободить ресурсы компрессора.
  void dispose() {
    _tasks.clear();
    _cancelled.clear();
    _progressController.close();
    _compressor.dispose();
  }

  Future<void> _processNext({void Function(String error)? onError}) async {
    // В Dart код выполняется в одном потоке до первого await,
    // поэтому проверка и установка флага — атомарная операция.
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (_tasks.isNotEmpty) {
        final task = _tasks.removeAt(0);
        await _processTask(task, onError: onError);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processTask(
    _VideoUploadTask task, {
    void Function(String error)? onError,
  }) async {
    final media = task.media;
    final bytes = task.originalBytes;

    media.isCompressing = true;
    media.compressProgress = 0.0;
    _notifyProgress(media);

    // Показываем предупреждение о трафике один раз.
    if (!_trafficWarningShown && !_compressor.isLoaded) {
      _trafficWarningShown = true;
      onError?.call('ffmpegTrafficWarning');
    }

    Uint8List? compressedBytes;
    try {
      await _compressor.initialize();

      final progressSub = _compressor.progressStream.listen((progress) {
        media.compressProgress = progress.clamp(0.0, 1.0);
        _notifyProgress(media);
      });

      compressedBytes = await _compressor.compressVideo(bytes);
      await progressSub.cancel();
    } catch (e) {
      if (kDebugMode) debugPrint('Video compression failed: $e');
      media.isCompressing = false;
      media.compressProgress = 0.0;
      _notifyProgress(media);
      onError?.call('compression_failed');
      return;
    }

    // Проверяем эффективность сжатия.
    if (compressedBytes == null ||
        compressedBytes.isEmpty ||
        compressedBytes.length >= bytes.length) {
      media.isCompressing = false;
      media.compressProgress = 0.0;
      _notifyProgress(media);
      onError?.call('compression_ineffective');
      return;
    }

    media.compressedSize = compressedBytes.length;
    media.fileSize = bytes.length;
    media.webBytes = compressedBytes;
    media.isCompressing = false;
    media.compressProgress = 1.0;
    _notifyProgress(media);

    // Если медиа было отменено (например, вопрос удалён), не загружаем
    // результат и не держим сжатые байты в памяти.
    if (_cancelled.remove(media)) {
      media.webBytes = null;
      _notifyProgress(media);
      if (kDebugMode) {
        debugPrint('Video upload cancelled after compression: ${task.fileName}');
      }
      return;
    }

    // Загрузка на сервер.
    media.isUploading = true;
    media.uploadProgress = 0.0;
    _notifyProgress(media);

    try {
      final result = await uploadWithProgress(
        fileBytes: compressedBytes,
        fileName: task.fileName,
        mimeType: task.mimeType,
        relativePath: task.relativePath,
        reportId: task.reportId,
        shareToken: task.shareToken,
        onProgress: (progress) {
          media.uploadProgress = progress;
          _notifyProgress(media);
        },
        onPresigned: (fileId) {
          // Сохраняем fileId до начала PUT — если пользователь удалит
          // вопрос/ответ во время загрузки, _deleteMediaItem сможет
          // удалить файл с сервера.
          media.serverFileId = fileId;
        },
      );

      if (result.success) {
        media.serverFileId = result.serverFileId;
        media.webUrl = result.webUrl;
        media.isUploading = false;
        media.uploadProgress = 1.0;
      } else {
        media.isUploading = false;
        media.uploadProgress = 0.0;
        onError?.call(result.error ?? 'upload_failed');
      }
    } catch (e) {
      media.isUploading = false;
      media.uploadProgress = 0.0;
      if (kDebugMode) debugPrint('Video upload failed: $e');
      onError?.call('upload_failed');
    }

    _notifyProgress(media);
  }

  void _notifyProgress(MediaItem media) {
    if (_progressController.isClosed) return;
    final phase = media.isCompressing
        ? VideoProcessingPhase.compressing
        : VideoProcessingPhase.uploading;
    final value = media.isCompressing
        ? media.compressProgress
        : media.uploadProgress;
    _progressController.add(VideoUploadProgress(
      mediaId: media.name,
      phase: phase,
      value: value,
    ));
  }
}
