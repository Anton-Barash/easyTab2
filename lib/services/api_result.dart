/// Результат вызова API.
class ApiResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  const ApiResult({
    required this.success,
    this.data,
    this.token,
    this.user,
    this.error,
  });
}
