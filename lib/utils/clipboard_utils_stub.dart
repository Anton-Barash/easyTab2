// ============================================================
// Копирование в буфер обмена на нативных платформах (не web).
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Копирует [text] в буфер обмена. Возвращает true при успехе.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (e) {
    debugPrint('copyToClipboard failed: $e');
    return false;
  }
}
