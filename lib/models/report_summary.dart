enum ReportSyncStatus { localOnly, cloudOnly, synced, dirtyLocal, dirtyRemote, conflict }

class ReportSummary {
  final String id; // local folder name or server id
  final String title;
  final DateTime createdAt;
  final DateTime modified;
  final bool localExists;
  final bool onServer;
  final int? serverVersion;
  final ReportSyncStatus status;

  /// Публичный идентификатор отчёта с сервера (public_id).
  /// Используется для открытия HTML-версии напрямую: /view/report/:publicId.
  /// Может быть null для локальных отчётов без серверной копии.
  final String? publicId;

  /// Имя автора отчёта с сервера (JOIN users.username). null/пустой — «Аноним».
  final String? authorName;

  /// Абсолютный путь к локальной папке отчёта (на нативных платформах).
  /// Заполнен, только если [localExists] == true. Нужен для открытия
  /// отчёта через ReportState.loadReport(), который ждёт абсолютный путь.
  final String? localFolderPath;

  /// Абсолютный путь к header-изображению (обложка) локального отчёта.
  /// На нативных платформах используется как миниатюра в списке.
  /// Для облачных/web-отчётов вместо этого берётся /view/report/:publicId/cover.
  final String? thumbnailPath;

  ReportSummary({
    required this.id,
    required this.title,
    DateTime? createdAt,
    required this.modified,
    required this.localExists,
    required this.onServer,
    this.serverVersion,
    required this.status,
    this.publicId,
    this.authorName,
    this.localFolderPath,
    this.thumbnailPath,
  }) : createdAt = createdAt ?? modified;
}
