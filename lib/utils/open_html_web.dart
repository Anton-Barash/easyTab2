// ============================================================
// Web-реализация: открытие HTML в новой вкладке браузера.
//
// Два метода:
//   1. openHtmlInBrowser(htmlContent) — для незалогиненных:
//      использует Blob URL + AnchorElement.click() — надёжнее window.open().
//
//   2. openHtmlInBrowserUrl(url) — для залогиненных:
//      открывает реальный URL (подписанная ссылка KS3).
//      URL можно скопировать и поделиться.
// ============================================================

// TODO P3-50: dart:html устарел — перейти на package:web для поддержки Wasm-компиляции.
// Требуется: добавить web: ^1.0.0 в pubspec.yaml и переписать на web.Blob/web.URL/web.document.
import 'dart:html';

/// Открыть HTML-контент в новой вкладке (без сервера).
///
/// Использует Blob URL + AnchorElement.click() — этот метод
/// надёжнее window.open(), т.к. не блокируется popup blocker.
void openHtmlInBrowser(String htmlContent) {
  // Создаём Blob с MIME-типом text/html
  final blob = Blob([htmlContent], 'text/html');
  final url = Url.createObjectUrlFromBlob(blob);

  // Создаём скрытый anchor и кликаем по нему
  // Это надёжнее window.open() для blob: URLs
  final anchor = AnchorElement(href: url)
    ..setAttribute('target', '_blank')
    ..setAttribute('rel', 'noopener');

  document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Освобождаем URL через 10 секунд (даём вкладке время загрузиться)
  Future.delayed(const Duration(seconds: 10), () {
    Url.revokeObjectUrl(url);
  });
}

/// Открыть URL в новой вкладке браузера.
///
/// Используется, когда есть реальная ссылка на сервер (KS3).
/// URL открывается как обычная страница — рендерится HTML
/// (т.к. файл загружен с MIME text/html и is_inline=true).
void openHtmlInBrowserUrl(String url) {
  final anchor = AnchorElement(href: url)
    ..setAttribute('target', '_blank')
    ..setAttribute('rel', 'noopener');

  document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}