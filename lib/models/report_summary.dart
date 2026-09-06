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

  /// Абсолютный путь к локальной папке отчёта (на нативных платформах).
  /// Заполнен, только если [localExists] == true. Нужен для открытия
  /// отчёта через ReportState.loadReport(), который ждёт абсолютный путь.
  final String? localFolderPath;

  ReportSummary({
    required this.id,
    required this.title,
    DateTime? createdAt,
    required this.modified,
    required this.localExists,
    required this.onServer,
    this.serverVersion,
    required this.status,
    this.localFolderPath,
  }) : createdAt = createdAt ?? modified;
}
