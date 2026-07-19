// ============================================================
// Cookie utilities stub для non-web платформ (mobile, desktop).
// На этих платформах cookies не используются (iframe не нужен).
// ============================================================

/// Установить cookie auth_token (no-op для non-web).
void setAuthTokenCookie(String token) {
  // No-op: cookies не используются на non-web платформах
}

/// Удалить cookie auth_token (no-op для non-web).
void clearAuthTokenCookie() {
  // No-op: cookies не используются на non-web платформах
}

/// Получить значение cookie auth_token (always null для non-web).
String? getAuthTokenCookie() {
  return null;
}
