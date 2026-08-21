import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import 'dotted_pattern_painter.dart';
import 'star_background.dart';

/// Фоновый виджет главного экрана.
///
/// По умолчанию рисует точечный узор ([DottedPatternPainter]). Если в
/// настройках включён «Звёздный фон» ([SettingsState.starsBackground]),
/// вместо точек показывается анимированное звёздное небо ([StarBackground]).
///
/// Заменяет повторяющийся паттерн Positioned.fill + Container + CustomPaint
/// в main.dart, template_select_screen.dart, reports_screen.dart, form_fill_screen.dart.
class DottedBackground extends StatelessWidget {
  const DottedBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    if (settings.starsBackground) {
      return const StarBackground();
    }
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background,
        child: CustomPaint(painter: DottedPatternPainter()),
      ),
    );
  }
}
