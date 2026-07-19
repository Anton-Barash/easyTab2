// ============================================================
// Stub для non-web платформ (mobile/desktop).
// На web функция переопределяется в report_html_iframe_web.dart.
// ============================================================

/// Заглушка: на non-web возвращает пустую строку (iframe не используется).
/// Реальная логика только на web.
String createIframeView(String htmlContent) {
  // No-op: на mobile/desktop нужен другой подход (webview_flutter)
  return '';
}
