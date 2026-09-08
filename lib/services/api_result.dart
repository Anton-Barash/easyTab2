/// Результат вызова API.
class ApiResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  /// HTTP-статус ответа. null при сетевой ошибке (нет ответа от сервера).
  /// Позволяет отличить 404/410 (ресурс удалён) от временного сбоя сети.
  final int? statusCode;

  const ApiResult({
    required this.success,
    this.data,
    this.token,
    this.user,
    this.error,
    this.statusCode,
  });

  /// True если сервер ответил постоянным отказом доступа / истечением права
  /// (403 — запрещено, 404 — отчёт удалён/недоступен, 410 — просроченная
  /// ссылка), либо текст/код ошибки говорит о denied/forbidden/expired.
  ///
  /// 401 (не залогинен) сюда НЕ входит: это временное состояние — после
  /// входа синхронизация снова должна работать.
  bool get isPermanentAccessDenied {
    if (success) return false;
    if (statusCode == 403 || statusCode == 404 || statusCode == 410) return true;
    final text =
        '${data?.toString() ?? ''} ${error ?? ''}'.toLowerCase();
    const markers = <String>[
      'denied',
      'forbidden',
      'expired',
      'permission',
      'access_denied',
      'no_access',
      'gone',
      'report_not_found',
    ];
    return markers.any(text.contains);
  }
}
