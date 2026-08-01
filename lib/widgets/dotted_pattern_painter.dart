import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// P2-28: Вынесен из 4 файлов (main.dart, form_fill_screen.dart,
/// template_select_screen.dart, reports_screen.dart).
///
/// Рисует фоновый узор из точек для экранов приложения.
class DottedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.dottedPattern
      ..style = PaintingStyle.fill;

    const dotSize = 1.0;
    const spacing = 20.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
