import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// P2-28: Единая кнопка в стиле easyTab.
///
/// Заменяет дублированные `_buildButton` в main.dart,
/// template_select_screen.dart, login_screen.dart.
///
/// Параметры:
/// - [label] — текст кнопки
/// - [onTap] — обработчик (null = disabled)
/// - [isOutline] — Outline-вариант (без заливки, без теней)
/// - [fontSize] — размер шрифта (18 для главного экрана, 16 для остальных)
/// - [verticalPadding] — вертикальный padding (18/14)
/// - [horizontalPadding] — горизонтальный padding (20/16)
class EasyTabButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isOutline;
  final double fontSize;
  final double verticalPadding;
  final double horizontalPadding;
  final Widget? child;

  const EasyTabButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isOutline = false,
    this.fontSize = 16,
    this.verticalPadding = 14,
    this.horizontalPadding = 20,
    this.child,
  });

  static const _borderRadius = BorderRadius.only(
    topLeft: Radius.circular(8),
    topRight: Radius.circular(10),
    bottomLeft: Radius.circular(9),
    bottomRight: Radius.circular(11),
  );

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isOutline
            ? Colors.white
            : (disabled ? AppColors.grey300 : AppColors.surface),
        borderRadius: _borderRadius,
        border: Border.all(width: 2.5, color: AppColors.border),
        boxShadow: isOutline
            ? null
            : [
                const BoxShadow(
                  color: AppColors.border,
                  blurRadius: 0,
                  spreadRadius: 1.5,
                ),
                const BoxShadow(
                  color: AppColors.shadowOverlay,
                  offset: Offset(2, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: _borderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: _borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: horizontalPadding,
            ),
            child: child ??
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    color: disabled
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    shadows: isOutline
                        ? null
                        : const [
                            Shadow(
                              color: AppColors.textShadowDark,
                              blurRadius: 1.2,
                            ),
                            Shadow(
                              color: AppColors.textShadowLight,
                              blurRadius: 0.8,
                            ),
                          ],
                  ),
                  textAlign: TextAlign.center,
                ),
          ),
        ),
      ),
    );
  }
}
