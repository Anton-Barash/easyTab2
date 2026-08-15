import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/services/mime_utils.dart';
import 'package:easy_tab/widgets/dotted_background.dart';
import 'package:easy_tab/widgets/easy_tab_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import '../providers/report_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';
import '../models/report_models.dart';
import '../utils/open_html.dart';
import '../utils/filename_utils.dart';
import '../services/anonymous_id_service.dart';
import '../utils/share_link_opener_stub.dart'
    if (dart.library.html) '../utils/share_link_opener_web.dart';
import '../widgets/form_fill/header_card.dart';
import '../widgets/form_fill/header_field.dart';
import '../widgets/form_fill/header_list_tile.dart';
import '../widgets/form_fill/header_photo_picker.dart';
import '../widgets/form_fill/header_side_panel_tile.dart';
import '../widgets/form_fill/permission_option.dart';
import '../widgets/form_fill/picker_item.dart';
import '../widgets/form_fill/question_card.dart';
import '../widgets/form_fill/section_title.dart';
import '../widgets/sync/sync_dialog.dart';
import '../widgets/sync/sync_menu_dialog.dart';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:async';

enum ViewMode { list, card }

class FormFillScreen extends StatefulWidget {
  /// Если задан, отчёт открывается по share-ссылке, без авторизации.
  final String? shareToken;

  const FormFillScreen({super.key, this.shareToken});

  @override
  State<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  final Map<String, Map<int, TextEditingController>> _answerControllers = {};
  final Map<String, Map<int, Timer?>> _debounceTimers = {};
  ViewMode _viewMode = ViewMode.list;
  bool _isLoadingSharedReport = false;

  TextEditingController? _getSafeController(String qid, int j) {
    return _answerControllers[qid]?[j];
  }

  bool _isSidePanelCollapsed = false;
  bool _hideAnsweredQuestions = false;
  final PageController _pageController = PageController(initialPage: 0);
  final ItemScrollController _listItemScrollController = ItemScrollController();
  final ItemScrollController _sidePanelItemScrollController =
      ItemScrollController();
  int _currentPage = -1;
  final Map<int, bool> _needsWorkMap = {};
  Set<int> _blockedQuestionIndices = {};
  bool _isUpdatingControllers = false;
  final Map<String, Map<int, bool>> _enabledAnswers = {};
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  String _processingMessage = '';

  bool _checkedSyncAfterLoad = false;

  // Ссылка на провайдер сохраняется в initState: в dispose() нельзя
  // вызывать context.read() — виджет уже деактивирован.
  late final ReportState _reportState;

  void _resetControllers() {
    _answerControllers.values
        .expand((map) => map.values)
        .forEach((c) => c.dispose());
    _answerControllers.clear();
    _debounceTimers.values
        .expand((map) => map.values)
        .forEach((timer) => timer?.cancel());
    _debounceTimers.clear();
    _enabledAnswers.clear();
  }

  @override
  void initState() {
    super.initState();
    // Подписка на изменения отчёта: синхронизация контроллеров происходит
    // в listener (синхронно при notifyListeners, до пересборки виджета),
    // а не в build() — это устраняет побочные эффекты из метода сборки.
    final reportState = context.read<ReportState>();
    _reportState = reportState;
    reportState.addListener(_onReportStateChanged);
    final report = reportState.currentReport;
    if (report != null) {
      _syncControllers(reportState);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedReportIfNeeded();
      _checkSyncAfterLoad();
    });
  }

  void _onReportStateChanged() {
    if (!mounted) return;
    if (_reportState.currentReport != null) {
      _syncControllers(_reportState);
    }
  }

  /// Загрузить отчёт по share-ссылке, если экран открыт с token.
  Future<void> _loadSharedReportIfNeeded() async {
    if (widget.shareToken == null || widget.shareToken!.isEmpty) return;

    final reportState = context.read<ReportState>();
    if (reportState.currentReport != null) return;

    setState(() => _isLoadingSharedReport = true);
    final ok = await reportState.loadSharedReport(widget.shareToken!);
    if (!mounted) return;
    setState(() => _isLoadingSharedReport = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить отчёт по ссылке')),
      );
    }
  }

  void _checkSyncAfterLoad() {
    if (_checkedSyncAfterLoad) return;

    final reportState = context.read<ReportState>();
    if (reportState.needsSyncAfterLoad()) {
      _showSyncMenuDialog();
    }
    _checkedSyncAfterLoad = true;
  }

  @override
  void dispose() {
    _reportState.removeListener(_onReportStateChanged);
    _answerControllers.values
        .expand((map) => map.values)
        .forEach((c) => c.dispose());
    _debounceTimers.values
        .expand((map) => map.values)
        .forEach((timer) => timer?.cancel());
    _pageController.dispose();
    super.dispose();
  }

  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  Future<void> _doSave() async {
    if (!_hasUnsavedChanges) return;

    setState(() => _isSaving = true);
    try {
      final reportState = context.read<ReportState>();
      await reportState.saveReport();
      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Обработчик создания share-ссылки из меню отчёта.
  /// Если отчёт ещё не сохранён на сервере — сначала сохраняет.
  Future<void> _handleCreateShareLink() async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();

    if (reportState.serverReportId == null) {
      if (_hasUnsavedChanges) {
        await _doSave();
      }
      if (!mounted) return;
      if (reportState.serverReportId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.shareLinkSaveFirst)));
        return;
      }
    }

    await _showCreateShareLinkDialog();
  }

  /// Показывает диалог создания share-ссылки в стиле easyTab.
  Future<void> _showCreateShareLinkDialog() async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();

    int selectedDays = 7;
    String selectedPermission = 'edit';
    bool isCreating = false;
    String? createdLink;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> doCreate() async {
            setDialogState(() => isCreating = true);
            final expiresAt = DateTime.now().add(Duration(days: selectedDays));
            final result = await reportState.createShareLink(
              expiresAt: expiresAt,
              permissions: selectedPermission,
            );
            if (!ctx.mounted) return;
            setDialogState(() => isCreating = false);
            if (result.success && result.data?['share']?['url'] is String) {
              setDialogState(() => createdLink = result.data!['share']['url']);
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(result.error ?? loc.shareLinkError)),
              );
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 420,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(width: 2, color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: createdLink != null
                      ? [
                          // Ссылка создана
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.grey700,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  loc.shareLinkCreated,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: SelectableText(
                              createdLink!,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: EasyTabButton(
                                  label: loc.shareLinkClose,
                                  onTap: () => Navigator.of(ctx).pop(),
                                  fontSize: 14,
                                  verticalPadding: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: EasyTabButton(
                                  label: loc.shareLinkCopy,
                                  onTap: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: createdLink!),
                                    );
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(loc.shareLinkCopied),
                                        ),
                                      );
                                      Navigator.of(ctx).pop();
                                    }
                                  },
                                  fontSize: 14,
                                  verticalPadding: 12,
                                ),
                              ),
                            ],
                          ),
                        ]
                      : [
                          // Заголовок
                          Row(
                            children: [
                              const Icon(
                                Icons.share,
                                color: AppColors.grey700,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  loc.createShareLink,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Срок действия
                          Text(
                            loc.shareLinkExpiresIn,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [1, 7, 30].map((days) {
                              final isSelected = selectedDays == days;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: days == 30 ? 0 : 8,
                                  ),
                                  child: InkWell(
                                    onTap: isCreating
                                        ? null
                                        : () => setDialogState(
                                            () => selectedDays = days,
                                          ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.grey700
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppColors.grey700
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        '$days ${loc.shareLinkDays}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // Права доступа
                          Text(
                            loc.shareAccess,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              PermissionOption(
                                label: loc.sharePermissionEdit,
                                icon: Icons.edit,
                                value: 'edit',
                                groupValue: selectedPermission,
                                onTap: isCreating
                                    ? null
                                    : () => setDialogState(
                                        () => selectedPermission = 'edit',
                                      ),
                              ),
                              const SizedBox(width: 8),
                              PermissionOption(
                                label: loc.sharePermissionView,
                                icon: Icons.visibility,
                                value: 'view',
                                groupValue: selectedPermission,
                                onTap: isCreating
                                    ? null
                                    : () => setDialogState(
                                        () => selectedPermission = 'view',
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // Кнопки
                          Row(
                            children: [
                              Expanded(
                                child: EasyTabButton(
                                  label: loc.cancel,
                                  onTap: isCreating
                                      ? null
                                      : () => Navigator.of(ctx).pop(),
                                  fontSize: 14,
                                  verticalPadding: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: EasyTabButton(
                                  label: isCreating ? '' : loc.createShareLink,
                                  onTap: isCreating ? null : doCreate,
                                  fontSize: 14,
                                  verticalPadding: 12,
                                  child: isCreating
                                      ? const Center(
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProcessingDialog(String message) {
    setState(() {
      _processingMessage = message;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_processingMessage),
          ],
        ),
      ),
    );
  }

  void _hideProcessingDialog() {
    if (!mounted) return;
    setState(() {
      _processingMessage = '';
    });
    // P3-47: pop только если диалог действительно активен.
    // Проверяем через canPop — иначе pop() закроет текущий экран,
    // если диалог уже был закрыт ранее.
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Загрузить все файлы отчёта на сервер по отдельности (не ZIP).
  ///
  /// Файлы загружаются в KS3 через POST /files/upload:
  ///   - report.json — данные отчёта (основное хранилище — БД, KS3 — бекап)
  ///   - report.xlsx — Excel-экспорт
  ///   - Медиафайлы (фото, видео) из маркеров ответов
  ///
  /// HTML-отчёт не загружается: сервер генерирует его сам из JSON-данных в БД.
  ///
  /// Каждый файл загружается отдельным запросом, сохраняя относительные пути,
  /// чтобы на сервере получить структуру папок отчёта.
  Future<void> _uploadReportToServer() async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();
    final authProvider = context.read<AuthProvider>();

    // Проверяем, что пользователь залогинен
    if (!authProvider.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.loginRequired)));
      }
      return;
    }

    // 1. Сохраняем отчёт локально (на нативных — чтобы файлы были на диске).
    await reportState.saveReport();

    try {
      // 2. Создаём/обновляем запись отчёта в БД, чтобы получить reportId
      //    и ks3Folder. Без reportId файлы не привяжутся к отчёту и
      //    загрузятся в общую папку files/{uuid}/, а не в папку отчёта.
      final saved = await reportState.saveReportToServer();
      final reportId = reportState.serverReportId;
      if (!saved || reportId == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.uploadError)));
        }
        return;
      }

      // 3. Собираем файлы для загрузки с диска.
      final filesToUpload = <Map<String, String>>[];

      final reportPath = reportState.currentReportPath;
      if (reportPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.uploadError)));
        }
        return;
      }

      // report.json — основной файл данных
      final jsonFile = File('$reportPath/report.json');
      if (await jsonFile.exists()) {
        filesToUpload.add({
          'filePath': jsonFile.path,
          'relativePath': 'report.json',
        });
      }

      // report.xlsx — Excel-экспорт
      final excelBytes = reportState.generateExcelBytes();
      final excelFile = File('$reportPath/report.xlsx');
      await excelFile.writeAsBytes(excelBytes);
      filesToUpload.add({
        'filePath': excelFile.path,
        'relativePath': 'report.xlsx',
      });

      // Заголовочное фото (если есть)
      final headerPath = reportState.currentReport?.headerImagePath;
      if (headerPath != null && headerPath.isNotEmpty) {
        final hFile = File('$reportPath/$headerPath');
        if (await hFile.exists()) {
          filesToUpload.add({
            'filePath': hFile.path,
            'relativePath': headerPath,
          });
        }
      }

      // Медиафайлы из ответов (фото, видео)
      final report = reportState.currentReport;
      if (report != null) {
        for (final markerEntry in report.markers.entries) {
          for (final answerMarker in markerEntry.value) {
            for (final media in answerMarker.media) {
              if (media.localPath != null && media.localPath!.isNotEmpty) {
                final mFile = File('$reportPath/${media.localPath}');
                if (await mFile.exists()) {
                  filesToUpload.add({
                    'filePath': mFile.path,
                    'relativePath': media.localPath!,
                  });
                }
              }
            }
          }
        }
      }

      if (filesToUpload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.noFilesToUpload)));
        }
        return;
      }

      // 4. Загружаем файлы на сервер с reportId — сервер привяжет их
      //    к отчёту и сложит в папку reports/{ks3Folder}/{relativePath}.
      _showProcessingDialog(loc.uploadingFiles);

      final result = await ApiService.uploadFiles(
        files: filesToUpload,
        reportId: reportId,
      );

      _hideProcessingDialog();

      if (!mounted) return;

      // 5. Показываем результат
      if (result.success) {
        final total = result.data?['total'] ?? 0;
        final successCount = result.data?['successCount'] ?? 0;
        final failedCount = result.data?['failedCount'] ?? 0;

        if (failedCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.uploadCompleteAll),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${loc.uploadCompletePartial}: $successCount/$total',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? loc.uploadError),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      _hideProcessingDialog();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${loc.uploadError}: $e')));
      }
    }
  }

  void _handleLanguageChange(String lang) {
    final reportState = context.read<ReportState>();
    final report = reportState.currentReport;
    if (report == null) return;

    final unsyncIndices = reportState.getUnsyncQuestionIndices();
    if (unsyncIndices.isNotEmpty) {
      _showSyncDialog(lang, unsyncIndices);
    } else {
      reportState.setLanguage(lang);
    }
  }

  void _showSyncDialog(String targetLang, List<int> unsyncIndices) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SyncDialog(
        reportState: context.read<ReportState>(),
        targetLang: targetLang,
        unsyncIndices: unsyncIndices,
        onSyncApplied: () async {
          final reportState = context.read<ReportState>();
          reportState.setLanguage(targetLang);
          _blockedQuestionIndices.clear();
          await reportState.saveReport();
        },
        onSkipSync: () {
          final reportState = context.read<ReportState>();
          reportState.setLanguage(targetLang);
          setState(() {
            _blockedQuestionIndices = unsyncIndices.toSet();
          });
        },
      ),
    );
  }

  void _showSyncMenuDialog() {
    final reportState = context.read<ReportState>();
    final report = reportState.currentReport;
    if (report == null) return;

    final unsyncIndices = reportState.getUnsyncQuestionIndices();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SyncMenuDialog(
        reportState: reportState,
        unsyncIndices: unsyncIndices,
        onApplied: () {},
      ),
    );
  }

  void _showDeleteAnswerDialog(
    BuildContext context,
    int i,
    int j,
    ReportState reportState,
  ) {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
        contentPadding: isMobile
            ? const EdgeInsets.all(16)
            : const EdgeInsets.all(24),
        shape: isMobile
            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
            : null,
        content: isMobile
            ? SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.deleteAnswerConfirm,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(loc.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.errorLight,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              final qid = i.toString();
                              _debounceTimers[qid]?[j]?.cancel();
                              _debounceTimers[qid]?.remove(j);
                              _answerControllers[qid]?[j]?.dispose();
                              _answerControllers[qid]?.remove(j);
                              _enabledAnswers[qid]?.remove(j);
                              await reportState.removeAnswer(i, j);
                              _markAsUnsaved();
                              if (context.mounted) Navigator.pop(ctx);
                            },
                            child: Text(loc.delete),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loc.deleteAnswerConfirm),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(loc.cancel),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.errorLight,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final qid = i.toString();
                          _debounceTimers[qid]?[j]?.cancel();
                          _debounceTimers[qid]?.remove(j);
                          _answerControllers[qid]?[j]?.dispose();
                          _answerControllers[qid]?.remove(j);
                          _enabledAnswers[qid]?.remove(j);
                          await reportState.removeAnswer(i, j);
                          _markAsUnsaved();
                          if (context.mounted) Navigator.pop(ctx);
                        },
                        child: Text(loc.delete),
                      ),
                    ],
                  ),
                ],
              ),
        title: isMobile ? null : Text(loc.deleteAnswerTitle),
      ),
    );
  }

  void _showLockDialog(
    BuildContext context,
    int i,
    int j,
    String qid,
    ReportState reportState,
  ) {
    final loc = AppLocalizations.of(context)!;
    final currentAnswer = reportState.currentReport?.getAnswersForQuestion(
      i,
      reportState.currentReport!.currentLanguage,
    )[j];
    final currentText = currentAnswer?['text'] ?? '';

    final TextEditingController replaceController = TextEditingController(
      text: currentText,
    );
    final TextEditingController newController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(context).size.width <= 800;
        return AlertDialog(
          insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
          contentPadding: isMobile
              ? const EdgeInsets.all(16)
              : const EdgeInsets.all(24),
          shape: isMobile
              ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
              : null,
          title: Text(loc.changeAnswerTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.lockWarningText,
                  style: const TextStyle(color: AppColors.errorLight),
                ),
                const SizedBox(height: 16),
                Text(
                  loc.replaceExistingAnswer,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: replaceController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: loc.enterNewAnswerText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.grey200),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  loc.orAddNewAnswer,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: loc.enterNewAnswerPlaceholder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.grey200),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _enabledAnswers[qid]![j] = true;
                });

                if (newController.text.isNotEmpty) {
                  reportState.addAnswer(i);
                  final newJ =
                      (reportState.currentReport
                              ?.getAnswersForQuestion(
                                i,
                                reportState.currentReport!.currentLanguage,
                              )
                              .length ??
                          1) -
                      1;
                  reportState.updateAnswerText(i, newJ, newController.text);
                } else if (replaceController.text.isNotEmpty &&
                    replaceController.text != currentText) {
                  reportState.updateAnswerText(i, j, replaceController.text);
                }

                Navigator.pop(ctx);
              },
              child: Text(loc.ok),
            ),
          ],
        );
      },
    );
  }

  /// Просмотр HTML на mobile/desktop.
  ///
  /// HTML генерируется на сервере (GET /reports/:publicId/html),
  /// поэтому отчёт должен быть синхронизирован. Скачанный HTML
  /// записывается в папку отчёта и открывается системным просмотрщиком.
  /// Медиа подгружаются через прокси-URL сервера (нужен интернет).
  Future<void> viewHtmlWithChooser() async {
    final reportState = context.read<ReportState>();
    final loc = AppLocalizations.of(context)!;

    // Отчёт должен быть на сервере — синхронизируем при необходимости.
    if (reportState.serverPublicId == null) {
      final synced = await reportState.saveReportToServer();
      if (!synced || reportState.serverPublicId == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.htmlRequiresSync)));
        }
        return;
      }
    }

    final result = await ApiService.getReportHtmlByPublicId(
      reportState.serverPublicId!,
    );
    final htmlContent = result.data?['html'] as String?;
    if (!result.success || htmlContent == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? loc.htmlRequiresSync)),
        );
      }
      return;
    }

    if (reportState.currentReportPath == null) {
      await reportState.saveReport();
    }

    final folderPath = reportState.currentReportPath!;
    final file = File('$folderPath/easy_report.html');
    await file.writeAsString(htmlContent);

    final openResult = await OpenFile.open(file.path);

    if (openResult.type == ResultType.noAppToOpen) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.noAppToOpenHtml)));
      }
    }
  }

  /// Просмотр HTML на web: открывает новую вкладку Flutter.
  ///
  /// Архитектура:
  ///   1. Flutter открывает новую вкладку: /#/view-report?pid=abc123
  ///   2. Новая вкладка — это Flutter-экран ViewReportHtmlScreen
  ///   3. Экран делает API-запрос: GET /reports/abc123/html
  ///   4. Сервер читает JSON из БД, генерирует HTML, возвращает {success, html}
  ///   5. Экран отображает HTML в iframe srcdoc
  ///   6. Медиа загружаются через серверный прокси /view/report/:id/files/...
  ///
  /// URL новой вкладки строится относительно текущего origin, поэтому работает
  /// на любом порту/домене, где развёрнут фронтенд.
  ///
  /// Если отчёт ещё не на сервере — сначала сохраняем. Без логина и
  /// share-токена серверный просмотр недоступен.
  Future<void> _viewHtmlOnWeb() async {
    final authProvider = context.read<AuthProvider>();
    final reportState = context.read<ReportState>();
    final loc = AppLocalizations.of(context)!;
    final origin = Uri.base.origin;

    // Залогиненный пользователь: открываем Flutter-маршрут /view-report.
    // Cookie auth_token уже установлен при логине, поэтому токен не нужен в URL.
    if (authProvider.isLoggedIn) {
      if (reportState.serverPublicId == null) {
        final saved = await reportState.saveReport();
        if (!saved || reportState.serverPublicId == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.htmlRequiresSync)));
          }
          return;
        }
      }
      final viewUrl = '$origin/#/view-report?pid=${reportState.serverPublicId}';
      openHtmlInBrowserUrl(viewUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HTML отчёт открыт в новой вкладке')),
        );
      }
      return;
    }

    // Анонимный пользователь по share-ссылке: открываем серверный
    // endpoint /reports/shares/:token/html. Сервер генерирует HTML
    // с proxy URL медиа, содержащими share_token.
    final shareToken = reportState.shareToken;
    if (shareToken != null && shareToken.isNotEmpty) {
      final anonymousId = await AnonymousIdService.getId();
      final uri = Uri.http(
        ApiService.baseUrl,
        '/reports/shares/$shareToken/html',
        {'anonymous_id': anonymousId},
      );
      openHtmlInBrowserUrl(uri.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HTML отчёт открыт в новой вкладке')),
        );
      }
      return;
    }

    // Нет ни логина, ни share-токена — серверный просмотр недоступен.
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.htmlRequiresSync)));
    }
  }

  /// Синхронизировать TextEditingController'ы с текущими ответами отчёта.
  ///
  /// Вызывается из listener'а ReportState (синхронно при notifyListeners),
  /// поэтому контроллеры всегда готовы к моменту пересборки виджета.
  /// Не вызывать из build() — метод имеет побочные эффекты (создание
  /// контроллеров, таймеров, dispose устаревших).
  void _syncControllers(ReportState reportState) {
    final report = reportState.currentReport;
    if (report == null) return;

    for (int i = 0; i < report.questions.length; i++) {
      final qid = i.toString();
      if (!_answerControllers.containsKey(qid)) {
        _answerControllers[qid] = {};
      }
      if (!_enabledAnswers.containsKey(qid)) {
        _enabledAnswers[qid] = {};
      }
      if (!_debounceTimers.containsKey(qid)) {
        _debounceTimers[qid] = {};
      }
      final answers = report.getAnswersForQuestion(i, report.currentLanguage);

      final existingIndices = _answerControllers[qid]?.keys.toList() ?? [];
      for (final j in existingIndices) {
        // Cancel any pending debounce timer to prevent stale updates
        _debounceTimers[qid]?[j]?.cancel();
        _debounceTimers[qid]?.remove(j);
        if (j >= answers.length) {
          _getSafeController(qid, j)?.dispose();
          _answerControllers[qid]?.remove(j);
          _enabledAnswers[qid]?.remove(j);
        }
      }

      for (int j = 0; j < answers.length; j++) {
        if (!_answerControllers[qid]!.containsKey(j)) {
          _answerControllers[qid]![j] = TextEditingController(
            text: answers[j]['text'] ?? '',
          );
          _getSafeController(qid, j)?.addListener(() {
            if (!_isUpdatingControllers) {
              _debounceTimers[qid] ??= {};
              _debounceTimers[qid]![j] = Timer(
                const Duration(milliseconds: 300),
                () {
                  reportState.updateAnswerText(
                    i,
                    j,
                    _getSafeController(qid, j)?.text ?? '',
                  );
                  if (!_hasUnsavedChanges) {
                    setState(() => _hasUnsavedChanges = true);
                  }
                },
              );
            }
          });
        } else {
          final controller = _getSafeController(qid, j);
          if (controller != null) {
            final newText = answers[j]['text'] ?? '';
            if (controller.text != newText) {
              _isUpdatingControllers = true;
              // НЕ сохраняем позицию курсора — сбрасываем выделение
              // и ставим курсор в конец текста. Это предотвращает
              // нежелательное выделение при синхронизации.
              controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: newText.length),
              );
              _isUpdatingControllers = false;
            }
          }
        }

        final hasOtherAnswers = reportState.hasAnswersInOtherLanguages(i, j);
        _enabledAnswers[qid]![j] = !hasOtherAnswers;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.watch<ReportState>();
    final report = reportState.currentReport;

    if (report == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(loc.newReport),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: Center(
          child: _isLoadingSharedReport
              ? const CircularProgressIndicator()
              : Text(loc.noQuestions),
        ),
      );
    }

    // Контроллеры синхронизируются в _onReportStateChanged (listener),
    // build() остаётся чистой функцией без побочных эффектов.

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            report.reportName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          // Report language switcher
          if (report.availableLanguages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: PopupMenuButton<String>(
                icon: Row(
                  children: [
                    const Icon(Icons.language),
                    const SizedBox(width: 4),
                    Text(
                      report.currentLanguage,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                itemBuilder: (ctx) => report.availableLanguages
                    .map(
                      (lang) => PopupMenuItem(
                        value: lang,
                        child: Row(
                          children: [
                            Text(lang),
                            if (lang == report.currentLanguage)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check, size: 16),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onSelected: (lang) {
                  _handleLanguageChange(lang);
                },
              ),
            ),
          IconButton(
            icon: Icon(
              _viewMode == ViewMode.list ? Icons.grid_view : Icons.list,
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == ViewMode.list
                    ? ViewMode.card
                    : ViewMode.list;
              });
              if (_viewMode == ViewMode.card) {
                Future.delayed(Duration.zero, () {
                  if (!_pageController.hasClients) return;
                  if (_currentPage == -1) {
                    _pageController.jumpToPage(0);
                  } else {
                    final page = _getPageForQuestion(_currentPage, report);
                    if (page >= 0) {
                      _pageController.jumpToPage(page);
                    }
                  }
                });
              }
            },
            tooltip: loc.toggleView,
          ),
          // Manual save button
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.save,
                    size: 24,
                    color: _hasUnsavedChanges
                        ? AppColors.primaryLight
                        : AppColors.greyDisabled,
                  ),
            onPressed: _hasUnsavedChanges && !_isSaving ? _doSave : null,
            tooltip: _hasUnsavedChanges ? loc.save : loc.saved,
          ),
          Consumer<LocaleProvider>(
            builder: (context, localeProvider, child) {
              final authProvider = context.watch<AuthProvider>();
              return PopupMenuButton<dynamic>(
                icon: const Icon(Icons.menu),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 0,
                    child: Row(
                      children: [
                        const Icon(Icons.visibility),
                        const SizedBox(width: 8),
                        Text(loc.viewHtml),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 1,
                    child: Row(
                      children: [
                        const Icon(Icons.save_alt),
                        const SizedBox(width: 8),
                        Text(loc.saveZip),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 2,
                    child: Row(
                      children: [
                        const Icon(Icons.share),
                        const SizedBox(width: 8),
                        Text(loc.share),
                      ],
                    ),
                  ),
                  // Сжатие видео — только на нативных платформах.
                  // На web видео сжимается автоматически (ffmpeg.wasm)
                  // при добавлении, ручная кнопка не нужна.
                  if (!kIsWeb)
                    PopupMenuItem(
                      value: 6,
                      child: Row(
                        children: [
                          const Icon(Icons.video_call),
                          const SizedBox(width: 8),
                          Text(loc.compressVideoTitle),
                        ],
                      ),
                    ),
                  // Создать share-ссылку — только для залогиненных пользователей.
                  if (authProvider.isLoggedIn)
                    PopupMenuItem(
                      value: 8,
                      child: Row(
                        children: [
                          const Icon(Icons.link),
                          const SizedBox(width: 8),
                          Text(loc.createShareLink),
                        ],
                      ),
                    ),
                  // "Залить на сервер" — только для залогиненных пользователей
                  // на нативных платформах. На web медиа грузятся через
                  // presigned сразу при добавлении, кнопка не нужна.
                  if (authProvider.isLoggedIn && !kIsWeb)
                    PopupMenuItem(
                      value: 7,
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_upload),
                          const SizedBox(width: 8),
                          Text(loc.uploadToServer),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 3,
                    child: Row(
                      children: [
                        const Icon(Icons.sync),
                        const SizedBox(width: 8),
                        Text(loc.syncTranslations),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 4,
                    child: Row(
                      children: [
                        const Icon(Icons.table_chart),
                        const SizedBox(width: 8),
                        Text(loc.exportExcel),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  // App language switcher
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      loc.appLanguage,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  PopupMenuItem(
                    value: const Locale('en'),
                    child: Row(
                      children: [
                        Text(loc.english),
                        if (localeProvider.locale.languageCode == 'en')
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 16),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: const Locale('ru'),
                    child: Row(
                      children: [
                        Text(loc.russian),
                        if (localeProvider.locale.languageCode == 'ru')
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 16),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: const Locale('zh'),
                    child: Row(
                      children: [
                        Text(loc.chinese),
                        if (localeProvider.locale.languageCode == 'zh')
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 16),
                          ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 5,
                    child: Row(
                      children: [
                        const Icon(Icons.exit_to_app),
                        const SizedBox(width: 8),
                        Text(loc.exit),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value is Locale) {
                    localeProvider.setLocale(value);
                  } else if (value == 0) {
                    // HTML генерируется на сервере — открываем серверный просмотр
                    if (kIsWeb) {
                      await _viewHtmlOnWeb();
                    } else {
                      // На мобильных/десктопах скачиваем HTML с сервера
                      // и открываем через системный просмотрщик
                      await viewHtmlWithChooser();
                    }
                  } else if (value == 4) {
                    final excelHtml = reportState.generateExcelHtmlContent();
                    try {
                      await Clipboard.setData(ClipboardData(text: excelHtml));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(loc.excelHtmlCopied)),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${loc.copyError}$e')),
                        );
                      }
                    }
                  } else if (value == 1) {
                    if (kIsWeb) {
                      final shareToken = reportState.shareToken;
                      final publicId = reportState.serverPublicId;
                      if (shareToken != null && shareToken.isNotEmpty) {
                        // Аноним / share-ссылка: скачиваем ZIP через share endpoint.
                        final anonymousId = await AnonymousIdService.getId();
                        final uri = Uri.http(
                          ApiService.baseUrl,
                          '/reports/shares/$shareToken/zip',
                          {'anonymous_id': anonymousId},
                        );
                        final zipName = buildShareZipName(
                          reportState.currentReport?.reportName ?? 'report',
                          shareToken,
                        );
                        downloadShareZip(uri.toString(), zipName);
                      } else if (publicId != null && publicId.isNotEmpty) {
                        // Залогиненный владелец: скачиваем ZIP через
                        // авторизованный endpoint с токеном в query.
                        final token = ApiService.authToken;
                        final query = token != null && token.isNotEmpty
                            ? {'token': token}
                            : <String, String>{};
                        final uri = Uri.http(
                          ApiService.baseUrl,
                          '/reports/$publicId/zip',
                          query,
                        );
                        final zipName = buildShareZipName(
                          reportState.currentReport?.reportName ?? 'report',
                          publicId,
                        );
                        downloadShareZip(uri.toString(), zipName);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(loc.saveZipWeb)));
                      }
                      return;
                    }
                    // Show hint on mobile devices - only hint, no action
                    if (Platform.isAndroid || Platform.isIOS) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(loc.saveZipMobileHint),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }
                    await reportState.saveReport();
                    try {
                      final result = await FilePicker.platform.saveFile(
                        dialogTitle: loc.saveZip,
                        fileName:
                            '${reportState.currentReport?.reportName.replaceAll(RegExp(r'[^\w\sа-яА-ЯёЁ\u4e00-\u9fff-]'), '').replaceAll(' ', '_')}.zip',
                        allowedExtensions: ['zip'],
                      );
                      if (result != null) {
                        _showProcessingDialog(loc.processingZip);
                        final zipPath = await reportState.exportZip(
                          customSavePath: path.dirname(result),
                          customFileName: path.basename(result),
                        );
                        _hideProcessingDialog();
                        if (zipPath != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${loc.zipSaved}$zipPath')),
                          );
                        }
                      }
                    } catch (e) {
                      _hideProcessingDialog();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${loc.saveZipError}$e')),
                        );
                      }
                    }
                  } else if (value == 2) {
                    if (kIsWeb) {
                      // На web кнопка «Поделиться» создаёт share-ссылку
                      await _showCreateShareLinkDialog();
                    } else {
                      await reportState.saveReport();
                      _showProcessingDialog(loc.processingZip);
                      final zipPath = await reportState.exportZip();
                      _hideProcessingDialog();
                      if (zipPath != null && mounted) {
                        await reportState.shareZip(zipPath);
                      }
                    }
                  } else if (value == 3) {
                    _showSyncMenuDialog();
                  } else if (value == 5) {
                    Navigator.pushReplacementNamed(context, '/');
                  } else if (value == 6) {
                    // Сжать все видео отчёта (native)
                    _showCompressVideoDialog();
                  } else if (value == 7) {
                    // Залить отчёт на сервер (только для залогиненных)
                    await _uploadReportToServer();
                  } else if (value == 8) {
                    // Создать share-ссылку
                    await _handleCreateShareLink();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth <= 800;
          return Stack(
            children: [
              const DottedBackground(),
              if (!isMobile)
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isSidePanelCollapsed ? 40 : 220,
                      child: _isSidePanelCollapsed
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSidePanelCollapsed = false;
                                });
                              },
                              child: Container(
                                width: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    right: BorderSide(
                                      width: 2,
                                      color: AppColors.border,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 16),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.textPrimary,
                                    ),
                                    const SizedBox(height: 8),
                                    RotatedBox(
                                      quarterTurns: 3,
                                      child: Text(
                                        loc.questions,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              width: 220,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  right: BorderSide(
                                    width: 2,
                                    color: AppColors.border,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    color: AppColors.grey100,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      4,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          loc.questions,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left),
                                          onPressed: () {
                                            setState(() {
                                              _isSidePanelCollapsed = true;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    color: AppColors.grey100,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      8,
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _hideAnsweredQuestions =
                                              !_hideAnsweredQuestions;
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: Checkbox(
                                              value: _hideAnsweredQuestions,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              fillColor:
                                                  WidgetStateProperty.resolveWith(
                                                    (states) {
                                                      if (states.contains(
                                                        WidgetState.selected,
                                                      )) {
                                                        return AppColors
                                                            .textPrimary;
                                                      }
                                                      return AppColors
                                                          .greyDisabled;
                                                    },
                                                  ),
                                              onChanged: (value) {
                                                setState(() {
                                                  _hideAnsweredQuestions =
                                                      value ?? false;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              loc.hideAnswered,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ScrollablePositionedList.builder(
                                      itemScrollController:
                                          _sidePanelItemScrollController,
                                      itemCount:
                                          _getFilteredQuestionCount(report) + 1,
                                      itemBuilder: (ctx, index) {
                                        if (index ==
                                            _getFilteredQuestionCount(report)) {
                                          return const SizedBox(height: 80);
                                        }
                                        if (index == 0) {
                                          return HeaderSidePanelTile(
                                            report: report,
                                            onTap: () {
                                              setState(() {
                                                _currentPage = -1;
                                                _isSidePanelCollapsed = true;
                                              });
                                              if (_viewMode == ViewMode.card) {
                                                _pageController.animateToPage(
                                                  0,
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  curve: Curves.ease,
                                                );
                                              } else {
                                                if (_listItemScrollController
                                                    .isAttached) {
                                                  _listItemScrollController
                                                      .scrollTo(
                                                        index: 0,
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 300,
                                                            ),
                                                        curve: Curves.ease,
                                                      );
                                                }
                                              }
                                            },
                                          );
                                        }
                                        final i = _getFilteredQuestionIndex(
                                          index - 1,
                                          report,
                                        );
                                        if (i == -1) {
                                          return const SizedBox.shrink();
                                        }
                                        final lang = report.currentLanguage;
                                        final answers = report
                                            .getAnswersForQuestion(i, lang);
                                        final answerCount = answers
                                            .where(
                                              (a) => !(a['isEmpty'] == true),
                                            )
                                            .length;
                                        final attentionCount = answers
                                            .where(
                                              (a) => a['attention'] == true,
                                            )
                                            .length;

                                        final q = report.questions[i];
                                        final questionLoc = q.getLocalization(
                                          lang,
                                        );
                                        final hasTranslation = q.hasTranslation(
                                          lang,
                                        );

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Material(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _currentPage = i;
                                                });
                                                if (_viewMode ==
                                                    ViewMode.card) {
                                                  final page =
                                                      _getPageForQuestion(
                                                        i,
                                                        report,
                                                      );
                                                  if (page >= 0) {
                                                    _pageController
                                                        .animateToPage(
                                                          page,
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    300,
                                                              ),
                                                          curve: Curves.ease,
                                                        );
                                                  }
                                                } else {
                                                  _scrollToQuestion(i);
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    width: 1.5,
                                                    color:
                                                        _viewMode ==
                                                                ViewMode.card &&
                                                            _currentPage == i
                                                        ? const Color(
                                                            0xFF3b82f6,
                                                          )
                                                        : const Color(
                                                            0xFFe5e7eb,
                                                          ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFF333333,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Center(
                                                            child: Text(
                                                              '${i + 1}',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            questionLoc?.name ??
                                                                q.getDisplayName(
                                                                  lang,
                                                                ) ??
                                                                loc.noName,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: Color(
                                                                    0xFF424242,
                                                                  ),
                                                                ),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    if (!hasTranslation &&
                                                        q.hasSomeTranslation())
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFfff3cd,
                                                          ),
                                                          border: Border.all(
                                                            width: 1,
                                                            color: const Color(
                                                              0xFFffc107,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          loc.switchLanguage,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xFF856404,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                answerCount > 0
                                                                ? const Color(
                                                                    0xFFd1fae5,
                                                                  )
                                                                : const Color(
                                                                    0xFFe5e7eb,
                                                                  ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            '$answerCount',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color:
                                                                  answerCount >
                                                                      0
                                                                  ? const Color(
                                                                      0xFF065f46,
                                                                    )
                                                                  : const Color(
                                                                      0xFF6b7280,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        if (attentionCount > 0)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFfff3cd,
                                                                  ),
                                                              border: Border.all(
                                                                width: 1,
                                                                color:
                                                                    const Color(
                                                                      0xFFfbbf24,
                                                                    ),
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                const Text(
                                                                  '⚡',
                                                                  style:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  '$attentionCount',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    color: Color(
                                                                      0xFF92400e,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        if (_needsWorkMap[i] ==
                                                            true)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFfef3c7,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.edit_note,
                                                              size: 14,
                                                              color: Color(
                                                                0xFFd97706,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Expanded(
                      child: _viewMode == ViewMode.list
                          ? _buildListView(reportState, report)
                          : _buildCardView(reportState, report),
                    ),
                  ],
                ),
              if (isMobile)
                Positioned.fill(
                  child: _viewMode == ViewMode.list
                      ? _buildListView(reportState, report)
                      : _buildCardView(reportState, report),
                ),
              if (isMobile && !_isSidePanelCollapsed)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSidePanelCollapsed = true;
                      });
                    },
                    child: const ColoredBox(
                      color: Color(0x80000000), // black 50% opacity
                    ),
                  ),
                ),
              if (isMobile && !_isSidePanelCollapsed)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 280,
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Container(
                          color: AppColors.grey100,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Row(
                            children: [
                              Text(
                                loc.questions,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _isSidePanelCollapsed = true;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        Container(
                          color: AppColors.grey100,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _hideAnsweredQuestions =
                                    !_hideAnsweredQuestions;
                              });
                            },
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _hideAnsweredQuestions,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    fillColor: WidgetStateProperty.resolveWith((
                                      states,
                                    ) {
                                      if (states.contains(
                                        WidgetState.selected,
                                      )) {
                                        return AppColors.textPrimary;
                                      }
                                      return AppColors.greyDisabled;
                                    }),
                                    onChanged: (value) {
                                      setState(() {
                                        _hideAnsweredQuestions = value ?? false;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    loc.hideAnswered,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ScrollablePositionedList.builder(
                            itemScrollController:
                                _sidePanelItemScrollController,
                            itemCount: _getFilteredQuestionCount(report) + 1,
                            itemBuilder: (ctx, index) {
                              if (index == _getFilteredQuestionCount(report)) {
                                return const SizedBox(height: 80);
                              }
                              if (index == 0) {
                                return HeaderSidePanelTile(
                                  report: report,
                                  onTap: () {
                                    setState(() {
                                      _currentPage = -1;
                                      _isSidePanelCollapsed = true;
                                    });
                                    if (_viewMode == ViewMode.card) {
                                      _pageController.animateToPage(
                                        0,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.ease,
                                      );
                                    } else {
                                      if (_listItemScrollController
                                          .isAttached) {
                                        _listItemScrollController.scrollTo(
                                          index: 0,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.ease,
                                        );
                                      }
                                    }
                                  },
                                );
                              }
                              final i = _getFilteredQuestionIndex(
                                index - 1,
                                report,
                              );
                              if (i == -1) return const SizedBox.shrink();
                              final lang = report.currentLanguage;
                              final answers = report.getAnswersForQuestion(
                                i,
                                lang,
                              );
                              final answerCount = answers
                                  .where((a) => !(a['isEmpty'] == true))
                                  .length;
                              final attentionCount = answers
                                  .where((a) => a['attention'] == true)
                                  .length;

                              final q = report.questions[i];
                              final questionLoc = q.getLocalization(lang);
                              final hasTranslation = q.hasTranslation(lang);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentPage = i;
                                        _isSidePanelCollapsed = true;
                                      });
                                      if (_viewMode == ViewMode.card) {
                                        final page = _getPageForQuestion(
                                          i,
                                          report,
                                        );
                                        if (page >= 0) {
                                          _pageController.animateToPage(
                                            page,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.ease,
                                          );
                                        }
                                      } else {
                                        _scrollToQuestion(i);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          width: 1.5,
                                          color:
                                              _viewMode == ViewMode.card &&
                                                  _currentPage == i
                                              ? AppColors.primaryLight
                                              : AppColors.grey200,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF333333,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  questionLoc?.name ??
                                                      q.getDisplayName(lang) ??
                                                      loc.noName,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (!hasTranslation &&
                                              q.hasSomeTranslation())
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.warningLight,
                                                border: Border.all(
                                                  width: 1,
                                                  color: const Color(
                                                    0xFFffc107,
                                                  ),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                loc.switchLanguage,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.warningDark,
                                                ),
                                              ),
                                            ),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: answerCount > 0
                                                      ? AppColors.successLight
                                                      : AppColors.grey200,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '$answerCount',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: answerCount > 0
                                                        ? const Color(
                                                            0xFF065f46,
                                                          )
                                                        : const Color(
                                                            0xFF6b7280,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              if (attentionCount > 0)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFfff3cd,
                                                    ),
                                                    border: Border.all(
                                                      width: 1,
                                                      color: const Color(
                                                        0xFFfbbf24,
                                                      ),
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Text(
                                                        '⚡',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '$attentionCount',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Color(
                                                            0xFF92400e,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              const SizedBox(width: 4),
                                              if (_needsWorkMap[i] == true)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFfef3c7,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.edit_note,
                                                    size: 14,
                                                    color:
                                                        AppColors.warningAccent,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _scrollToQuestion(int index) {
    // index is 0-based question index; in list, item at listIndex where visibleIndices[listIndex] == index+1
    if (!_listItemScrollController.isAttached) return;
    final report = context.read<ReportState>().currentReport;
    if (report == null) return;
    // Build same visibleIndices as _buildListView
    final visibleIndices = <int>[0];
    for (int i = 0; i < report.questions.length; i++) {
      if (_shouldShowQuestion(i, report)) {
        visibleIndices.add(i + 1);
      }
    }
    final targetValue = index + 1;
    final listIndex = visibleIndices.indexOf(targetValue);
    if (listIndex < 0) return;
    _listItemScrollController.scrollTo(
      index: listIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
      alignment: 0.0,
    );
  }

  void _scrollSidePanelToQuestion(int questionIndex, Report report) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sidePanelItemScrollController.isAttached) return;
      // Calculate visible index in side panel
      int visibleIndex;
      if (questionIndex == -1) {
        visibleIndex = 0; // header
      } else if (!_hideAnsweredQuestions) {
        visibleIndex = questionIndex + 1;
      } else {
        int seen = 1; // header is always first
        for (int i = 0; i <= questionIndex; i++) {
          if (_shouldShowQuestion(i, report)) seen++;
        }
        visibleIndex = seen - 1;
      }
      _sidePanelItemScrollController.scrollTo(
        index: visibleIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
        alignment: 0.5, // center the item
      );
    });
  }

  bool _shouldShowQuestion(int i, Report report) {
    if (!_hideAnsweredQuestions) return true;
    if (_needsWorkMap[i] == true) return true;
    final lang = report.currentLanguage;
    final answers = report.getAnswersForQuestion(i, lang);
    final hasFilledAnswer = answers.any((a) => !(a['isEmpty'] == true));
    return !hasFilledAnswer;
  }

  int _getFilteredQuestionCount(Report report) {
    if (!_hideAnsweredQuestions) return report.questions.length + 1;
    int count = 1; // card 0 always visible
    for (int i = 0; i < report.questions.length; i++) {
      if (_shouldShowQuestion(i, report)) count++;
    }
    return count;
  }

  int _getFilteredQuestionIndex(int visibleIndex, Report report) {
    if (!_hideAnsweredQuestions) return visibleIndex;
    int seen = 0;
    for (int i = 0; i < report.questions.length; i++) {
      if (_shouldShowQuestion(i, report)) {
        if (seen == visibleIndex) return i;
        seen++;
      }
    }
    return -1;
  }

  /// Get the page index in filtered PageView for a given question index
  int _getPageForQuestion(int questionIndex, Report report) {
    if (!_hideAnsweredQuestions) return questionIndex + 1;
    int page = 1; // page 0 is header
    for (int i = 0; i < questionIndex; i++) {
      if (_shouldShowQuestion(i, report)) page++;
    }
    // Check if this question is visible
    if (_shouldShowQuestion(questionIndex, report)) return page;
    return -1; // question is hidden
  }

  Widget _buildListView(ReportState reportState, Report report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth <= 800;
        // Build list of visible items: always include index 0 (header),
        // then only questions that pass the filter
        final visibleIndices = <int>[0];
        for (int i = 0; i < report.questions.length; i++) {
          if (_shouldShowQuestion(i, report)) {
            visibleIndices.add(i + 1);
          }
        }
        return ScrollablePositionedList.builder(
          itemScrollController: _listItemScrollController,
          itemCount: visibleIndices.length + 1,
          itemBuilder: (ctx, listIndex) {
            if (listIndex == visibleIndices.length) {
              return const SizedBox(height: 120);
            }
            final index = visibleIndices[listIndex];
            if (index == 0) {
              return Padding(
                padding: isMobile
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(vertical: 8),
                child: HeaderListTile(
                  report: report,
                  reportState: reportState,
                  isMobile: isMobile,
                  onNavigateToHeader: () {
                    setState(() {
                      _currentPage = -1;
                      if (isMobile) {
                        _isSidePanelCollapsed = false;
                      }
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollSidePanelToQuestion(-1, report);
                    });
                  },
                ),
              );
            }
            return Padding(
              padding: isMobile
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              child: _buildQuestionCard(ctx, index - 1, reportState, false),
            );
          },
        );
      },
    );
  }

  Widget _buildCardView(ReportState reportState, Report report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final loc = AppLocalizations.of(context)!;
        if (report.questions.isEmpty) {
          return Center(child: Text(loc.noQuestions));
        }
        final isMobile = constraints.maxWidth <= 800;
        // Build list of visible page indices: always include 0 (header),
        // then only questions that pass the filter
        final visiblePageIndices = <int>[0];
        for (int i = 0; i < report.questions.length; i++) {
          if (_shouldShowQuestion(i, report)) {
            visiblePageIndices.add(i + 1);
          }
        }
        return Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (page) {
                // Снимаем фокус с полей предыдущей страницы: иначе курсор
                // на невидимой карточке вызывает автоматическую прокрутку
                // обратно (showOnScreen) при любом обновлении состояния.
                FocusManager.instance.primaryFocus?.unfocus();
                final realIndex = page < visiblePageIndices.length
                    ? visiblePageIndices[page]
                    : page;
                final newPage = realIndex == 0 ? -1 : realIndex - 1;
                if (_currentPage != newPage && _hasUnsavedChanges) {
                  _doSave();
                }
                setState(() {
                  _currentPage = newPage;
                });
                if (newPage >= 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollSidePanelToQuestion(newPage, report);
                  });
                }
              },
              physics: const BouncingScrollPhysics(),
              itemCount: visiblePageIndices.length,
              itemBuilder: (context, pageIdx) {
                final index = pageIdx < visiblePageIndices.length
                    ? visiblePageIndices[pageIdx]
                    : pageIdx;
                if (index == 0) {
                  return SingleChildScrollView(
                    padding: isMobile
                        ? const EdgeInsets.only(bottom: 100)
                        : const EdgeInsets.all(20),
                    child: Center(
                      child: HeaderCard(
                        report: report,
                        reportState: reportState,
                        onOpenSidePanel: () {
                          setState(() => _isSidePanelCollapsed = false);
                        },
                        onNavigateToHeader: () {
                          setState(() => _isSidePanelCollapsed = false);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollSidePanelToQuestion(-1, report);
                          });
                        },
                        onEditHeader: () =>
                            _showEditHeaderDialog(context, reportState),
                        onPhotoAreaTap: () =>
                            _showHeaderPhotoPicker(context, reportState),
                      ),
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: isMobile
                      ? const EdgeInsets.only(bottom: 100)
                      : const EdgeInsets.all(20),
                  child: Center(
                    child: _buildQuestionCard(
                      context,
                      index - 1,
                      reportState,
                      true,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _currentPage == -1
                        ? '0 / ${report.questions.length}'
                        : '${_currentPage + 1} / ${report.questions.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            if (_isSaving)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text('⏳', style: TextStyle(fontSize: 32)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showEditHeaderDialog(BuildContext context, ReportState reportState) {
    final report = reportState.currentReport;
    if (report == null) return;
    final loc = AppLocalizations.of(context)!;

    final productTypeController = TextEditingController(
      text: report.productType,
    );
    final factoryController = TextEditingController(text: report.factory);
    final modelController = TextEditingController(text: report.model);

    final hadHeaderImageBefore =
        report.headerImagePath != null && report.headerImagePath!.isNotEmpty;

    String? tempPhotoPath;
    if (hadHeaderImageBefore && reportState.currentReportPath != null) {
      final sourceFile = File(
        '${reportState.currentReportPath}/${report.headerImagePath}',
      );
      if (sourceFile.existsSync()) {
        final tempDir = Directory.systemTemp;
        final tempFile = File(
          '${tempDir.path}/header_edit_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        sourceFile.copySync(tempFile.path);
        tempPhotoPath = tempFile.path;
      }
    }

    // Байты для web-превью
    Uint8List? tempPhotoBytes;
    String? tempPhotoFileName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      enableDrag: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasImage = tempPhotoPath != null || tempPhotoBytes != null;
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.grey200, width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        loc.editHeader,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 20),
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    children: [
                      HeaderField(
                        label: loc.productType,
                        controller: productTypeController,
                      ),
                      const SizedBox(height: 12),
                      HeaderField(
                        label: loc.factory,
                        controller: factoryController,
                      ),
                      const SizedBox(height: 12),
                      HeaderField(
                        label: loc.model,
                        controller: modelController,
                      ),
                      const SizedBox(height: 16),
                      HeaderPhotoPicker(
                        hasImage: hasImage,
                        imagePath: kIsWeb ? null : tempPhotoPath,
                        imageBytes: kIsWeb ? tempPhotoBytes : null,
                        loc: loc,
                        onImagePathChanged: (path) {
                          setDialogState(() {
                            tempPhotoPath = path;
                            tempPhotoBytes = null;
                            tempPhotoFileName = null;
                          });
                        },
                        onImageBytesChanged: (bytes) {
                          setDialogState(() {
                            tempPhotoBytes = bytes;
                            tempPhotoPath = null;
                            tempPhotoFileName =
                                'header_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            reportState.updateHeaderInfo(
                              productType: productTypeController.text.trim(),
                              factory: factoryController.text.trim(),
                              model: modelController.text.trim(),
                            );
                            try {
                              if (kIsWeb) {
                                if (tempPhotoBytes != null) {
                                  await reportState.addHeaderImageFromBytes(
                                    tempPhotoBytes!,
                                    tempPhotoFileName ?? 'header.jpg',
                                  );
                                } else if (hadHeaderImageBefore) {
                                  await reportState.removeHeaderImage();
                                }
                              } else {
                                if (tempPhotoPath != null) {
                                  await reportState.addHeaderImage(
                                    File(tempPhotoPath!),
                                  );
                                } else if (hadHeaderImageBefore) {
                                  await reportState.removeHeaderImage();
                                }
                              }
                            } catch (e) {
                              debugPrint('Header image error: $e');
                            }
                            await reportState.saveReport();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.border,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            loc.save,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    int index,
    ReportState reportState,
    bool isCardView,
  ) {
    final report = reportState.currentReport!;
    return QuestionCard(
      index: index,
      reportState: reportState,
      isCardView: isCardView,
      answerControllerFor: _getSafeController,
      answerEnabledFor: (qid, j) => _enabledAnswers[qid]?[j] ?? true,
      needsWork: _needsWorkMap[index] == true,
      onNeedsWorkChanged: (newValue) {
        setState(() {
          _needsWorkMap[index] = newValue;
        });
      },
      onMarkAsUnsaved: _markAsUnsaved,
      onQuestionNumberTap: () {
        setState(() {
          _isSidePanelCollapsed = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollSidePanelToQuestion(index, report);
        });
      },
      onEditQuestion: (fieldType) => _showEditQuestionDialog(
        context,
        index,
        reportState,
        fieldType,
        _markAsUnsaved,
      ),
      onAddQuestionAbove: () {
        _resetControllers();
        reportState.addQuestion(index - 1);
        if (index > 0) {
          _pageController.animateToPage(
            index - 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
          );
        }
      },
      onAddQuestionBelow: () {
        _resetControllers();
        reportState.addQuestion(index);
        _pageController.animateToPage(
          index + 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      },
      onDeleteQuestion: () async {
        _resetControllers();
        await reportState.removeQuestion(index);
        if (_currentPage >= report.questions.length) {
          _currentPage = report.questions.isNotEmpty
              ? report.questions.length - 1
              : -1;
        }
        if (_currentPage == -1) {
          _pageController.jumpToPage(0);
        } else {
          final page = _getPageForQuestion(_currentPage, report);
          if (page >= 0) {
            _pageController.jumpToPage(page);
          }
        }
        _markAsUnsaved();
      },
      onShowMediaPicker: (j) => _showMediaPicker(context, index, j, false),
      onShowLockDialog: (j, qid) =>
          _showLockDialog(context, index, j, qid, reportState),
      onShowDeleteAnswerDialog: (j) =>
          _showDeleteAnswerDialog(context, index, j, reportState),
    );
  }

  /// Диалог выбора качества и запуск сжатия всех видео отчёта (native).
  void _showCompressVideoDialog() {
    final loc = AppLocalizations.of(context)!;
    int selectedQuality = 2;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.compressVideoTitle),
        content: StatefulBuilder(
          builder: (dialogCtx, setDialogState) => RadioGroup<int>(
            groupValue: selectedQuality,
            onChanged: (value) =>
                setDialogState(() => selectedQuality = value ?? 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<int>(
                  title: Text(loc.highQuality),
                  subtitle: Text(loc.highQualityDesc),
                  value: 1,
                ),
                RadioListTile<int>(
                  title: Text(loc.mediumQuality),
                  subtitle: Text(loc.mediumQualityDesc),
                  value: 2,
                ),
                RadioListTile<int>(
                  title: Text(loc.lowQuality),
                  subtitle: Text(loc.lowQualityDesc),
                  value: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _compressVideosWithQuality(selectedQuality);
            },
            child: Text(loc.ok),
          ),
        ],
      ),
    );
  }

  /// Сжатие всех видео с прогресс-диалогом (native, v_video_compressor).
  Future<void> _compressVideosWithQuality(int quality) async {
    final reportState = context.read<ReportState>();
    final loc = AppLocalizations.of(context)!;

    int current = 0;
    int total = 0;
    StateSetter? setDialogState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setState) {
          setDialogState = setState;
          return AlertDialog(
            title: Text(loc.compressVideoTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loc.compressingVideo),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: total > 0 ? current / total : 0),
                const SizedBox(height: 8),
                Text(
                  total > 0 ? '$current / $total' : '',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final compressed = await reportState.compressVideosWithSettings(
        qualityLevel: quality,
        onProgress: (c, t) {
          current = c;
          total = t;
          // Перерисовываем прогресс-диалог (в старой версии этого
          // вызова не было, и индикатор всегда стоял на нуле).
          setDialogState?.call(() {});
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // закрыть прогресс-диалог

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            compressed.isEmpty
                ? loc.noVideoToCompress
                : '${loc.compressionComplete}: '
                      '${loc.compressedVideoCount(compressed.length)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.compressionError(e.toString()))),
      );
    }
  }

  /// Показывает диалог выбора фото для шапки (только фото, без видео).
  Future<void> _showHeaderPhotoPicker(
    BuildContext context,
    ReportState reportState,
  ) async {
    // Снимаем фокус с текстовых полей, чтобы после добавления фото
    // PageView не прокручивался к полю с курсором.
    FocusManager.instance.primaryFocus?.unfocus();
    final loc = AppLocalizations.of(context)!;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.addMediaTitle,
                  style: const TextStyle(
                    color: AppColors.border,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle(title: loc.createSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.camera_alt,
                  label: loc.takePhoto,
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: AppColors.grey300,
                    thickness: 1.5,
                    height: 1.5,
                  ),
                ),
                SectionTitle(title: loc.selectSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.photo_library,
                  label: loc.photoFromGallery,
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    final picker = ImagePicker();
    XFile? image;

    if (action == 'camera') {
      image = await picker.pickImage(source: ImageSource.camera);
    } else if (action == 'gallery') {
      image = await picker.pickImage(source: ImageSource.gallery);
    }

    if (image == null) return;

    // Валидация: только изображения
    final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
    final ext = image.path.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Неверный формат файла')),
      );
      return;
    }

    // Проверка размера (макс 10MB)
    final fileSize = kIsWeb
        ? (await image.readAsBytes()).length
        : File(image.path).lengthSync();
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (fileSize > maxSize) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Файл слишком большой (макс. 10MB)')),
      );
      return;
    }

    try {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        final fileName = 'header_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await reportState.addHeaderImageFromBytes(bytes, fileName);
      } else {
        await reportState.addHeaderImage(File(image.path));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Фото добавлено')),
      );
    } catch (e) {
      debugPrint('Header photo error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _showMediaPicker(
    BuildContext context,
    int questionIndex,
    int answerIndex,
    bool isAttention,
  ) async {
    // Снимаем фокус с текстовых полей, чтобы после добавления медиа
    // PageView не прокручивался к полю с курсором.
    FocusManager.instance.primaryFocus?.unfocus();
    final loc = AppLocalizations.of(context)!;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.addMediaTitle,
                  style: const TextStyle(
                    color: AppColors.border,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle(title: loc.createSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.camera_alt,
                  label: loc.takePhoto,
                  onTap: () => Navigator.pop(ctx, 'camera-photo'),
                ),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.videocam,
                  label: loc.takeVideo,
                  onTap: () => Navigator.pop(ctx, 'camera-video'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: AppColors.grey300,
                    thickness: 1.5,
                    height: 1.5,
                  ),
                ),
                SectionTitle(title: loc.selectSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.photo_library,
                  label: loc.photoFromGallery,
                  onTap: () => Navigator.pop(ctx, 'gallery-photo'),
                ),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.video_library,
                  label: loc.videoFromGallery,
                  onTap: () => Navigator.pop(ctx, 'gallery-video'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    // ===== Web: используем XFile/PlatformFile напрямую =====
    if (kIsWeb) {
      final List<XFile> selectedXFiles = [];
      final List<PlatformFile> selectedPlatformFiles = [];

      if (action == 'camera-photo') {
        final picker = ImagePicker();
        final file = await picker.pickImage(source: ImageSource.camera);
        if (file != null) selectedXFiles.add(file);
      } else if (action == 'camera-video') {
        final picker = ImagePicker();
        final file = await picker.pickVideo(source: ImageSource.camera);
        if (file != null) selectedXFiles.add(file);
      } else if (action == 'gallery-photo') {
        final picker = ImagePicker();
        final files = await picker.pickMultiImage();
        selectedXFiles.addAll(files);
      } else if (action == 'gallery-video') {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.video,
          withData: true, // Важно: загружаем байты сразу
        );
        if (result != null && result.files.isNotEmpty) {
          selectedPlatformFiles.addAll(result.files);
        }
      }

      if (selectedXFiles.isEmpty && selectedPlatformFiles.isEmpty) return;

      if (!context.mounted) return;
      final reportState = context.read<ReportState>();
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      void onVideoError(String code) {
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        String message;
        switch (code) {
          case 'ffmpegTrafficWarning':
            message = loc.ffmpegTrafficWarning;
            break;
          case 'compression_ineffective':
            message = loc.videoCompressionIneffective;
            break;
          case 'compression_failed':
            message = loc.videoCompressionFailed;
            break;
          case 'upload_failed':
          default:
            message = loc.videoUploadFailed;
            break;
        }
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
      }

      try {
        var anyAdded = false;

        // Обрабатываем XFile (image_picker) — преобразуем в PlatformFile
        // для единообразной обработки (включая сжатие видео).
        for (final file in selectedXFiles) {
          final bytes = await file.readAsBytes();
          final platformFile = PlatformFile(
            name: file.name,
            size: bytes.length,
            bytes: bytes,
          );
          await reportState.addMediaFromBytes(
            questionIndex: questionIndex,
            answerIndex: answerIndex,
            bytes: bytes,
            fileName: platformFile.name,
            mimeType: mimeTypeFromFilename(platformFile.name),
            isAttention: isAttention,
            onVideoError: onVideoError,
          );
          anyAdded = true;
        }

        // Обрабатываем PlatformFile (file_picker)
        for (final file in selectedPlatformFiles) {
          if (file.bytes == null) continue;
          await reportState.addMediaFromBytes(
            questionIndex: questionIndex,
            answerIndex: answerIndex,
            bytes: file.bytes!,
            fileName: file.name,
            mimeType: mimeTypeFromFilename(file.name),
            isAttention: isAttention,
            onVideoError: onVideoError,
          );
          anyAdded = true;
        }

        // Сохраняем отчёт в фоне, не блокируя UI, только если что-то добавлено.
        if (anyAdded) {
          reportState.saveReport().then((_) {
            if (mounted) {
              setState(() {
                _hasUnsavedChanges = false;
              });
            }
          });
        }
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('${loc.saveError}$e')),
        );
      }
      return;
    }

    // ===== Mobile/Desktop: используем File =====
    final List<File> selectedFiles = [];

    if (action == 'camera-photo') {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file != null) {
        selectedFiles.add(File(file.path));
      }
    } else if (action == 'camera-video') {
      final picker = ImagePicker();
      final file = await picker.pickVideo(source: ImageSource.camera);
      if (file != null) {
        selectedFiles.add(File(file.path));
      }
    } else if (action == 'gallery-photo') {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isNotEmpty) {
        for (final file in files) {
          selectedFiles.add(File(file.path));
        }
      }
    } else if (action == 'gallery-video') {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.video,
      );
      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            selectedFiles.add(File(file.path!));
          }
        }
      }
    }

    if (selectedFiles.isEmpty) return;

    if (!context.mounted) return;
    final reportState = context.read<ReportState>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      for (final file in selectedFiles) {
        await reportState.addMedia(
          questionIndex,
          answerIndex,
          file,
          isAttention,
        );
      }

      reportState.saveReport().then((_) {
        if (mounted) {
          setState(() {
            _hasUnsavedChanges = false;
          });
        }
      });
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('${loc.saveError}$e')),
      );
    }
  }
}

void _showEditQuestionDialog(
  BuildContext context,
  int questionIndex,
  ReportState reportState,
  String fieldType,
  VoidCallback? onSaved,
) {
  final report = reportState.currentReport;
  if (report == null) return;

  final loc = AppLocalizations.of(context)!;
  final q = report.questions[questionIndex];
  final lang = report.currentLanguage;
  final questionLoc = q.getLocalization(lang);

  String currentValue = '';
  String title = '';

  if (fieldType == 'name') {
    title = loc.editName;
    currentValue = questionLoc?.name ?? q.getDisplayName(lang) ?? '';
  } else if (fieldType == 'description') {
    title = loc.editDescription;
    currentValue = questionLoc?.description ?? '';
  }

  final controller = TextEditingController(text: currentValue);

  showDialog(
    context: context,
    builder: (ctx) {
      final isMobile = MediaQuery.of(context).size.width <= 800;
      return AlertDialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
        contentPadding: isMobile
            ? const EdgeInsets.all(16)
            : const EdgeInsets.all(24),
        shape: isMobile
            ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
            : null,
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: fieldType == 'description' ? 3 : 1,
          autofocus: false,
          decoration: InputDecoration(
            hintText: fieldType == 'name' ? loc.enterName : loc.enterDecryption,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              final newValue = controller.text.trim();
              if (fieldType == 'name') {
                reportState.updateQuestionLocalization(
                  questionIndex,
                  lang,
                  newValue,
                  questionLoc?.description,
                  questionLoc?.example,
                );
              } else if (fieldType == 'description') {
                reportState.updateQuestionLocalization(
                  questionIndex,
                  lang,
                  questionLoc?.name,
                  newValue,
                  questionLoc?.example,
                );
              }
              onSaved?.call();
              Navigator.pop(ctx);
            },
            child: Text(loc.save),
          ),
        ],
      );
    },
  );
}
