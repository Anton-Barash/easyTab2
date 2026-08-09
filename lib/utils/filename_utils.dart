// Утилиты для безопасных имён файлов.

/// Очищает строку, оставляя буквы, цифры, дефисы, подчёркивания и пробелы,
/// после чего заменяет пробелы на подчёркивания.
String sanitizeFileName(String name) {
  return name
      .replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ\-_ ]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

/// Формирует имя ZIP-архива по названию отчёта и share-токену.
String buildShareZipName(String reportName, String shareToken) {
  final safeName = sanitizeFileName(reportName);
  final suffix = shareToken.length >= 8
      ? shareToken.substring(0, 8)
      : shareToken;
  return safeName.isNotEmpty
      ? '${safeName}_$suffix.zip'
      : 'report_$suffix.zip';
}
