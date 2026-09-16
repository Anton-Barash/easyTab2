/// Разбор share-токена из введённой пользователем строки.
///
/// Принимает либо полную share-ссылку
/// `scheme://host/#/welcome?token=XXX` (или `/?token=XXX`),
/// либо «голый» токен (например, UUID из QR-сканера).
List<String> _splitParams(String q) => q.split('&').toList();

String? _paramValue(List<String> params, String name) {
  for (final pair in params) {
    final eq = pair.indexOf('=');
    if (eq < 0) continue;
    if (pair.substring(0, eq) != name) continue;
    final v = pair.substring(eq + 1);
    if (v.isNotEmpty) return Uri.decodeComponent(v);
  }
  return null;
}

/// Извлекает share-токен из произвольной строки (ссылка или голый токен).
/// Возвращает null, если токен определить нельзя.
String? extractShareToken(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final uri = Uri.tryParse(input);
  if (uri != null && uri.scheme.isNotEmpty) {
    // Похоже на URL (https://..., easytab://...). Ищем ?token= в fragment:
    // `#/welcome?token=XXX`, затем в query самой ссылки `/?token=XXX`.
    String? token;
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final fragQuery = fragment.indexOf('?');
      final query = fragQuery >= 0 ? fragment.substring(fragQuery + 1) : fragment;
      token = _paramValue(_splitParams(query), 'token');
    }
    if (token == null || token.isEmpty) {
      if (uri.query.isNotEmpty) {
        token = _paramValue(_splitParams(uri.query), 'token');
      }
    }
    return (token != null && token.isNotEmpty) ? token.trim() : null;
  }

  // Нет схемы — считаем весь ввод токеном (например, голый UUID).
  return input;
}