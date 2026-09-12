// ============================================================
// Реализация для non-web платформ (mobile/desktop).
// Открывает URL серверного HTML-отчёта в системном браузере.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открыть HTML-контент в браузере (заглушка для non-web).
/// На mobile/desktop HTML открывается через серверный URL, поэтому
/// передача raw-контента сюда не используется — оставляем no-op.
void openHtmlInBrowser(String htmlContent) {
  // No-op: на mobile/desktop используется openHtmlInBrowserUrl(url).
}

/// Открыть URL в системном браузере (mobile/desktop).
///
/// Используется для просмотра серверного HTML-отчёта
/// (/view/report/:publicId?token=...) во внешнем браузере на телефоне,
/// где данные и медиа грузятся с сервера, а не из локальной копии.
Future<void> openHtmlInBrowserUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (kDebugMode) debugPrint('openHtmlInBrowserUrl error: $e');
  }
}