// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Открыть share-ссылку в новой вкладке (web).
void openShareLink(String url) {
  html.window.open(url, '_blank');
}

/// Скачать ZIP по share-ссылке (web).
void downloadShareZip(String url, String fileName) {
  final anchor = html.AnchorElement(href: url)
    ..target = '_blank'
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
