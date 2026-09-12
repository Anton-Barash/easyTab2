import 'package:easy_tab/utils/app_colors.dart';

import 'package:easy_tab/utils/open_html_stub.dart'
    if (dart.library.html) 'package:easy_tab/utils/open_html_web.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/utils/cover_image_provider.dart'
    if (dart.library.html) 'package:easy_tab/utils/cover_image_provider_web.dart';
import 'package:easy_tab/widgets/dotted_background.dart';
import 'package:easy_tab/utils/sync_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/report_provider.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

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
    // Чистим «осиротевшие» скрытые копии облачных отчётов (если приложение
    // закрылось прямо в редакторе и копия не была удалена).
    _syncManager.purgeCloudCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadReports() {
    _reportsFuture = _syncManager.loadCombinedList();
  }

  /// Форматирует дату в компактный строковый вид (yyyy-MM-dd HH:mm).
  String _formatDateTime(DateTime dt) =>
      dt.toLocal().toString().substring(0, 16);

  /// Есть ли осмысленная дата изменения (отличается от даты создания более
  /// чем на минуту — чтобы не показывать «Изменён» сразу после создания).
  bool _hasRealModification(ReportSummary report) =>
      !report.createdAt.isAtSameMomentAs(report.modified) &&
      report.modified.difference(report.createdAt).abs().inSeconds >= 60;

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

    var anyDetached = false;
    var anyFailed = false;
    for (var report in reports) {
      // try sync if local exists, otherwise try download
      if (!mounted) return;
      if (report.localExists) {
        final ok = await _syncManager.syncReport(localFolderName: report.id, serverReportId: int.tryParse(report.id), baseVersion: report.serverVersion);
        if (ok) {
          _syncedReports.add(report.id);
        } else if (_syncManager.lastDeniedUnlinkedFolder != null) {
          // Право на редактирование истекло — копия отвязана от сервера.
          anyDetached = true;
        } else {
          anyFailed = true;
        }
      } else if (report.onServer) {
        final folder = await _syncManager.downloadReportFromServer(int.parse(report.id));
        if (folder != null) {
          _syncedReports.add(folder);
        } else {
          anyFailed = true;
        }
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
    // Если хотя бы один отчёт был отвязан из-за истекшего права —
    // показываем отдельное сообщение вместо общего «синхронизировано».
    final detached = anyDetached;
    final message = anyFailed || anyDetached
        ? syncFailureMessage(
            _syncManager.lastSyncError,
            loc,
            detached: anyDetached,
          )
        : loc.syncCompleteMessage;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: detached ? const Duration(seconds: 8) : const Duration(seconds: 4),
      ),
    );
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
    // Если сервер ответил постоянным отказом, локальная копия отвязана —
    // показываем отдельное сообщение вместо общей ошибки синхронизации.
    final detached = !ok && _syncManager.lastDeniedUnlinkedFolder != null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? loc.syncCompleteMessage
              : syncFailureMessage(
                  _syncManager.lastSyncError,
                  loc,
                  detached: detached,
                ),
        ),
        duration: detached ? const Duration(seconds: 8) : const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final bool isMobile = MediaQuery.of(context).size.width <= 800;
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
                    return SelectionArea(
                      child: ListView.builder(
                        // На мобильных добавляем снизу запас, чтобы последний
                        // отчёт можно было проскроллить выше плавающих кнопок.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          isMobile ? 140 : 16,
                        ),
                        itemCount: filteredReports.length,
                        itemBuilder: (ctx, index) {
                          final report = filteredReports[index];
                          return _buildReportCard(context, report);
                        },
                      ),
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

  /// Миниатюра отчёта (обложка из header-фото, «карточка 0»).
  ///
  /// Источники:
  ///   - нативные платформы: локальный файл отчёта (headerImagePath);
  ///   - web: /view/report/:publicId/cover (обложка с сервера, cookie-авторизация).
  /// Для отчётов без обложки — иконка-заглушка. По клику открывается
  /// увеличенное фото (для детального просмотра).
  Widget _buildReportThumbnail(BuildContext context, ReportSummary report) {
    ImageProvider? provider;
    if (report.thumbnailPath != null) {
      provider = localCoverImageProvider(report.thumbnailPath);
    } else if (kIsWeb &&
        report.onServer &&
        (report.publicId?.isNotEmpty ?? false)) {
      provider =
          NetworkImage('${Uri.base.origin}/view/report/${report.publicId}/cover');
    }

    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Icon(
        Icons.description_outlined,
        size: 24,
        color: AppColors.textSecondary,
      ),
    );

    final Widget box;
    if (provider == null) {
      box = fallback;
    } else {
      box = Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    }

    return GestureDetector(
      onTap: provider == null
          ? null
          : () => _showCoverDialog(context, provider!),
      child: box,
    );
  }

  /// Показать обложку отчёта в увеличенном виде.
  void _showCoverDialog(BuildContext context, ImageProvider image) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          maxScale: 5,
          minScale: 0.8,
          child: Image(image: image, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, ReportSummary report) {
    if (!mounted) return const SizedBox.shrink();
    final reportState = Provider.of<ReportState>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loc = AppLocalizations.of(context)!;


    final isSynced = _syncedReports.contains(report.id) || report.status == ReportSyncStatus.synced;
    final isSyncing = _syncingReports.contains(report.id);

    // Просмотр HTML-версии облачного отчёта без скачивания.
    // На web открываем в новой вкладке браузера; на native запрашиваем
    // HTML у сервера и открываем системным просмотрщиком (как в редакторе).
    Future<void> openServerHtmlView() async {
      final messenger = ScaffoldMessenger.of(context);
      if (kIsWeb) {
        // Открываем серверный HTML напрямую (без загрузки Flutter/Dart).
        // GET /view/report/:publicId отдаёт чистый HTML: светлая тема, один
        // вариант с фото, в заголовке — название отчёта (не номер).
        // Авторизация идёт через HttpOnly cookie auth_token (ставится сервером
        // при login), поэтому токен в URL не передаётся и не «светится».
        final publicId = report.publicId;
        if (publicId == null || publicId.isEmpty) {
          messenger.showSnackBar(
            SnackBar(content: Text(loc.openReportFailed)),
          );
          return;
        }
        final origin = Uri.base.origin;
        final viewUrl = '$origin/view/report/$publicId';
        openHtmlInBrowserUrl(viewUrl);
        return;
      }
      // На web/tnative открываем серверный HTML во внешнем браузере через
      // обмен короткого view-токена на HttpOnly cookie (см. /auth/redeem-view).
      final publicId = report.publicId;
      if (publicId == null || publicId.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(loc.openReportFailed)),
        );
        return;
      }
      try {
        final tokenResult = await ApiService.getHtmlViewToken(publicId);
        final token = tokenResult.data?['token'] as String?;
        if (!mounted) return;
        if (!tokenResult.success || token == null) {
          messenger.showSnackBar(
            SnackBar(content: Text(tokenResult.error ?? loc.openReportFailed)),
          );
          return;
        }
        final viewUrl = ApiService.uri(
          '/auth/redeem-view',
          {'token': token, 'target': '/view/report/$publicId'},
        ).toString();
        await openHtmlInBrowserUrl(viewUrl);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(loc.htmlOpenedInNewTab)),
          );
        }
      } catch (e) {
        if (kDebugMode) print('Open server HTML error: $e');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(loc.openReportFailed)),
          );
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      constraints: const BoxConstraints(maxWidth: 900),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () async {
          final nav = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          if (report.localExists) {
            // Открываем именно выбранный локальный отчёт. loadReport() на
            // нативных платформах ждёт абсолютный путь к папке отчёта —
            // берём его из localFolderPath (иначе откроется «последний»).
            setState(() => _syncingReports.add(report.id));
            try {
              final loaded = await reportState.loadReport(
                report.localFolderPath ?? report.id,
              );
              if (!mounted) return;
              if (loaded) {
                final reportId = reportState.serverReportId;
                nav.pushNamed(
                  reportId != null ? '/fill?reportId=$reportId' : '/fill',
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(loc.openReportFailed)),
                );
              }
            } finally {
              if (mounted) {
                setState(() => _syncingReports.remove(report.id));
              }
            }
          } else if (report.onServer) {
            if (kIsWeb) {
              // Auto-open for web version (uses native web support in loadReport)
              setState(() => _syncingReports.add(report.id));
              try {
                // On web, loadReport directly uses server API without local filesystem
                final loaded = await reportState.loadReport(report.id);
                if (loaded) {
                  if (!mounted) return;
                  final reportId = reportState.serverReportId;
                  nav.pushNamed(
                    reportId != null ? '/fill?reportId=$reportId' : '/fill',
                  );
                  // Refresh reports list to mark as synced
                  setState(() => _loadReports());
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text(loc.openReportFailed)),
                  );
                }
              } catch (e) {
                if (kDebugMode) print('Web report open error: $e');
                messenger.showSnackBar(
                  SnackBar(content: Text(loc.openReportFailed)),
                );
              } finally {
                if (mounted) {
                  setState(() => _syncingReports.remove(report.id));
                }
              }
            } else {
              // Mobile/Desktop: открываем облачный отчёт сразу для
              // редактирования. Медиа кладутся в скрытую рабочую копию
              // (кэш приложения, не в «Мои отчёты»), правки автосохраняются
              // на сервер, а при выходе копия удаляется.
              setState(() => _syncingReports.add(report.id));
              String? sessionFolder;
              int? sessionServerId;
              try {
                sessionFolder = await _syncManager
                    .downloadReportToCache(int.parse(report.id));
                if (!mounted) return;
                if (sessionFolder == null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(loc.openReportFailed)),
                  );
                  return;
                }
                final loaded = await reportState.loadReport(sessionFolder);
                if (!mounted) return;
                if (!loaded) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(loc.openReportFailed)),
                  );
                  return;
                }
                final serverId = reportState.serverReportId;
                sessionServerId = serverId;
                await nav.pushNamed(
                  serverId != null ? '/fill?reportId=$serverId' : '/fill',
                );
              } catch (e) {
                if (kDebugMode) print('Cloud report open error: $e');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(loc.openReportFailed)),
                  );
                }
              } finally {
                if (sessionFolder != null && mounted) {
                  // Сначала досинхронизируем изменения с сервером (текст +
                  // новые медиа), иначе при удалении временной копии правки
                  // из «быстрого открытия» будут потеряны.
                  bool synced = true;
                  final sessionId = sessionServerId;
                  if (sessionId != null && authProvider.isLoggedIn) {
                    synced = await _syncManager.syncCloudSession(
                      sessionFolder,
                      sessionId,
                    );
                  }
                  if (synced) {
                    await _syncManager.deleteCloudCacheFolder(sessionFolder);
                  } else if (mounted) {
                    // Сервер мог ответить постоянным отказом — тогда копия
                    // уже перенесена из кэша в «Мои отчёты» как локальный
                    // отчёт (правки не потеряны).
                    final denied =
                        _syncManager.lastDeniedUnlinkedFolder != null;
                    // Папки может не быть и в том случае, когда отвязку
                    // выполнил сам провайдер ещё в редакторе (копия уже в
                    // «Моих отчётах», сообщение было показано там).
                    final folderExists =
                        await Directory(sessionFolder).exists();
                    if (denied) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(loc.reportAccessExpiredDetached),
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    } else if (folderExists) {
                      // Оставляем копию, чтобы не потерять данные; она будет
                      // удалена следующей очисткой кэша.
                      messenger.showSnackBar(
                        SnackBar(content: Text(loc.cloudSessionSyncFailed)),
                      );
                    }
                  }
                }
                if (mounted) {
                  setState(() {
                    _syncingReports.remove(report.id);
                    _loadReports();
                  });
                }
              }
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildReportThumbnail(context, report),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
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
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasRealModification(report))
                          Text(
                            '${loc.modifiedLabel} ${_formatDateTime(report.modified)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        Text(
                          '${loc.createdLabel} ${_formatDateTime(report.createdAt)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (report.onServer)
                          Text(
                            report.authorName == null ||
                                    report.authorName!.isEmpty
                                ? loc.anonymous
                                : report.authorName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (report.onServer) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.open_in_new,
                        color: AppColors.primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: loc.openHtmlTooltip,
                      onPressed: openServerHtmlView,
                    ),
                    const SizedBox(width: 8),
                  ],
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    tooltip: loc.moreMenu,
                    onSelected: (value) {
                      if (value == 'delete_local') {
                        _confirmDeleteLocal(report);
                      } else if (value == 'delete_server') {
                        _confirmDeleteServer(report);
                      } else if (value == 'unlink') {
                        _confirmUnlink(report);
                      }
                    },
                    itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                      if (report.localExists)
                        PopupMenuItem<String>(
                          value: 'delete_local',
                          child: Text(loc.reportMenuDeleteLocal),
                        ),
                      if (report.onServer)
                        PopupMenuItem<String>(
                          value: 'delete_server',
                          child: Text(loc.reportMenuDeleteServer),
                        ),
                      if (report.localExists && report.onServer)
                        PopupMenuItem<String>(
                          value: 'unlink',
                          child: Text(loc.reportMenuUnlink),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Показывает диалог подтверждения и удаляет локальную копию отчёта с устройства.
  Future<void> _confirmDeleteLocal(ReportSummary report) async {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final reportState = Provider.of<ReportState>(context, listen: false);

    if (report.localFolderPath == null) {
      _showSnack(loc.reportDeleteError);
      return;
    }
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
        contentPadding: isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24),
        shape: isMobile
            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
            : null,
        title: isMobile ? null : Text(loc.reportMenuDeleteLocal),
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
    if (confirm != true || !mounted) return;

    final deleted =
        await reportState.deleteReportLocal(report.localFolderPath!);
    if (!mounted) return;
    setState(() => _loadReports());
    _showSnack(deleted
        ? loc.reportDeleted
        : loc.reportDeleteError
    );
  }

  /// Удаляет отчёт на сервере, оставляя локальную копию без изменений.
  Future<void> _confirmDeleteServer(ReportSummary report) async {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final reportState = Provider.of<ReportState>(context, listen: false);

    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
        contentPadding: isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24),
        shape: isMobile
            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
            : null,
        title: isMobile ? null : Text(loc.reportMenuDeleteServer),
        content: Text(loc.cannotUndo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final result = await reportState.deleteReportOnServer(report.id);
    if (!mounted) return;
    // 403 означает, что отчёт принадлежит другому автору — даём понятное
    // предупреждение вместо общего «ошибка удаления».
    if (result == 403) {
      _showSnack(loc.reportDeleteServerDenied);
      return;
    }
    // После удаления на сервере локальная копия (если была) остаётся
    // обычным локальным отчётом — перечитываем список.
    setState(() => _loadReports());
    _showSnack(result == 0
        ? loc.reportDeleted
        : loc.reportDeleteError);
  }

  /// Разрывает связь локальной копии с сервером (отменяет синхронизацию),
  /// не удаляя ни локальную, ни облачную копии. Отчёт становится локальным,
  /// повторная заливка создаст новый отчёт на сервере.
  Future<void> _confirmUnlink(ReportSummary report) async {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    if (report.localFolderPath == null) {
      _showSnack(loc.reportDeleteError);
      return;
    }
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
        contentPadding: isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24),
        shape: isMobile
            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
            : null,
        title: isMobile ? null : Text(loc.reportMenuUnlink),
        content: Text(loc.reportMenuUnlinkHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.reportMenuUnlink),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok =
        await _syncManager.detachReportFromServer(report.localFolderPath!);
    if (!mounted) return;
    setState(() => _loadReports());
    _showSnack(ok ? loc.reportDeleted : loc.reportDeleteError);
  }

  /// Показывает SnackBar, если виджет ещё смонтирован.
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}