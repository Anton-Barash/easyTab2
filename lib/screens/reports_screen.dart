import 'package:easy_tab/utils/app_colors.dart';

import 'package:easy_tab/utils/open_html_stub.dart'
    if (dart.library.html) 'package:easy_tab/utils/open_html_web.dart';
import 'package:easy_tab/widgets/dotted_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/report_provider.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';

import '../models/report_summary.dart';
import '../providers/report_sync_manager.dart';
import '../widgets/sync_buttons.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<List<ReportSummary>>? _reportsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSyncingAll = false;
  final Set<String> _syncedReports = {};
  final Set<String> _syncingReports = {};

  final ReportSyncManager _syncManager = ReportSyncManager();

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadReports() {
    _reportsFuture = _syncManager.loadCombinedList();
  }

  Future<void> _syncAllReports() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.loginRequired)));
      return;
    }

    final reports = await _reportsFuture;
    if (reports == null || reports.isEmpty) return;

    setState(() {
      _isSyncingAll = true;
      for (var report in reports) {
        _syncingReports.add(report.id);
      }
    });

    for (var report in reports) {
      // try sync if local exists, otherwise try download
      if (!mounted) return;
      if (report.localExists) {
        final ok = await _syncManager.syncReport(localFolderName: report.id, serverReportId: int.tryParse(report.id), baseVersion: report.serverVersion);
        if (ok) _syncedReports.add(report.id);
      } else if (report.onServer) {
        final folder = await _syncManager.downloadReportFromServer(int.parse(report.id));
        if (folder != null) _syncedReports.add(folder);
      }
      if (!mounted) return;
      setState(() {
        _syncingReports.remove(report.id);
      });
    }

    setState(() {
      _isSyncingAll = false;
    });

    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.syncCompleteMessage)));
  }

  Future<void> _syncReport(ReportSummary report) async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.loginRequired)));
      return;
    }

    setState(() {
      _syncingReports.add(report.id);
    });

    bool ok = false;
    if (report.localExists) {
      ok = await _syncManager.syncReport(localFolderName: report.id, serverReportId: int.tryParse(report.id), baseVersion: report.serverVersion);
    } else if (report.onServer) {
      final folder = await _syncManager.downloadReportFromServer(int.parse(report.id));
      ok = folder != null;
    }

    if (!mounted) return;
    setState(() {
      _syncingReports.remove(report.id);
      if (ok) _syncedReports.add(report.id);
      _loadReports();
    });

    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? loc.syncCompleteMessage : loc.syncErrorMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.myReports),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const DottedBackground(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: loc.searchReports,
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.border,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<ReportSummary>>(
                  future: _reportsFuture,
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(loc.loadError(snapshot.error.toString())),
                      );
                    }
                    final reports = snapshot.data ?? [];
                    final filteredReports = reports.where((report) {
                      if (_searchQuery.isEmpty) return true;
                      return report.title.toLowerCase().contains(_searchQuery);
                    }).toList();
                    if (filteredReports.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? loc.noReportsYet
                              : loc.reportsNotFound,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredReports.length,
                      itemBuilder: (ctx, index) {
                        final report = filteredReports[index];
                        return _buildReportCard(context, report);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _buildActionButtons(),
    );
  }

  Widget _buildActionButtons() {
    final loc = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (authProvider.isLoggedIn)
          FloatingActionButton(
            heroTag: 'sync_all_btn',
            onPressed: _isSyncingAll ? null : _syncAllReports,
            tooltip: loc.syncToCloud,
            backgroundColor: _isSyncingAll
                ? AppColors.grey300
                : AppColors.primary,
            child: _isSyncingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload),
          ),
        if (authProvider.isLoggedIn) const SizedBox(width: 10),
        FloatingActionButton(
          heroTag: 'import_btn',
          onPressed: _importProject,
          tooltip: loc.importProject,
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(width: 10),
        FloatingActionButton(
          heroTag: 'new_report_btn',
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed('/template'),
          tooltip: loc.newReportTooltip,
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  Future<void> _importProject() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.isNotEmpty) {
        final zipPath = result.files.single.path;
        if (zipPath != null) {
          if (!mounted) return;
          final reportState = Provider.of<ReportState>(context, listen: false);

          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(loc.importingProject),
                ],
              ),
            ),
          );

          final importedPath = await reportState.importProjectFromZip(zipPath);

          if (!mounted) return;
          Navigator.pop(context);

          if (importedPath != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.projectImported)));
            setState(() {
              _loadReports();
            });
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.importError)));
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.importError)));
    }
  }

  Widget _buildReportCard(BuildContext context, ReportSummary report) {
    if (!mounted) return const SizedBox.shrink();
    final reportState = Provider.of<ReportState>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loc = AppLocalizations.of(context)!;


    final isSynced = _syncedReports.contains(report.id) || report.status == ReportSyncStatus.synced;
    final isSyncing = _syncingReports.contains(report.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(maxWidth: 500),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: AppColors.border),
      ),
      child: InkWell(
        onTap: () async {
          final nav = Navigator.of(context);
          if (report.localExists) {
            await reportState.loadReport(report.id);
            if (!mounted) return;
            final reportId = reportState.serverReportId;
            nav.pushNamed(
              reportId != null ? '/fill?reportId=$reportId' : '/fill',
            );
          } else if (report.onServer) {
            // Offer to download
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.downloadReport),
                content: Text(loc.downloadReportPrompt),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.downloadButton)),
                ],
              ),
            );
            if (confirmed == true) {
              setState(() => _syncingReports.add(report.id));
              final folder = await _syncManager.downloadReportFromServer(int.parse(report.id));
              setState(() {
                _syncingReports.remove(report.id);
                if (folder != null) _syncedReports.add(folder);
                _loadReports();
              });
            }
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(width: 2, color: AppColors.border),
                    ),
                    child: const Icon(
                        Icons.description_outlined,
                        size: 32,
                        color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (authProvider.isLoggedIn) ...[
                          const SizedBox(width: 8),
                          if (isSyncing)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else ...[
                            Icon(
                              isSynced ? Icons.cloud_done : Icons.cloud_upload,
                              color: isSynced ? AppColors.primary : AppColors.greyMuted,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            SyncButtons(
                              showDownload: report.onServer && !report.localExists,
                              showSync: report.localExists && report.onServer,
                              inProgress: isSyncing,
                              onDownload: report.onServer && !report.localExists
                                  ? () async {
                                      setState(() => _syncingReports.add(report.id));
                                      final folder = await _syncManager.downloadReportFromServer(int.parse(report.id));
                                      setState(() {
                                        _syncingReports.remove(report.id);
                                        if (folder != null) _syncedReports.add(folder);
                                        _loadReports();
                                      });
                                    }
                                  : null,
                              onSync: report.localExists && report.onServer
                                  ? () => _syncReport(report)
                                  : null,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    report.modified.toLocal().toString().substring(0, 16),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (kIsWeb && report.onServer) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.open_in_new,
                        color: AppColors.primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Открыть HTML',
                      onPressed: () {
                        final origin = Uri.base.origin;
                        final viewUrl = '$origin/#/view-report?pid=${report.id}';
                        openHtmlInBrowserUrl(viewUrl);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppColors.errorLight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final loc = AppLocalizations.of(context)!;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final isMobile = MediaQuery.of(context).size.width <= 800;
                      final confirm = await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          insetPadding: isMobile
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(40),
                          contentPadding: isMobile
                              ? const EdgeInsets.all(16)
                              : const EdgeInsets.all(24),
                          shape: isMobile
                              ? const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                )
                              : null,
                          title: isMobile ? null : Text(loc.deleteReport),
                          content: isMobile
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(loc.cannotUndo),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text(loc.cancel),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: Text(loc.delete),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(loc.cannotUndo),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: Text(loc.cancel),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text(loc.delete),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      );
                      if (confirm == true) {
                        final deleted = await reportState.deleteReport(
                          report.id,
                        );
                        setState(() {
                          _loadReports();
                        });
                        if (!mounted) return;
                        scaffoldMessenger.showSnackBar(
                          deleted
                              ? SnackBar(content: Text(loc.reportDeleted))
                              : SnackBar(
                                  content: Text(loc.reportDeleteError),
                                  backgroundColor: AppColors.error,
                                ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
