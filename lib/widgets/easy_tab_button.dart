import 'package:flutter/material.dart';

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

  const EasyTabButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isOutline = false,
    this.fontSize = 16,
    this.verticalPadding = 14,
    this.horizontalPadding = 20,
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
            : (disabled ? const Color(0xFFcccccc) : const Color(0xFFe0e0e0)),
        borderRadius: _borderRadius,
        border: Border.all(width: 2.5, color: const Color(0xFF333333)),
        boxShadow: isOutline
            ? null
            : [
                const BoxShadow(
                  color: Color(0xFF333333),
                  blurRadius: 0,
                  spreadRadius: 1.5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.13),
                  offset: const Offset(2, 2),
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: disabled
                    ? const Color(0xFF999999)
                    : const Color(0xFF424242),
                shadows: isOutline
                    ? null
                    : const [
                        Shadow(
                          color: Color.fromRGBO(66, 66, 66, 0.45),
                          blurRadius: 1.2,
                        ),
                        Shadow(
                          color: Color.fromRGBO(255, 255, 255, 0.9),
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
