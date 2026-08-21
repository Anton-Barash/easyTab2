import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Фоновый виджет с warp-звёздами (аналог сплэша index.html).
///
/// Включается через настройку [SettingsState.starsBackground].
/// Рисуется через CustomPaint + AnimationController — не добавляет
/// сетевых запросов и работает на всех платформах.
class StarBackground extends StatefulWidget {
  const StarBackground({super.key});

  @override
  State<StarBackground> createState() => _StarBackgroundState();
}

class _StarBackgroundState extends State<StarBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _StarField _field;

  @override
  void initState() {
    super.initState();
    _field = _StarField();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _StarPainter(_field, _controller.value),
          ),
        ),
      ),
    );
  }
}

/// Состояние одной звезды (логика аналогична JS-версии в index.html).
class _Star {
  double x;
  double y;
  double z;
  double v;
  double b;
  double? px;
  double? py;

  _Star({
    required this.x,
    required this.y,
    required this.z,
    required this.v,
    required this.b,
  });
}

/// Пул звёзд: рождаются в центре, разлетаются к краям экрана.
class _StarField {
  static const int _count = 120;
  final List<_Star> _stars = [];
  double _maxZ = 1;

  _StarField() {
    final rng = Random();
    for (int i = 0; i < _count; i++) {
      _stars.add(_spawn(rng, initial: true));
    }
  }

  _Star _spawn(Random rng, {required bool initial}) {
    final star = _Star(
      x: (rng.nextDouble() - 0.5) * 2000,
      y: (rng.nextDouble() - 0.5) * 2000,
      // Новая звезда — глубоко (проецируется почти в центр). При первой
      // заливке раскидываем по всей глубине, чтобы небо не было пустым.
      z: _maxZ * (initial ? rng.nextDouble() * 1.2 : 1.4),
      v: 0.7 + rng.nextDouble() * 0.6,
      b: 0.7 + rng.nextDouble() * 0.3,
    );
    star.px = null;
    star.py = null;
    return star;
  }

  /// Обновляет состояние всех звёзд под размер [size] и текущий прогресс
  /// [t] анимации, рисуя их через [canvas]. Возвращает true, если нужен
  /// перерисов в следующем кадре (всегда, пока цикл анимации идёт).
  void paint(Canvas canvas, Size size, double t) {
    final rng = Random();
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (final s in _stars) {
      final nx = cx + (s.x / s.z) * cx;
      final ny = cy + (s.y / s.z) * cx;
      final depth = max(0.0, 1 - s.z / _maxZ); // 0 далеко → 1 близко

      if (s.px != null) {
        final shade = ((165 - depth * 95) * s.b).round();
        final alpha = min(1.0, depth * 4);
        final paint = Paint()
          ..color = Color.fromRGBO(shade, shade, shade, alpha)
          ..strokeWidth = 0.6 + depth * 2.8
          ..strokeCap = StrokeCap.round;
        // Стрик «хвост → голова» по направлению полёта.
        canvas.drawLine(
          Offset(s.px!, s.py!),
          Offset(nx, ny),
          paint,
        );
      }

      s.px = nx;
      s.py = ny;
      s.z -= (2.5 + depth * 7) * s.v; // ближе — быстрее

      // Улетела за экран или «сквозь камеру» — респавн в центре.
      if (nx < -60 ||
          nx > size.width + 60 ||
          ny < -60 ||
          ny > size.height + 60 ||
          s.z < 1) {
        _stars[_stars.indexOf(s)] = _spawn(rng, initial: false);
      }
    }
    _maxZ = size.width;
  }
}

class _StarPainter extends CustomPainter {
  final _StarField _field;
  final double _t;

  _StarPainter(this._field, this._t);

  @override
  void paint(Canvas canvas, Size size) {
    // Заполняем фон цветом приложения.
    final bg = Paint()..color = AppColors.background;
    canvas.drawRect(Offset.zero & size, bg);
    _field.paint(canvas, size, _t);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate._t != _t;
}
