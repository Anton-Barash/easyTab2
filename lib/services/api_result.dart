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
}
