import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/report_models.dart';
import '../utils/video_thumbnail_generator.dart';
import '../utils/web_video_compressor.dart';
import 'upload_helper.dart';

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
  final int qualityLevel;

  _VideoUploadTask({
    required this.media,
    required this.originalBytes,
    required this.fileName,
    required this.mimeType,
    required this.relativePath,
    this.reportId,
    this.shareToken,
    this.qualityLevel = 3,
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
  ///
  /// [qualityLevel]: 1=high, 2=medium, 3=low (default).
  Future<void> enqueue({
    required MediaItem media,
    required Uint8List originalBytes,
    required String fileName,
    required String mimeType,
    required String relativePath,
    int? reportId,
    String? shareToken,
    int qualityLevel = 3,
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
      qualityLevel: qualityLevel,
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

      compressedBytes = await _compressor.compressVideo(
        bytes,
        qualityLevel: task.qualityLevel,
      );
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
    // Если сжатие не дало результата — загружаем оригинал.
    final bool useOriginal;
    if (compressedBytes == null ||
        compressedBytes.isEmpty ||
        compressedBytes.length >= bytes.length) {
      if (kDebugMode) {
        debugPrint(
          'Video compression ineffective for ${task.fileName}, '
          'uploading original (${bytes.length} bytes)',
        );
      }
      useOriginal = true;
      media.compressedSize = bytes.length;
    } else {
      useOriginal = false;
      media.compressedSize = compressedBytes.length;
    }

    final Uint8List uploadBytes;
    if (useOriginal) {
      uploadBytes = bytes;
    } else {
      uploadBytes = compressedBytes!;
    }
    media.fileSize = bytes.length;
    media.webBytes = uploadBytes;
    media.isCompressing = false;
    media.compressProgress = 1.0;
    _notifyProgress(media);

    // Если медиа было отменено (например, вопрос удалён), не загружаем
    // результат и не держим сжатые байты в памяти.
    if (_cancelled.remove(media)) {
      media.webBytes = null;
      _notifyProgress(media);
      if (kDebugMode) {
        debugPrint(
          'Video upload cancelled after compression: ${task.fileName}',
        );
      }
      return;
    }

    // Загрузка на сервер.
    media.isUploading = true;
    media.uploadProgress = 0.0;
    _notifyProgress(media);

    try {
      final result = await uploadWithProgress(
        fileBytes: uploadBytes,
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

        // Генерируем и загружаем превью (кадр из видео).
        _uploadThumbnail(
          media: media,
          videoBytes: uploadBytes,
          videoFileName: task.fileName,
          videoRelativePath: task.relativePath,
          reportId: task.reportId,
          shareToken: task.shareToken,
        );
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
    _progressController.add(
      VideoUploadProgress(mediaId: media.name, phase: phase, value: value),
    );
  }

  /// Генерирует и загружает превью (кадр из видео) на сервер.
  Future<void> _uploadThumbnail({
    required MediaItem media,
    required Uint8List videoBytes,
    required String videoFileName,
    required String videoRelativePath,
    int? reportId,
    String? shareToken,
  }) async {
    try {
      final generator = VideoThumbnailGenerator.create();
      final thumbnailBytes = await generator.generateThumbnail(
        videoBytes,
        maxWidth: 256,
        maxHeight: 256,
        quality: 70,
      );

      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('Thumbnail generation returned null for $videoFileName');
        }
        return;
      }

      final thumbFileName =
          'thumb_${videoFileName.split('.').first}.jpg';
      final thumbRelativePath = videoRelativePath.replaceAll(
        videoFileName,
        thumbFileName,
      );

      if (kDebugMode) {
        debugPrint(
          'Uploading thumbnail: $thumbFileName (${thumbnailBytes.length} bytes)',
        );
      }

      final thumbResult = await uploadWithProgress(
        fileBytes: thumbnailBytes,
        fileName: thumbFileName,
        mimeType: 'image/jpeg',
        relativePath: thumbRelativePath,
        reportId: reportId,
        shareToken: shareToken,
        onProgress: (_) {},
        onPresigned: (fileId) {
          media.thumbnailServerFileId = fileId;
        },
      );

      if (thumbResult.success) {
        media.thumbnailServerFileId = thumbResult.serverFileId;
        _notifyProgress(media);
        if (kDebugMode) {
          debugPrint(
            'Thumbnail uploaded: $thumbFileName → fileId=${thumbResult.serverFileId}',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            'Thumbnail upload failed: $thumbFileName — ${thumbResult.error}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Thumbnail error for $videoFileName: $e');
      }
    }
  }
}
