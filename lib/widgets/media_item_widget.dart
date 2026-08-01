// ============================================================
// MediaItemWidget — карточка медиафайла (фото/видео) в сетке ответа.
//
// Вынесен из form_fill_screen.dart при рефакторинге.
// Отображает один медиафайл с обрамлением, индикатором внимания
// и состояниями загрузки (webBytes / webUrl / локальный файл).
// ============================================================

import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/widgets/video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class MediaItemWidget extends StatelessWidget {
  final Map<String, dynamic> media;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final String? reportPath;

  const MediaItemWidget({
    super.key,
    required this.media,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    this.reportPath,
  });

  String? _getAbsolutePath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    if (reportPath == null) return relativePath;
    if (relativePath.startsWith('/') || relativePath.contains(':\\')) {
      return relativePath;
    }
    return '$reportPath/$relativePath';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                width: 2,
                color: (media['attention'] == true)
                    ? AppColors.warning
                    : AppColors.grey200,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Builder(
                builder: (context) {
                  final localPath = _getAbsolutePath(
                    media['localPath'] as String?,
                  );
                  final isImage = (media['type'] as String? ?? '').startsWith('image');
                  final webBytes = media['webBytes'] as Uint8List?;

                  if (isImage) {
                    // Web: отображаем из webBytes (freshly загруженные фото)
                    if (kIsWeb && webBytes != null) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            webBytes,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image,
                              color: Colors.red,
                            ),
                          ),
                          // Индикатор загрузки на сервер (если serverFileId ещё нет)
                          if (media['serverFileId'] == null)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    // Web: отображаем через presigned URL (фото с сервера)
                    final webUrl = media['webUrl'] as String?;
                    if (kIsWeb && webUrl != null && webUrl.isNotEmpty) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            webUrl,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      );
                    }
                    // Mobile/Desktop: отображаем из файла
                    if (!kIsWeb && localPath != null) {
                      if (!File(localPath).existsSync()) {
                        return const Icon(
                          Icons.broken_image,
                          color: Colors.red,
                        );
                      }
                      return fileImageWidget(
                        localPath,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      );
                    }
                    // Нет данных для отображения
                    return const Center(
                      child: Icon(
                        Icons.image,
                        size: 30,
                        color: AppColors.textTertiary,
                      ),
                    );
                  }

                  // Видео
                  return VideoThumbnailWidget(
                    localPath: localPath,
                    size: 70,
                    fileSize: media['fileSize'] as int?,
                    compressedSize: media['compressedSize'] as int?,
                    webBytes: webBytes,
                    isUploading: media['isUploading'] == true,
                    uploadProgress: (media['uploadProgress'] as num?)?.toDouble() ?? 0.0,
                    isCompressing: media['isCompressing'] == true,
                    compressProgress: (media['compressProgress'] as num?)?.toDouble() ?? 0.0,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
