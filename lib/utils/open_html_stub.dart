// ============================================================
// Заглушка для non-web платформ.
// На mobile/desktop HTML открывается через viewHtmlWithChooser().
// ============================================================

/// Открыть HTML в браузере (заглушка для non-web).
/// На web эта функция переопределяется в open_html_web.dart.
void openHtmlInBrowser(String htmlContent) {
  // No-op: на mobile/desktop используется другой механизм
}

/// Открыть URL в новой вкладке браузера (заглушка для non-web).
/// На web эта функция переопределяется в open_html_web.dart.
void openHtmlInBrowserUrl(String url) {
  // No-op: на mobile/desktop не используется
}
