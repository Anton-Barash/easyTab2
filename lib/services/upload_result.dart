/// Результат загрузки файла.
class UploadResult {
  final bool success;
  final String? error;
  final String? serverFileId;
  final String? webUrl;

  UploadResult({
    required this.success,
    this.error,
    this.serverFileId,
    this.webUrl,
  });
}
