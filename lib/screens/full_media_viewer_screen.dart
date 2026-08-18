// ============================================================
// FullMediaViewerScreen — полноэкранный просмотрщик медиафайлов.
//
// Вынесен из form_fill_screen.dart при рефакторинге.
// Открывается из карточки ответа; поддерживает:
//   - постраничное перелистывание (ZoomablePhotoViewer)
//   - зум фото: pinch (даже в середине свайпа), двойной тап
//   - свайп увеличенного фото: панорама, затем перелист страницы
//     (поведение как в галереях современных телефонов)
//   - воспроизведение видео (video_player)
//   - режим сетки с множественным выделением/удалением
// ============================================================

import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/utils/native_file_ops.dart'
    if (dart.library.html) 'package:easy_tab/utils/native_file_ops_web.dart';
import 'package:easy_tab/widgets/video_thumbnail.dart';
import 'package:easy_tab/widgets/zoomable_photo_viewer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class FullMediaViewerScreen extends StatefulWidget {
  final List mediaList;
  final int initialIndex;
  final Future<void> Function(List<int>)? onDelete;
  final String? reportPath;
  final bool startInSelectionMode;

  const FullMediaViewerScreen({
    super.key,
    required this.mediaList,
    this.initialIndex = 0,
    this.onDelete,
    this.reportPath,
    this.startInSelectionMode = false,
  });

  @override
  State<FullMediaViewerScreen> createState() => _FullMediaViewerScreenState();
}

class _FullMediaViewerScreenState extends State<FullMediaViewerScreen> {
  final ZoomablePhotoViewerController _viewerController =
      ZoomablePhotoViewerController();
  late int _currentIndex;
  bool _showGrid = false;
  final Set<int> _selectedIndices = {};
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  int? _videoIndex;

  String? _getAbsolutePath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    if (widget.reportPath == null) return relativePath;
    if (relativePath.startsWith('/') || relativePath.contains(':\\')) {
      return relativePath;
    }
    return '${widget.reportPath}/$relativePath';
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    if (widget.startInSelectionMode) {
      _showGrid = true;
      _selectedIndices.add(widget.initialIndex);
    } else {
      _initializeVideo(widget.initialIndex);
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _initializeVideo(int index) {
    // Очищаем предыдущий blob URL (если был)
    disposeVideoBytesController(_videoController);
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }

    if (index >= 0 && index < widget.mediaList.length) {
      final media = widget.mediaList[index] as Map<String, dynamic>;
      final localPath = _getAbsolutePath(media['localPath'] as String?);
      final webUrl = media['webUrl'] as String?;
      final isVideo = (media['type'] as String? ?? '').startsWith('video');

      if (isVideo) {
        _videoIndex = index;
        if (!kIsWeb && localPath != null) {
          _videoController = createFileVideoController(localPath)
            ..initialize().then((_) {
              if (mounted) {
                setState(() {});
              }
            });
        } else if (kIsWeb && webUrl != null && webUrl.isNotEmpty) {
          _videoController = VideoPlayerController.networkUrl(Uri.parse(webUrl))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {});
              }
            });
        } else if (kIsWeb) {
          // P3-58: webUrl отсутствует (видео ещё не загружено на KS3).
          // Создаём blob URL из webBytes для локального просмотра.
          final webBytes = media['webBytes'] as Uint8List?;
          if (webBytes != null && webBytes.isNotEmpty) {
            _videoController =
                createVideoControllerFromBytes(
                    webBytes,
                    media['type'] as String? ?? 'video/mp4',
                  )
                  ..initialize().then((_) {
                    if (mounted) {
                      setState(() {});
                    }
                  });
          }
        }
      } else {
        // Страница не видео — сбрасываем привязку контроллера, чтобы
        // соседние видео-страницы при перелисте не показывали чужой плеер.
        _videoIndex = null;
      }
    }
  }

  @override
  void dispose() {
    disposeVideoBytesController(_videoController);
    _videoController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (widget.onDelete != null && _selectedIndices.isNotEmpty) {
      // #17: ждём завершения удаления, иначе экран закроется раньше времени
      // и колбэк может вызвать setState после dispose.
      await widget.onDelete!(List.from(_selectedIndices));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteCurrent() async {
    if (widget.onDelete != null) {
      await widget.onDelete!([_currentIndex]);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1}/${widget.mediaList.length}'),
        actions: [
          if (_showGrid && _selectedIndices.isNotEmpty)
            TextButton(
              onPressed: _deleteSelected,
              child: Text(
                '${loc.delete} (${_selectedIndices.length})',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (!_showGrid)
            IconButton(
              icon: const Icon(Icons.grid_view),
              onPressed: () {
                setState(() {
                  _showGrid = true;
                });
              },
            ),
          if (!_showGrid)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteCurrent,
            ),
        ],
      ),
      body: _showGrid ? _buildGrid() : _buildViewer(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      padding: const EdgeInsets.all(4),
      itemCount: widget.mediaList.length,
      itemBuilder: (ctx, index) {
        final media = widget.mediaList[index] as Map<String, dynamic>;
        final isSelected = _selectedIndices.contains(index);
        final isVideo = (media['type'] as String? ?? '').startsWith('video');

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentIndex = index;
                  _showGrid = false;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _viewerController.jumpToPage(index);
                });
                _initializeVideo(index);
              },
              onLongPress: () => _toggleSelect(index),
              child: isVideo
                  ? VideoThumbnailWidget(
                      localPath: !kIsWeb
                          ? _getAbsolutePath(media['localPath'])
                          : null,
                      size: 100,
                      fileSize: media['fileSize'] as int?,
                      compressedSize: media['compressedSize'] as int?,
                      webBytes: kIsWeb
                          ? (media['webBytes'] as Uint8List?)
                          : null,
                      webUrl: kIsWeb ? (media['webUrl'] as String?) : null,
                      thumbnailUrl: kIsWeb
                          ? (media['thumbnailUrl'] as String?)
                          : null,
                    )
                  : (!kIsWeb && media['localPath'] != null
                        ? fileImageWidget(
                            _getAbsolutePath(media['localPath']) ??
                                media['localPath'],
                            fit: BoxFit.cover,
                          )
                        : (kIsWeb && (media['webUrl'] as String?) != null
                              ? Image.network(
                                  media['webUrl'] as String,
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
                                    color: Colors.grey,
                                  ),
                                )
                              : const Icon(Icons.image, color: Colors.grey))),
            ),
            if (isSelected)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, color: Colors.blue, size: 20),
              ),
            if (isVideo)
              const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(Icons.play_circle, color: Colors.white, size: 20),
              ),
          ],
        );
      },
    );
  }

  Widget _buildViewer() {
    return Column(
      children: [
        Expanded(
          // ZoomablePhotoViewer решает арену жестов целиком:
          //   - pinch-зум доступен в любой момент, даже в середине свайпа;
          //   - свайп увеличенного фото панорамирует его, а перелист
          //     страницы начинается только когда фото пролистано до края
          //     (панорамирование и листание работают всегда);
          //   - при масштабе 1 свайп сразу листает фото;
          //   - при отпускании смещение > 1/4 ширины экрана → перелист.
          child: ZoomablePhotoViewer(
            controller: _viewerController,
            itemCount: widget.mediaList.length,
            initialIndex: _currentIndex,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _initializeVideo(index);
            },
            imageProvider: _imageProviderFor,
            pageBuilder: _buildPageFallback,
          ),
        ),
        // Video controls
        if (_videoController != null && _videoController!.value.isInitialized)
          _buildVideoControls(),
      ],
    );
  }

  /// Возвращает ImageProvider для страницы-фото или null для видео
  /// (видео и «пустые» страницы отрисовываются через [pageBuilder]).
  ImageProvider? _imageProviderFor(int index) {
    final media = widget.mediaList[index] as Map<String, dynamic>;
    if ((media['type'] as String? ?? '').startsWith('video')) return null;

    final localPath = _getAbsolutePath(media['localPath'] as String?);
    final webUrl = media['webUrl'] as String?;
    final webBytes = media['webBytes'] as Uint8List?;

    if (!kIsWeb && localPath != null) {
      return fileImageProvider(localPath);
    }
    if (kIsWeb && webBytes != null) {
      return MemoryImage(webBytes);
    }
    if (kIsWeb && webUrl != null && webUrl.isNotEmpty) {
      return NetworkImage(webUrl);
    }
    // Источник недоступен — отрисуем заглушку через pageBuilder.
    return null;
  }

  Widget _buildPageFallback(int index) {
    final media = widget.mediaList[index] as Map<String, dynamic>;
    final isVideo = (media['type'] as String? ?? '').startsWith('video');

    if (isVideo) {
      // Плеер показываем только на текущей странице видео; соседние
      // видео-страницы (при перелисте) — иконка-заглушка.
      if (index == _videoIndex) return _buildVideoPlayer(index);
      return const Center(
        child: Icon(Icons.videocam, size: 60, color: Colors.white),
      );
    }
    // Фото без доступного источника.
    return const Center(
      child: Icon(Icons.broken_image, size: 60, color: Colors.white),
    );
  }

  Widget _buildVideoPlayer(int index) {
    // #14: плеер привязан к конкретной странице через _videoIndex, который
    // выставляется синхронно в _initializeVideo ДО создания контроллера.
    // Параметр index делает привязку явной (контроллер всегда текущей страницы).
    final bool isInitialized =
        index == _videoIndex &&
        _videoController != null &&
        _videoController!.value.isInitialized;

    if (isInitialized) {
      return Center(
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            if (!_isPlaying)
              Center(
                child: IconButton(
                  icon: const Icon(Icons.play_circle_filled, size: 60),
                  color: Colors.white,
                  onPressed: () {
                    setState(() {
                      _isPlaying = true;
                      _videoController!.play();
                    });
                  },
                ),
              ),
          ],
        ),
      );
    }

    return const Center(
      child: Icon(Icons.videocam, size: 60, color: Colors.white),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            color: Colors.white,
            onPressed: () {
              setState(() {
                if (_isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
                }
                _isPlaying = !_isPlaying;
              });
            },
          ),
          Expanded(
            child: VideoProgressIndicator(
              _videoController!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.blue,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
