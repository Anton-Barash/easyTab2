enum ReportSyncStatus { localOnly, cloudOnly, synced, dirtyLocal, dirtyRemote, conflict }

class ReportSummary {
  final String id; // local folder name or server id
  final String title;
  final DateTime modified;
  final bool localExists;
  final bool onServer;
  final int? serverVersion;
  final ReportSyncStatus status;

  ReportSummary({
    required this.id,
    required this.title,
    required this.modified,
    required this.localExists,
    required this.onServer,
    this.serverVersion,
    required this.status,
  });
}
