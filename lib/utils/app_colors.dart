import 'package:flutter/material.dart';

/// Цветовая палитра приложения EasyTab
class AppColors {
  AppColors._();

  // Основные цвета
  static const Color primary = Color(0xFF2563eb);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color background = Color(0xFFf8f7f2);
  static const Color surface = Color(0xFFe0e0e0);
  static const Color border = Color(0xFF333333);
  
  // Текстовые цвета
  static const Color textPrimary = Color(0xFF424242);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textTertiary = Color(0xFF999999);
  static const Color textLight = Color(0xFF64748b);
  static const Color textDark = Color(0xFF111827);
  
  // Статусные цвета
  static const Color success = Color(0xFF2e7d32);
  static const Color successLight = Color(0xFFd1fae5);
  static const Color error = Color(0xFFc62828);
  static const Color errorLight = Color(0xFFdc2626);
  static const Color warning = Color(0xFFf59e0b);
  static const Color warningLight = Color(0xFFfff3cd);
  static const Color warningDark = Color(0xFF856404);
  static const Color warningAccent = Color(0xFFd97706);
  
  // Серые оттенки
  static const Color grey100 = Color(0xFFf3f4f6);
  static const Color grey200 = Color(0xFFe5e7eb);
  static const Color grey300 = Color(0xFFcccccc);
  static const Color grey400 = Color(0xFF999999);
  static const Color grey500 = Color(0xFF666666);
  static const Color grey600 = Color(0xFF424242);
  static const Color grey700 = Color(0xFF333333);
  static const Color grey800 = Color(0xFF374151);
  static const Color grey900 = Color(0xFF1f2937);
  static const Color greyDisabled = Color(0xFF9CA3AF);
  static const Color greyBorder = Color(0xFFd1d5db);
  static const Color greyBackground = Color(0xFFf9fafb);
  static const Color greyLight = Color(0xFFf5f5f5);
  static const Color greyMuted = Color(0xFF9e9e9e);
  static const Color attentionBackground = Color(0xFFfff7ed);
  static const Color attentionBorder = Color(0xFFfed7aa);
  
  // Специальные цвета
  static const Color shadow = Color(0x21000000);
  static const Color dottedPattern = Color(0xFFcbc7bc);
  
  // Прозрачные цвета для эффектов
  static const Color textShadowDark = Color(0x73424242); // 46,66,66,0.45
  static const Color textShadowLight = Color(0xE6FFFFFF); // 255,255,255,0.9
  static const Color shadowOverlay = Color(0x21000000); // black 13% opacity
}
