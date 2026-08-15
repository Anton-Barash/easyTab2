// ============================================================
// ZoomablePhotoViewer — полноэкранный просмотрщик фотографий
// с ручным управлением жестами (как в галереях современных
// телефонов, например Vivo).
//
// Поведение:
//   - Зум (pinch) и свайп работают ОДНОВРЕМЕННО: во время движения
//     пальца второй палец может начать масштабирование, это не
//     отменяет ни свайп, ни зум.
//   - Если фото не увеличено — горизонтальный свайп сразу листает
//     страницы (соседние фото «раздвигаются» вместе с пальцем).
//   - Если фото увеличено — свайп сначала панорамирует его внутри
//     экрана; когда фото пролистано до края (вся его ширина вышла
//     за экран), дальнейший свайп начинает листать страницы.
//   - При отпускании: если фото/страница уехали за экран больше чем
//     на 1/4 ширины экрана — автоматический перелист, иначе плавный
//     откат на место.
//   - Двойной тап — зум до 2.5x в точку тапа / возврат к 1x.
//
// Технически: вместо PageView + extended_image используем один
// GestureDetector с onScaleUpdate — он объединяет и панорамирование
// (один палец), и зум (два пальца), и сам решает, куда отдать
// горизонтальное смещение (внутрь фото или на перелист страницы).
// Соседние страницы рисуются рядом и двигаются вместе с _pageOffset,
// давая эффект «раздвигания» фотографий при свайпе.
// ============================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Контроллер для [ZoomablePhotoViewer]: позволяет программно
/// перейти на конкретную страницу (например, из режима сетки).
class ZoomablePhotoViewerController {
  int _page = 0;
  _ZoomablePhotoViewerState? _state;

  int get page => _page;

  void _attach(_ZoomablePhotoViewerState state) {
    _page = state._current;
    _state = state;
  }

  void _detach(_ZoomablePhotoViewerState state) {
    if (_state == state) _state = null;
  }

  /// Мгновенный переход на страницу [page] (без анимации).
  void jumpToPage(int page) {
    _page = page;
    _state?.jumpToPage(page);
  }
}

/// Тип текущей анимации (у контроллера анимации один, поэтому
/// различаем, что именно мы анимируем).
enum _AnimKind { none, pageOffset, scale }

class ZoomablePhotoViewer extends StatefulWidget {
  const ZoomablePhotoViewer({
    super.key,
    required this.itemCount,
    this.initialIndex = 0,
    this.controller,
    this.onPageChanged,
    this.imageProvider,
    this.pageBuilder,
    this.maxScale = 4.0,
  });

  /// Количество страниц.
  final int itemCount;

  /// Начальная страница.
  final int initialIndex;

  /// Внешний контроллер для программной смены страницы.
  final ZoomablePhotoViewerController? controller;

  /// Вызывается после фактической смены страницы.
  final ValueChanged<int>? onPageChanged;

  /// Возвращает ImageProvider для зумируемой страницы (фото) или
  /// null, если страница не зумируемая (например, видео).
  final ImageProvider? Function(int index)? imageProvider;

  /// Запасная отрисовка страницы, для которой imageProvider вернул
  /// null (видео/заглушка).
  final Widget Function(int index)? pageBuilder;

  /// Максимальный масштаб зума.
  final double maxScale;

  @override
  State<ZoomablePhotoViewer> createState() => _ZoomablePhotoViewerState();
}

class _ZoomablePhotoViewerState extends State<ZoomablePhotoViewer>
    with SingleTickerProviderStateMixin {
  // ---- Состояние просмотра ----
  int _current = 0;
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  /// Горизонтальное смещение «перелиста» страницы (в px). Соседние
  /// страницы двигаются вместе с ним, раздвигая друг друга.
  double _pageOffset = 0.0;

  // ---- Состояние активного жеста ----
  double _startScale = 1.0;
  Offset _startFocal = Offset.zero;
  Offset _startPan = Offset.zero;
  double _startPageOffset = 0.0;

  // ---- Анимация ----
  late final AnimationController _animCtrl;
  _AnimKind _animKind = _AnimKind.none;
  double _animFrom = 0.0;
  double _animTo = 0.0;
  int _flipDir = 0;
  double _scaleFrom = 1.0;
  double _scaleTo = 1.0;
  Offset _panFrom = Offset.zero;
  Offset _scaleAnchor = Offset.zero;
  bool _resetPanOnScale = false;

  // ---- Данные изображений ----
  final Map<int, Size?> _intrinsicSizes = {};
  final Set<int> _sizeLoading = {};

  Size _viewport = Size.zero;
  Offset _doubleTapPos = Offset.zero;

  bool get _isCurrentZoomable => widget.imageProvider?.call(_current) != null;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, math.max(0, widget.itemCount - 1));
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onAnimTick)
      ..addStatusListener(_onAnimStatus);
    widget.controller?._attach(this);
    _scheduleNeighborSizes();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _animCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // Загрузка интринсивных размеров изображений (для границ панорамы)
  // ------------------------------------------------------------

  void _scheduleNeighborSizes() {
    _scheduleSize(_current);
    if (_current > 0) _scheduleSize(_current - 1);
    if (_current < widget.itemCount - 1) _scheduleSize(_current + 1);
  }

  void _scheduleSize(int index) {
    final provider = widget.imageProvider?.call(index);
    if (provider == null) return;
    if (_intrinsicSizes.containsKey(index) || _sizeLoading.contains(index)) {
      return;
    }
    _sizeLoading.add(index);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!mounted) return;
      setState(() {
        _intrinsicSizes[index] = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        _sizeLoading.remove(index);
      });
    }, onError: (Object error, StackTrace? stackTrace) {
      stream.removeListener(listener);
      _sizeLoading.remove(index);
    });
    stream.addListener(listener);
  }

  /// Размер отрисованного фото внутри вьюпорта при масштабе 1
  /// (прямоугольник BoxFit.contain). Пока размер не известен —
  /// используем размер вьюпорта.
  Size _contentSizeAt(int index) {
    final intrinsic = _intrinsicSizes[index];
    final w = _viewport.width;
    final h = _viewport.height;
    if (w <= 0 || h <= 0) return Size.zero;
    if (intrinsic == null) return Size(w, h);
    final fit = math.min(w / intrinsic.width, h / intrinsic.height);
    return Size(intrinsic.width * fit, intrinsic.height * fit);
  }

  // ------------------------------------------------------------
  // Жесты: объединённое панорамирование + зум + перелист
  // ------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d) {
    _animCtrl.stop();
    _animKind = _AnimKind.none;
    _startScale = _scale;
    _startFocal = d.focalPoint;
    _startPan = _pan;
    _startPageOffset = _pageOffset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final w = _viewport.width;
    final h = _viewport.height;
    if (w <= 0 || h <= 0) return;

    // 1. Масштаб (зум доступен всегда, даже на видео — там он не меняется).
    final double scale = _isCurrentZoomable
        ? (_startScale * d.scale).clamp(1.0, widget.maxScale)
        : 1.0;

    // 2. Панорамирование с якорем на фокальной точке (точке между
    //    пальцами): точка фото, над которой был палец в начале жеста,
    //    остаётся под текущей фокальной точкой. Зум «растёт» из точки
    //    между пальцами, а не из центра экрана.
    //    Формула выводится из screen = scale*(p - center) + center + pan.
    final Offset center = Offset(w / 2, h / 2);
    final Offset contentDelta =
        (_startFocal - center - _startPan) / _startScale;
    final Offset targetPan = d.focalPoint - center - contentDelta * scale;

    // 3. Границы панорамы: нельзя увести фото за край, пока его можно
    //    перемещать внутри экрана.
    final contentSize = _contentSizeAt(_current);
    final maxX = math.max(0.0, (contentSize.width * scale - w) / 2);
    final maxY = math.max(0.0, (contentSize.height * scale - h) / 2);
    final panX = targetPan.dx.clamp(-maxX, maxX);
    final panY = targetPan.dy.clamp(-maxY, maxY);

    // 4. Избыток горизонтального движения (фото уже пролистано до края)
    //    уходит в перелист страницы — соседние фото раздвигаются.
    final pageOffset = (_startPageOffset + (targetPan.dx - panX)).clamp(-w, w);

    setState(() {
      _scale = scale;
      _pan = Offset(panX, panY);
      _pageOffset = pageOffset;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final w = _viewport.width;
    if (w <= 0) return;

    final target = _pageOffset > 0 ? _current - 1 : _current + 1;
    final canFlip = target >= 0 && target < widget.itemCount;

    if (_pageOffset.abs() > w * 0.25 && canFlip) {
      // Пролистано больше 1/4 ширины экрана → перелист.
      final dir = _pageOffset > 0 ? -1 : 1;
      _startFlipAnimation(dir, _pageOffset > 0 ? w : -w);
    } else {
      // Недостаточно смещения → плавный откат.
      _startPageOffsetAnimation(0.0);
    }
  }

  void _onDoubleTapDown(TapDownDetails d) {
    _doubleTapPos = d.localPosition;
  }

  void _onDoubleTap() {
    if (!_isCurrentZoomable) return;
    _animCtrl.stop();
    _animKind = _AnimKind.none;
    if (_scale > 1.01) {
      // Возврат к 1x (по центру экрана).
      _animateScaleTo(1.0, anchor: _doubleTapPos, resetPan: true);
    } else {
      // Зум в точку тапа.
      _animateScaleTo(math.min(2.5, widget.maxScale), anchor: _doubleTapPos);
    }
  }

  /// Программный переход на страницу (без анимации).
  void jumpToPage(int page) {
    final target = page.clamp(0, math.max(0, widget.itemCount - 1)).toInt();
    if (target == _current) return;
    _animCtrl.stop();
    _animKind = _AnimKind.none;
    setState(() {
      _current = target;
      _pageOffset = 0.0;
      _scale = 1.0;
      _pan = Offset.zero;
    });
    widget.onPageChanged?.call(_current);
    _scheduleNeighborSizes();
  }

  // ------------------------------------------------------------
  // Анимации
  // ------------------------------------------------------------

  void _startPageOffsetAnimation(double to) {
    _animKind = _AnimKind.pageOffset;
    _animFrom = _pageOffset;
    _animTo = to;
    _flipDir = 0;
    _animCtrl.forward(from: 0);
  }

  void _startFlipAnimation(int dir, double to) {
    _animKind = _AnimKind.pageOffset;
    _animFrom = _pageOffset;
    _animTo = to;
    _flipDir = dir;
    _animCtrl.forward(from: 0);
  }

  void _animateScaleTo(double to, {required Offset anchor, bool resetPan = false}) {
    _animKind = _AnimKind.scale;
    _scaleFrom = _scale;
    _scaleTo = to.clamp(1.0, widget.maxScale);
    _panFrom = _pan;
    _scaleAnchor = anchor;
    _resetPanOnScale = resetPan;
    _animCtrl.forward(from: 0);
  }

  void _onAnimTick() {
    final t = _animCtrl.value;
    switch (_animKind) {
      case _AnimKind.pageOffset:
        final eased = Curves.easeOutCubic.transform(t);
        setState(() {
          _pageOffset = _animFrom + (_animTo - _animFrom) * eased;
        });
      case _AnimKind.scale:
        final eased = Curves.easeOut.transform(t);
        final scale = _scaleFrom + (_scaleTo - _scaleFrom) * eased;
        Offset pan;
        if (_resetPanOnScale) {
          // Уменьшение до 1x — плавно возвращаем центр.
          pan = Offset.lerp(_panFrom, Offset.zero, eased)!;
        } else {
          // Увеличение — точка тапа остаётся на месте (та же формула,
          // что и в жесте: якорь в точке, а не в центре экрана).
          final w = _viewport.width;
          final h = _viewport.height;
          final center = Offset(w / 2, h / 2);
          final contentDelta = (_scaleAnchor - center - _panFrom) / _scaleFrom;
          final raw = _scaleAnchor - center - contentDelta * scale;
          final contentSize = _contentSizeAt(_current);
          final maxX = math.max(0.0, (contentSize.width * scale - w) / 2);
          final maxY = math.max(0.0, (contentSize.height * scale - h) / 2);
          pan = Offset(raw.dx.clamp(-maxX, maxX), raw.dy.clamp(-maxY, maxY));
        }
        setState(() {
          _scale = scale;
          _pan = pan;
        });
      case _AnimKind.none:
        break;
    }
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_animKind == _AnimKind.pageOffset && _flipDir != 0) {
      final next = _current + _flipDir;
      if (next >= 0 && next < widget.itemCount) {
        setState(() {
          _current = next;
          _pageOffset = 0.0;
          _scale = 1.0;
          _pan = Offset.zero;
        });
        widget.onPageChanged?.call(_current);
        _scheduleNeighborSizes();
      } else {
        setState(() => _pageOffset = 0.0);
      }
    }
    _animKind = _AnimKind.none;
    _flipDir = 0;
  }

  // ------------------------------------------------------------
  // Отрисовка
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      _viewport = Size(w, h);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final i in _visibleIndices())
                Positioned(
                  left: (i - _current) * w + _pageOffset,
                  top: 0,
                  width: w,
                  height: h,
                  child: ClipRect(child: _buildPage(i, w, h)),
                ),
            ],
          ),
        ),
      );
    });
  }

  List<int> _visibleIndices() {
    final list = <int>[_current - 1, _current, _current + 1];
    return list.where((i) => i >= 0 && i < widget.itemCount).toList();
  }

  Widget _buildPage(int index, double w, double h) {
    final provider = widget.imageProvider?.call(index);
    final bool zoomable = provider != null;

    final Widget content;
    if (provider != null) {
      content = Image(
        image: provider,
        fit: BoxFit.contain,
        width: w,
        height: h,
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
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, size: 60, color: Colors.white),
        ),
      );
    } else if (widget.pageBuilder != null) {
      content = widget.pageBuilder!(index);
    } else {
      content = const SizedBox.shrink();
    }

    // Соседние страницы — без зума, просто фото/видео.
    if (index != _current) {
      return ColoredBox(color: Colors.black, child: content);
    }

    // Текущая страница: масштаб вокруг центра экрана + панорамирование.
    final transformed = Transform(
      transform: Matrix4.identity()
        ..translateByDouble(w / 2 + _pan.dx, h / 2 + _pan.dy, 0.0, 1.0)
        ..scaleByDouble(_scale, _scale, 1.0, 1.0)
        ..translateByDouble(-w / 2, -h / 2, 0.0, 1.0),
      child: ColoredBox(color: Colors.black, child: content),
    );

    // Двойной тап для зума — только на зумируемом фото (на видео
    // отдельный GestureDetector добавил бы задержку кнопке play).
    if (!zoomable) return transformed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: _onDoubleTap,
      child: transformed,
    );
  }
}
