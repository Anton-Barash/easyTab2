// ============================================================
// Копирование в буфер обмена на web.
//
// Сначала пробуем async Clipboard API (navigator.clipboard) —
// он работает только в secure context (https или localhost).
// Если недоступен (обычный http-сайт), используется fallback:
// скрытый textarea + document.execCommand('copy').
// ============================================================
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Копирует [text] в буфер обмена. Возвращает true при успехе.
Future<bool> copyToClipboard(String text) async {
  // 1) Нативный async Clipboard API (secure context).
  try {
    await web.window.navigator.clipboard.writeText(text).toDart;
    return true;
  } catch (_) {
    // clipboard недоступен или запись запрещена — переходим к fallback.
  }

  // 2) Fallback через скрытый textarea + execCommand.
  try {
    final textarea = web.HTMLTextAreaElement()
      ..value = text
      ..style.position = 'fixed'
      ..style.left = '-9999px'
      ..style.top = '0'
      ..style.opacity = '0';
    web.document.body!.append(textarea);
    textarea.focus();
    textarea.select();
    final ok = web.document.execCommand('copy');
    textarea.remove();
    return ok;
  } catch (_) {
    return false;
  }
}
