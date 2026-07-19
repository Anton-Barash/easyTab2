// ============================================================
// Cookie utilities для web-платформы.
// Используется для установки auth_token cookie при логине,
// чтобы iframe мог загружать фото с авторизацией.
// ============================================================

import 'dart:html' as html;

/// Установить cookie auth_token.
/// Cookie доступен для всех портов localhost (для iframe с сервером на другом порту).
/// SameSite=None требуется для кросс-порт запросов из iframe.
void setAuthTokenCookie(String token) {
  // Cookie действует 7 дней (как и JWT)
  // SameSite=None нужен для кросс-порт запросов (iframe localhost:4000 -> сервер localhost:8000)
  // Для localhost Secure не требуется (исключение для localhost)
  html.document.cookie = 'auth_token=$token; path=/; max-age=${7 * 24 * 60 * 60}; SameSite=None';
}

/// Удалить cookie auth_token (при logout).
void clearAuthTokenCookie() {
  html.document.cookie = 'auth_token=; path=/; max-age=0';
}

/// Получить значение cookie auth_token.
String? getAuthTokenCookie() {
  final cookies = html.document.cookie?.split(';') ?? [];
  for (final cookie in cookies) {
    final trimmed = cookie.trim();
    if (trimmed.startsWith('auth_token=')) {
      return trimmed.substring('auth_token='.length);
    }
  }
  return null;
}
