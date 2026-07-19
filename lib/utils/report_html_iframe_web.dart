// ============================================================
// Web-реализация: встраивает HTML в iframe (srcdoc) внутри Flutter.
//
// Используется для отображения серверного HTML-отчёта внутри Flutter web,
// чтобы пользователь оставался на localhost:4000 (а не уходил на сервер 8000).
// ============================================================

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

int _viewCounter = 0;

/// Создаёт уникальный viewType и регистрирует IFrameElement с заданным HTML.
///
/// Возвращает viewType — передаётся в HtmlElementView для отображения.
String createIframeView(String htmlContent) {
  final viewType = 'report-html-iframe-${_viewCounter++}';

  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..srcdoc = htmlContent
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.display = 'block';
      // Не используем sandbox - доверяем содержимому (генерируется нашим сервером)
      // Sandbox блокирует загрузку ресурсов из других origins (localhost:8000)
      return iframe;
    },
  );

  return viewType;
}
