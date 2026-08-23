// ============================================================
// Копирование текста в буфер обмена (кросс-платформенное).
//
// На web (clipboard_utils_web.dart) используется браузерный
// Clipboard API с fallback на execCommand — иначе на http-сайте
// (без secure context) Clipboard.setData молча не срабатывает.
// На нативных платформах (clipboard_utils_stub.dart) — Clipboard.setData.
//
// Возвращает true при успешном копировании.
// ============================================================
export 'clipboard_utils_stub.dart'
    if (dart.library.html) 'clipboard_utils_web.dart';
