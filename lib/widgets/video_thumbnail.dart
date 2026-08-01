// ============================================================
// VideoThumbnailWidget — миниатюра видео с индикатором загрузки.
//
// Вынесен из form_fill_screen.dart при рефакторинге.
// Отображает:
//   - кадр видео (через video_thumbnail на native)
//   - цветную точку статуса сжатия (зелёная/красная/серая)
//   - размер файла
//   - индикатор прогресса загрузки на сервер (P3-52)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String? localPath;
  final int size;
  final int? fileSize;
  final int? compressedSize;
  final Uint8List? webBytes;
  final bool isUploading;
  final double uploadProgress;
  final bool isCompressing;
  final double compressProgress;

  const VideoThumbnailWidget({
    super.key,
    this.localPath,
    this.size = 80,
    this.fileSize,
    this.compressedSize,
    this.webBytes,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.isCompressing = false,
    this.compressProgress = 0.0,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    if (kIsWeb || widget.localPath == null) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.localPath!,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.size,
        maxHeight: widget.size,
        quality: 50,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeToShow = widget.compressedSize ?? widget.fileSize;
    final isCompressed = widget.compressedSize != null;
    final needsCompression =
        widget.fileSize != null && widget.fileSize! > 5 * 1024 * 1024;

    Color dotColor;
    if (isCompressed) {
      dotColor = Colors.green;
    } else if (needsCompression) {
      dotColor = Colors.red;
    } else {
      dotColor = Colors.grey;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_thumbnailBytes != null)
          Image.memory(
            _thumbnailBytes!,
            width: widget.size.toDouble(),
            height: widget.size.toDouble(),
            fit: BoxFit.cover,
          )
        else
          const Center(
            child: Icon(Icons.videocam, size: 30, color: Color(0xFF999999)),
          ),
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
            ),
          ),
        ),
        if (sizeToShow != null && !widget.isUploading && !widget.isCompressing)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _formatFileSize(sizeToShow),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        // Индикатор фонового сжатия видео (ffmpeg.wasm).
        // Не блокирует UI — пользователь может работать с приложением.
        if (widget.isCompressing)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    child: LinearProgressIndicator(
                      value: widget.compressProgress > 0 &&
                              widget.compressProgress < 1.0
                          ? widget.compressProgress
                          : null,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.compressProgress > 0
                        ? '${(widget.compressProgress * 100).toStringAsFixed(0)}%'
                        : 'Сжатие...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // P3-52: индикатор загрузки видео на сервер.
        // Фазы (presigned URL flow):
        //   1. uploadProgress == 0 — presign (быстро), indeterminate + "Загрузка..."
        //   2. 0 < uploadProgress < 1 — прямая загрузка в KS3, determinate + "%"
        //   3. uploadProgress >= 1, isUploading — confirm (быстро), indeterminate + "Завершение..."
        if (widget.isUploading)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    child: LinearProgressIndicator(
                      value: (widget.uploadProgress > 0 && widget.uploadProgress < 1.0)
                          ? widget.uploadProgress
                          : null,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.uploadProgress >= 1.0
                        ? 'Завершение...'
                        : widget.uploadProgress > 0
                            ? '${(widget.uploadProgress * 100).toStringAsFixed(0)}%'
                            : 'Загрузка...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
