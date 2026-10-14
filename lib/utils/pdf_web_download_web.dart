// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// ============================================================
// Web-реализация: скачивание файла в браузере.
//
// Использует Blob URL + AnchorElement.download + click() — это надёжнее
// window.open(), не блокируется popup blocker и сохраняет имя файла.
// ============================================================

import 'dart:html';
import 'dart:typed_data';

/// Скачать байты как файл `fileName` в браузере.
Future<void> downloadBytesInBrowser(Uint8List bytes, String fileName) async {
  final blob = Blob([bytes], 'application/octet-stream');
  final url = Url.createObjectUrlFromBlob(blob);

  final anchor = AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..setAttribute('rel', 'noopener')
    ..style.display = 'none';

  document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Освобождаем URL позже, давая браузеру время начать сохранение.
  Future.delayed(const Duration(seconds: 10), () {
    Url.revokeObjectUrl(url);
  });
}
