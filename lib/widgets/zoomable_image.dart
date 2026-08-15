// ============================================================
// ZoomableImage — обёртка для просмотра изображений с зумом.
//
// Современный UX, как в галереях телефона:
//   - pinch-to-zoom (щипок), до [maxScale]
//   - двойной тап — зум 2.5x в точку касания / сброс
//   - панорамирование активно только при зуме, чтобы не
//     конфликтовать со свайпом страниц PageView
// ============================================================

import 'package:flutter/material.dart';

class ZoomableImage extends StatefulWidget {
  final Widget child;

  /// Уведомляет о смене состояния зума (например, чтобы
  /// родитель мог заблокировать прокрутку страниц).
  final ValueChanged<bool>? onZoomChanged;

  final double maxScale;

  /// Масштаб при двойном тапе.
  final double doubleTapScale;

  const ZoomableImage({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.maxScale = 5.0,
    this.doubleTapScale = 2.5,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage>
    with SingleTickerProviderStateMixin {
  static const _zoomDuration = Duration(milliseconds: 200);

  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;

  Offset? _doubleTapPosition;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: _zoomDuration)
      ..addListener(() {
        final animation = _zoomAnimation;
        if (animation != null) _transformController.value = animation.value;
      });
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final position = _doubleTapPosition;
    if (position == null) return;
    _animateTo(_zoomMatrixAt(position, widget.doubleTapScale));
  }

  /// Матрица масштабирования вокруг точки касания:
  /// точка [position] остаётся под пальцем после зума.
  static Matrix4 _zoomMatrixAt(Offset position, double scale) {
    return Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: widget.maxScale,
        // Панорамирование только в зуме: иначе горизонтальные
        // свайпы перехватываются и ломают перелистывание PageView.
        panEnabled: _isZoomed,
        child: widget.child,
      ),
    );
  }
}
