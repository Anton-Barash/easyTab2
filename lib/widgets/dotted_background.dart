import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'dotted_pattern_painter.dart';

/// Фоновый виджет с точечным узором.
///
/// Заменяет повторяющийся паттерн Positioned.fill + Container + CustomPaint
/// в main.dart, template_select_screen.dart, reports_screen.dart, form_fill_screen.dart.
class DottedBackground extends StatelessWidget {
  const DottedBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background,
        child: CustomPaint(painter: DottedPatternPainter()),
      ),
    );
  }
}
