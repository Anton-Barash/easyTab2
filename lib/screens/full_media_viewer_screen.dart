// ============================================================
// FullMediaViewerScreen — полноэкранный просмотрщик медиафайлов.
//
// Вынесен из form_fill_screen.dart при рефакторинге.
// Открывается из карточки ответа; поддерживает:
//   - постраничное перелистывание (PageView)
//   - воспроизведение видео (video_player)
//   - режим сетки с множественным выделением/удалением
// ============================================================

import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/utils/native_file_ops.dart'
    if (dart.library.html) 'package:easy_tab/utils/native_file_ops_web.dart';
import 'package:easy_tab/widgets/video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class FullMediaViewerScreen extends StatefulWidget {
  final List mediaList;
  final int initialIndex;
  final Function(List<int>)? onDelete;
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
  late final PageController _pageController;
  late int _currentIndex;
  bool _showGrid = false;
  final Set<int> _selectedIndices = {};
  VideoPlayerController? _videoController;
  bool _isPlaying = false;

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
    _pageController = PageController(initialPage: _currentIndex);

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
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  void _deleteSelected() {
    if (widget.onDelete != null && _selectedIndices.isNotEmpty) {
      widget.onDelete!(List.from(_selectedIndices));
    }
    Navigator.pop(context);
  }

  void _deleteCurrent() {
    if (widget.onDelete != null) {
      widget.onDelete!([_currentIndex]);
    }
    Navigator.pop(context);
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
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(index);
                  }
                });
                _initializeVideo(index);
              },
              onLongPress: () => _toggleSelect(index),
              child: isVideo
                  ? (!kIsWeb && media['localPath'] != null
                        ? VideoThumbnailWidget(
                            localPath: _getAbsolutePath(media['localPath']),
                            size: 100,
                            fileSize: media['fileSize'] as int?,
                            compressedSize: media['compressedSize'] as int?,
                          )
                        : (kIsWeb && (media['webUrl'] as String?) != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      media['webUrl'] as String,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Icon(
                                        Icons.play_circle,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                )
                              : const Icon(Icons.videocam, color: Colors.grey)))
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
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaList.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _initializeVideo(index);
            },
            itemBuilder: (ctx, index) {
              final media = widget.mediaList[index] as Map<String, dynamic>;
              final isVideo = (media['type'] as String? ?? '').startsWith(
                'video',
              );

              if (isVideo) {
                return _buildVideoPlayer(index);
              } else {
                final localPath = _getAbsolutePath(
                  media['localPath'] as String?,
                );
                final webUrl = media['webUrl'] as String?;
                return Center(
                  child: (!kIsWeb && localPath != null)
                      ? fileImageWidget(localPath, fit: BoxFit.contain)
                      : (kIsWeb && webUrl != null && webUrl.isNotEmpty
                            ? InteractiveViewer(
                                child: Image.network(
                                  webUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(
                                      child: SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.image,
                                size: 60,
                                color: Colors.white,
                              )),
                );
              }
            },
          ),
        ),
        // Video controls
        if (_videoController != null && _videoController!.value.isInitialized)
          _buildVideoControls(),
      ],
    );
  }

  Widget _buildVideoPlayer(int index) {
    final media = widget.mediaList[index] as Map<String, dynamic>;
    final localPath = _getAbsolutePath(media['localPath'] as String?);
    final webUrl = media['webUrl'] as String?;

    final bool isInitialized =
        _videoController != null && _videoController!.value.isInitialized;

    if (!kIsWeb && localPath != null && isInitialized) {
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

    if (kIsWeb && webUrl != null && webUrl.isNotEmpty && isInitialized) {
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
          IconButton(
            icon: const Icon(Icons.fullscreen),
            color: Colors.white,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
