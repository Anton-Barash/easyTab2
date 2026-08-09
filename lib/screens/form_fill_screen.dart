import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/services/mime_utils.dart';
import 'package:easy_tab/widgets/dotted_pattern_painter.dart';
import 'package:easy_tab/widgets/media_item_widget.dart';
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
import 'full_media_viewer_screen.dart';

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
  final PageController _pageController = PageController();
  final ItemScrollController _listItemScrollController = ItemScrollController();
  final ItemScrollController _sidePanelItemScrollController = ItemScrollController();
  int _currentPage = -1;
  final Map<int, bool> _needsWorkMap = {};
  Set<int> _blockedQuestionIndices = {};
  bool _isUpdatingControllers = false;
  final Map<String, Map<int, bool>> _enabledAnswers = {};
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  String _processingMessage = '';

  bool _checkedSyncAfterLoad = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedReportIfNeeded();
      _checkSyncAfterLoad();
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.shareLinkSaveFirst)),
        );
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
                SnackBar(
                  content: Text(result.error ?? loc.shareLinkError),
                ),
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
                              const Icon(Icons.check_circle,
                                  color: AppColors.grey700, size: 28),
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
                                      ScaffoldMessenger.of(ctx)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(loc.shareLinkCopied)),
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
                              const Icon(Icons.share,
                                  color: AppColors.grey700, size: 24),
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
                                            () => selectedDays = days),
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
                              _buildPermissionOption(
                                ctx: ctx,
                                label: loc.sharePermissionEdit,
                                icon: Icons.edit,
                                value: 'edit',
                                groupValue: selectedPermission,
                                onTap: isCreating
                                    ? null
                                    : () => setDialogState(
                                        () => selectedPermission = 'edit'),
                              ),
                              const SizedBox(width: 8),
                              _buildPermissionOption(
                                ctx: ctx,
                                label: loc.sharePermissionView,
                                icon: Icons.visibility,
                                value: 'view',
                                groupValue: selectedPermission,
                                onTap: isCreating
                                    ? null
                                    : () => setDialogState(
                                        () => selectedPermission = 'view'),
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

  Widget _buildPermissionOption({
    required BuildContext ctx,
    required String label,
    required IconData icon,
    required String value,
    required String groupValue,
    required VoidCallback? onTap,
  }) {
    final isSelected = value == groupValue;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.grey700 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.grey700 : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.loginRequired)),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.uploadError)),
          );
        }
        return;
      }

      // 3. Собираем файлы для загрузки с диска.
      final filesToUpload = <Map<String, String>>[];

      final reportPath = reportState.currentReportPath;
      if (reportPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.uploadError)),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.noFilesToUpload)),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.uploadError}: $e')),
        );
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
      builder: (ctx) => _SyncDialog(
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
      builder: (ctx) => _SyncMenuDialog(
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

  Future<void> viewHtmlWithChooser(String htmlContent) async {
    final reportState = context.read<ReportState>();

    if (reportState.currentReportPath == null) {
      await reportState.saveReport();
    }

    final folderPath = reportState.currentReportPath!;
    final file = File('$folderPath/easy_report.html');
    await file.writeAsString(htmlContent);

    final result = await OpenFile.open(file.path);

    if (result.type == ResultType.noAppToOpen) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.noAppToOpenHtml)));
      }
    }
  }

  /// Просмотр HTML на web: открывает новую вкладку Flutter.
  ///
  /// Архитектура:
  ///   1. Flutter открывает новую вкладку: /#/view-report?pid=abc123&token=xxx
  ///   2. Новая вкладка — это Flutter-экран ViewReportHtmlScreen
  ///   3. Экран делает API-запрос: GET /reports/abc123/html
  ///   4. Сервер читает JSON из БД, генерирует HTML, возвращает {success, html}
  ///   5. Экран отображает HTML в iframe srcdoc
  ///   6. Фото в HTML используют presigned URL из KS3 — грузятся с сервера
  ///
  /// URL новой вкладки строится относительно текущего origin, поэтому работает
  /// на любом порту/домене, где развёрнут фронтенд.
  ///
  /// Если пользователь не залогинен или отчёт не сохранён — fallback на blob.
  Future<void> _viewHtmlOnWeb(String htmlContent) async {
    final authProvider = context.read<AuthProvider>();
    final reportState = context.read<ReportState>();

    // Если отчёт ещё не сохранён на сервере — нет publicId, fallback на blob
    if (reportState.serverPublicId == null) {
      openHtmlInBrowser(htmlContent);
      return;
    }

    final origin = Uri.base.origin;

    // Залогиненный пользователь: открываем Flutter-маршрут /view-report.
    // Cookie auth_token уже установлен при логине, поэтому токен не нужен в URL.
    if (authProvider.isLoggedIn) {
      final viewUrl = '$origin/#/view-report?pid=${reportState.serverPublicId}';
      openHtmlInBrowserUrl(viewUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HTML отчёт открыт в новой вкладке')),
        );
      }
      return;
    }

    // Анонимный пользователь по share-ссылке: открываем тот же серверный
    // endpoint, что и на welcome-странице — /reports/shares/:token/html.
    // Сервер генерирует HTML с proxy URL медиа, содержащими share_token.
    final shareToken = reportState.shareToken;
    if (shareToken != null && shareToken.isNotEmpty) {
      final anonymousId = await AnonymousIdService.getId();
      final uri = Uri.http(ApiService.baseUrl, '/reports/shares/$shareToken/html', {
        'anonymous_id': anonymousId,
      });
      openHtmlInBrowserUrl(uri.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HTML отчёт открыт в новой вкладке')),
        );
      }
      return;
    }

    // Нет ни логина, ни share-токена — fallback на blob (медиа не будут видны,
    // т.к. относительные пути photos/... не резолвятся для blob URL).
    openHtmlInBrowser(htmlContent);
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
              // Сохраняем позицию курсора перед обновлением
              final selection = controller.selection;
              controller.value = TextEditingValue(
                text: newText,
                selection: selection.baseOffset > newText.length
                    ? TextSelection.collapsed(offset: newText.length)
                    : selection,
              );
              _isUpdatingControllers = false;
            }
          }
        }

        final hasOtherAnswers = reportState.hasAnswersInOtherLanguages(i, j);
        _enabledAnswers[qid]![j] = !hasOtherAnswers;
      }
    }

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
                    final htmlContent = reportState.generateHtmlContent();
                    if (kIsWeb) {
                      // На web — открываем серверный просмотр /view-report
                      await _viewHtmlOnWeb(htmlContent);
                    } else {
                      // На мобильных/десктопах открываем через системный диалог
                      await viewHtmlWithChooser(htmlContent);
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(loc.saveZipWeb)),
                        );
                      }
                      return;
                    }
                    // Show hint on mobile devices - only hint, no action
                    if (Platform.isAndroid || Platform.isIOS) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
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
              Positioned.fill(
                child: Container(
                  color: AppColors.background,
                  child: CustomPaint(painter: DottedPatternPainter()),
                ),
              ),
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
                                decoration: BoxDecoration(
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
                                        style: TextStyle(
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
                              decoration: BoxDecoration(
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
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _hideAnsweredQuestions = !_hideAnsweredQuestions;
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: Checkbox(
                                              value: _hideAnsweredQuestions,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              fillColor: WidgetStateProperty.resolveWith((states) {
                                                if (states.contains(WidgetState.selected)) {
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
                                      itemScrollController: _sidePanelItemScrollController,
                                      itemCount: _getFilteredQuestionCount(report) + 1,
                                      itemBuilder: (ctx, index) {
                                        if (index == _getFilteredQuestionCount(report)) {
                                          return const SizedBox(height: 80);
                                        }
                                        if (index == 0) {
                                          return _buildHeaderCard0SidePanel(
                                            context,
                                            report,
                                            reportState,
                                          );
                                        }
                                        final i = _getFilteredQuestionIndex(index - 1, report);
                                        if (i == -1) return const SizedBox.shrink();
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
                                                  final page = _getPageForQuestion(i, report);
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
                    child: Container(
                      color: const Color(0x80000000), // black 50% opacity
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
                                _hideAnsweredQuestions = !_hideAnsweredQuestions;
                              });
                            },
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _hideAnsweredQuestions,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    fillColor: WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(WidgetState.selected)) {
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
                            itemScrollController: _sidePanelItemScrollController,
                            itemCount: _getFilteredQuestionCount(report) + 1,
                            itemBuilder: (ctx, index) {
                              if (index == _getFilteredQuestionCount(report)) {
                                return const SizedBox(height: 80);
                              }
                              if (index == 0) {
                                return _buildHeaderCard0SidePanel(
                                  context,
                                  report,
                                  reportState,
                                );
                              }
                              final i = _getFilteredQuestionIndex(index - 1, report);
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
                                        final page = _getPageForQuestion(i, report);
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
                                                    color: AppColors.textPrimary,
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
                                                    color: AppColors.warningAccent,
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
                child: _buildHeaderCard0ListItem(
                  ctx,
                  report,
                  reportState,
                  isMobile,
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
                      child: _buildHeaderCard0(context, report, reportState),
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

  Widget _buildHeaderCard0(
    BuildContext context,
    Report report,
    ReportState reportState,
  ) {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final width = !isMobile ? 600.0 : double.infinity;

    final headerImagePath = report.headerImagePath;
    final hasImage = headerImagePath != null && headerImagePath.isNotEmpty;

    return Container(
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? Border(
                top: BorderSide(width: 2, color: AppColors.border),
                bottom: BorderSide(width: 2, color: AppColors.border),
              )
            : Border.all(width: 2, color: AppColors.border),
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              border: Border(
                bottom: BorderSide(width: 1.5, color: AppColors.grey200),
              ),
              borderRadius: isMobile
                  ? BorderRadius.zero
                  : const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSidePanelCollapsed = false;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollSidePanelToQuestion(-1, report);
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text(
                        '0',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.headerInfo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    setState(() {
                      _isSidePanelCollapsed = false;
                    });
                  },
                ),
              ],
            ),
          ),
          if (hasImage)
            Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: fileImageProvider(
                    '${reportState.currentReportPath}/$headerImagePath',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 150,
              color: AppColors.surface,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.image, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 8),
                    Text(
                      loc.noPhoto,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(loc.productType, report.productType),
                const SizedBox(height: 12),
                _buildInfoRow(loc.factory, report.factory),
                const SizedBox(height: 12),
                _buildInfoRow(loc.model, report.model),
                const SizedBox(height: 12),
                if (report.dateTimestamp != null)
                  _buildInfoRow(
                    loc.date,
                    DateTime.fromMillisecondsSinceEpoch(
                      report.dateTimestamp!,
                    ).toLocal().toString().substring(0, 10),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showEditHeaderDialog(context, reportState),
                  icon: const Icon(Icons.edit),
                  label: Text(loc.editHeader),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
          final hasImage = tempPhotoPath != null;
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
                      _buildHeaderField(loc.productType, productTypeController),
                      const SizedBox(height: 12),
                      _buildHeaderField(loc.factory, factoryController),
                      const SizedBox(height: 12),
                      _buildHeaderField(loc.model, modelController),
                      const SizedBox(height: 16),
                      _buildPhotoSection(
                        context,
                        hasImage,
                        tempPhotoPath,
                        loc,
                        setDialogState,
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
                              if (tempPhotoPath != null) {
                                await reportState.addHeaderImage(
                                  File(tempPhotoPath),
                                );
                              } else if (hadHeaderImageBefore) {
                                await reportState.removeHeaderImage();
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

  Widget _buildHeaderField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.grey800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.greyBorder),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.greyBorder),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            isDense: true,
          ),
          style: const TextStyle(color: AppColors.textDark, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildPhotoSection(
    BuildContext context,
    bool hasImage,
    String? tempPhotoPath,
    AppLocalizations loc,
    void Function(void Function()) setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.photo,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.grey800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        if (hasImage) ...[
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  image: DecorationImage(
                    image: fileImageProvider(tempPhotoPath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () {
                    tempPhotoPath = null;
                    setDialogState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.grey900,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  tempPhotoPath = image.path;
                  setDialogState(() {});
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey800,
                side: const BorderSide(color: AppColors.greyBorder),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(loc.changePhoto),
            ),
          ),
        ] else ...[
          InkWell(
            onTap: () async {
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (image != null) {
                tempPhotoPath = image.path;
                setDialogState(() {});
              }
            },
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.greyBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.greyBorder, width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo,
                    size: 32,
                    color: AppColors.greyDisabled,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.addPhoto,
                    style: const TextStyle(
                      color: AppColors.textLight,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeaderCard0ListItem(
    BuildContext context,
    Report report,
    ReportState reportState,
    bool isMobile,
  ) {
    final loc = AppLocalizations.of(context)!;
    final headerImagePath = report.headerImagePath;
    final hasImage = headerImagePath != null && headerImagePath.isNotEmpty;

    return Material(
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(width: 2, color: AppColors.border),
            top: BorderSide(width: 2, color: AppColors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
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
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: Text(
                          '0',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    loc.headerInfo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (hasImage)
              GestureDetector(
                onTap: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (image != null) {
                    await reportState.addHeaderImage(File(image.path));
                    setState(() {});
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: fileImageProvider(
                        '${reportState.currentReportPath}/$headerImagePath',
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (image != null) {
                    await reportState.addHeaderImage(File(image.path));
                    setState(() {});
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.greyLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.greyBorder),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_a_photo,
                        size: 28,
                        color: AppColors.greyDisabled,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc.addPhoto,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildEditableRow(loc.productType, report.productType, (val) {
                    reportState.updateHeaderInfo(productType: val);
                    if (!_hasUnsavedChanges) {
                      setState(() => _hasUnsavedChanges = true);
                    }
                  }),
                  const SizedBox(height: 6),
                  _buildEditableRow(loc.factory, report.factory, (val) {
                    reportState.updateHeaderInfo(factory: val);
                    if (!_hasUnsavedChanges) {
                      setState(() => _hasUnsavedChanges = true);
                    }
                  }),
                  const SizedBox(height: 6),
                  _buildEditableRow(loc.model, report.model, (val) {
                    reportState.updateHeaderInfo(model: val);
                    if (!_hasUnsavedChanges) {
                      setState(() => _hasUnsavedChanges = true);
                    }
                  }),
                  if (report.dateTimestamp != null) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      loc.date,
                      DateTime.fromMillisecondsSinceEpoch(
                        report.dateTimestamp!,
                      ).toLocal().toString().substring(0, 10),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableRow(
    String label,
    String value,
    Function(String) onChanged,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.greyBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.greyBorder),
            ),
            child: TextFormField(
              initialValue: value,
              style: const TextStyle(fontSize: 13, color: AppColors.textDark),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard0SidePanel(
    BuildContext context,
    Report report,
    ReportState reportState,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            setState(() {
              _currentPage = -1;
              _isSidePanelCollapsed = true;
            });
            if (_viewMode == ViewMode.card) {
              _pageController.animateToPage(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.ease,
              );
            } else {
              if (_listItemScrollController.isAttached) {
                _listItemScrollController.scrollTo(
                  index: 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                width: 1.5,
                color: AppColors.grey200,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      '0',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${report.productType} | ${report.factory} | ${report.model}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (report.dateTimestamp != null)
                        Text(
                          DateTime.fromMillisecondsSinceEpoch(
                            report.dateTimestamp!,
                          ).toLocal().toString().substring(0, 10),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    int index,
    ReportState reportState,
    bool isCardView,
  ) {
    final loc = AppLocalizations.of(context)!;
    final report = reportState.currentReport!;
    final q = report.questions[index];
    final lang = report.currentLanguage;
    final questionLoc = q.getLocalization(lang);
    final answers = report.getAnswersForQuestion(index, lang);

    final isMobile = MediaQuery.of(context).size.width <= 800;

    final width = isCardView && !isMobile ? 600.0 : double.infinity;

    return Container(
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? Border(
                top: BorderSide(width: 2, color: AppColors.border),
                bottom: BorderSide(width: 2, color: AppColors.border),
              )
            : Border.all(width: 2, color: AppColors.border),
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: isMobile
                ? const EdgeInsets.fromLTRB(0, 4, 4, 0)
                : const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              border: Border(
                bottom: BorderSide(width: 1.5, color: AppColors.grey200),
              ),
              borderRadius: isMobile
                  ? BorderRadius.zero
                  : const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile)
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isSidePanelCollapsed = false;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollSidePanelToQuestion(index, report);
                          });
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: () => _showEditQuestionDialog(
                            context,
                            index,
                            reportState,
                            'name',
                            _markAsUnsaved,
                          ),
                          child: Text(
                            questionLoc?.name ??
                                q.getDisplayName(lang) ??
                                loc.noName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ),
                      if (questionLoc?.description?.isNotEmpty ?? false)
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          color: AppColors.textLight,
                          onPressed: () => _showEditQuestionDialog(
                            context,
                            index,
                            reportState,
                            'description',
                            _markAsUnsaved,
                          ),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        color: Colors.white,
                        elevation: 4,
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'add_above',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 18),
                                const SizedBox(width: 8),
                                Text(loc.newQuestionAbove),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'add_below',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 18),
                                const SizedBox(width: 8),
                                Text(loc.newQuestionBelow),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: AppColors.errorLight,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  loc.deleteThisQuestion,
                                  style: const TextStyle(
                                    color: AppColors.errorLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'add_above') {
                            _resetControllers();
                            reportState.addQuestion(index - 1);
                            if (index > 0) {
                              _pageController.animateToPage(
                                index - 1,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.ease,
                              );
                            }
                          } else if (value == 'add_below') {
                            _resetControllers();
                            reportState.addQuestion(index);
                            _pageController.animateToPage(
                              index + 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease,
                            );
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(loc.deleteQuestionTitle),
                                content: Text(loc.deleteQuestionConfirm),
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
                            if (confirm == true &&
                                report.questions.length > 1) {
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
                            }
                          }
                        },
                      ),
                    ],
                  ),
                if (!isMobile)
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: GestureDetector(
                                    onTap: () => _showEditQuestionDialog(
                                      context,
                                      index,
                                      reportState,
                                      'name',
                                      _markAsUnsaved,
                                    ),
                                    child: Text(
                                      questionLoc?.name ??
                                          q.getDisplayName(lang) ??
                                          loc.noName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDark,
                                      ),
                                      softWrap: true,
                                    ),
                                  ),
                                ),
                                if (questionLoc?.description?.isNotEmpty ??
                                    false)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.help_outline,
                                      size: 20,
                                    ),
                                    color: AppColors.textLight,
                                    onPressed: () => _showEditQuestionDialog(
                                      context,
                                      index,
                                      reportState,
                                      'description',
                                      _markAsUnsaved,
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  color: Colors.white,
                                  elevation: 4,
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'add_above',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.add, size: 18),
                                          const SizedBox(width: 8),
                                          Text(loc.newQuestionAbove),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'add_below',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.add, size: 18),
                                          const SizedBox(width: 8),
                                          Text(loc.newQuestionBelow),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: AppColors.errorLight,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            loc.deleteThisQuestion,
                                            style: const TextStyle(
                                              color: AppColors.errorLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'add_above') {
                                      _resetControllers();
                                      reportState.addQuestion(index - 1);
                                      if (index > 0) {
                                        _pageController.animateToPage(
                                          index - 1,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.ease,
                                        );
                                      }
                                    } else if (value == 'add_below') {
                                      _resetControllers();
                                      reportState.addQuestion(index);
                                      _pageController.animateToPage(
                                        index + 1,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.ease,
                                      );
                                    } else if (value == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(loc.deleteQuestionTitle),
                                          content: Text(
                                            loc.deleteQuestionConfirm,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(loc.cancel),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(loc.delete),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true &&
                                          report.questions.length > 1) {
                                        _resetControllers();
                                        await reportState.removeQuestion(index);
                                        if (_currentPage >=
                                            report.questions.length) {
                                          _currentPage =
                                              report.questions.isNotEmpty
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
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (questionLoc?.example?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${questionLoc?.example}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: isMobile
                ? const EdgeInsets.all(8)
                : const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int j = 0; j < answers.length; j++)
                  _buildAnswerBlock(
                    context,
                    index,
                    j,
                    reportState,
                    index.toString(),
                    answers[j],
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      color: AppColors.textPrimary,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.grey100,
                        side: const BorderSide(
                          color: AppColors.grey200,
                          width: 1.5,
                        ),
                      ),
                      onPressed: () {
                        reportState.addAnswer(index);
                        _markAsUnsaved();
                      },
                      tooltip: loc.addAnswerTooltip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerBlock(
    BuildContext context,
    int i,
    int j,
    ReportState reportState,
    String qid,
    Map<String, dynamic> answer,
  ) {
    final loc = AppLocalizations.of(context)!;
    final attention = answer['attention'] == true;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    final report = reportState.currentReport;
    String? exampleText;
    if (report != null && i < report.questions.length) {
      final question = report.questions[i];
      final questionLoc = question.getLocalization(report.currentLanguage);
      exampleText = questionLoc?.example;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 6 : 12),
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: attention ? AppColors.attentionBackground : AppColors.greyBackground,
        border: Border.all(
          width: 1.5,
          color: attention ? AppColors.attentionBorder : AppColors.grey200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exampleText?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                exampleText!,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: AppColors.textLight,
                  fontStyle: FontStyle.italic,
                ),
                softWrap: true,
              ),
            ),
          TextField(
            controller: _getSafeController(qid, j),
            maxLines: null,
            enabled: _enabledAnswers[qid]?[j] ?? true,
            style: TextStyle(
              color: (_enabledAnswers[qid]?[j] ?? true)
                  ? AppColors.textDark
                  : AppColors.textLight,
            ),
            decoration: InputDecoration(
              hintText: loc.enterAnswer,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if ((answer['media'] as List?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildMediaGrid(
                context,
                answer['media'] as List,
                i,
                j,
                reportState,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  color: AppColors.textPrimary,
                  onPressed: () => _showMediaPicker(context, i, j, false),
                ),
                Tooltip(
                  message: loc.needsWorkTooltip,
                  child: IconButton(
                    icon: const Icon(Icons.edit_note),
                    color: _needsWorkMap[i] == true
                        ? AppColors.warning
                        : AppColors.greyDisabled,
                    onPressed: () {
                      final newValue = !(_needsWorkMap[i] ?? false);
                      setState(() {
                        _needsWorkMap[i] = newValue;
                      });
                      reportState.updateAnswerNeedsWork(i, j, newValue);
                      _markAsUnsaved();
                    },
                  ),
                ),
                Tooltip(
                  message: attention
                      ? loc.removeAttentionMark
                      : loc.addAttentionMark,
                  child: IconButton(
                    icon: Icon(
                      Icons.warning_amber,
                      color: attention
                          ? AppColors.warning
                          : AppColors.greyBorder,
                    ),
                    onPressed: () {
                      reportState.updateAnswerAttention(i, j, !attention);
                      _markAsUnsaved();
                    },
                  ),
                ),
                if (reportState.hasAnswersInOtherLanguages(i, j))
                  IconButton(
                    icon: const Icon(Icons.lock, color: AppColors.textLight),
                    onPressed: () =>
                        _showLockDialog(context, i, j, qid, reportState),
                    tooltip: loc.lockAnswerTooltip,
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.errorLight),
                  onPressed:
                      (reportState
                                  .currentReport
                                  ?.translations[qid]
                                  ?.values
                                  .firstOrNull
                                  ?.length ??
                              1) >
                          1
                      ? () =>
                            _showDeleteAnswerDialog(context, i, j, reportState)
                      : null,
                  tooltip: loc.deleteAnswerTooltip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMediaPicker(
    BuildContext context,
    int questionIndex,
    int answerIndex,
    bool isAttention,
  ) async {
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
                _buildSectionTitle(loc.createSection),
                const SizedBox(height: 8),
                _buildPickerItem(
                  icon: Icons.camera_alt,
                  label: loc.takePhoto,
                  onTap: () => Navigator.pop(ctx, 'camera-photo'),
                ),
                const SizedBox(height: 8),
                _buildPickerItem(
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
                _buildSectionTitle(loc.selectSection),
                const SizedBox(height: 8),
                _buildPickerItem(
                  icon: Icons.photo_library,
                  label: loc.photoFromGallery,
                  onTap: () => Navigator.pop(ctx, 'gallery-photo'),
                ),
                const SizedBox(height: 8),
                _buildPickerItem(
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.border,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPickerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: AppColors.border),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.border,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(
    BuildContext context,
    List mediaList,
    int questionIndex,
    int answerIndex,
    ReportState reportState,
  ) {
    final List<Widget> items = [];
    const maxVisible = 8;
    final visibleCount = mediaList.length > maxVisible
        ? maxVisible
        : mediaList.length;

    for (int idx = 0; idx < visibleCount; idx++) {
      final media = mediaList[idx] as Map<String, dynamic>;
      final isLastExtra =
          idx == maxVisible - 1 && mediaList.length > maxVisible;

      if (isLastExtra) {
        // Показываем "+N"
        items.add(
          GestureDetector(
            onTap: () => _showFullMediaViewer(
              context,
              mediaList,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
            ),
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(width: 2, color: AppColors.grey200),
              ),
              child: Center(
                child: Text(
                  '+${mediaList.length - 7}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        // Обычный медиа‑элемент
        items.add(
          MediaItemWidget(
            media: media,
            reportPath: reportState.currentReportPath,
            onTap: () => _showFullMediaViewer(
              context,
              mediaList,
              initialIndex: idx,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
            ),
            onLongPress: () => _showFullMediaViewer(
              context,
              mediaList,
              initialIndex: idx,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
              startInSelectionMode: true,
            ),
            onDelete: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Удалить?'),
                  content: const Text('Файл будет удален без возможности восстановления.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await reportState.removeMedia(questionIndex, answerIndex, idx);
                await reportState.saveReport();
              }
            },
          ),
        );
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  void _showFullMediaViewer(
    BuildContext context,
    List mediaList, {
    int initialIndex = 0,
    int? questionIndex,
    int? answerIndex,
    ReportState? reportState,
    bool startInSelectionMode = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => FullMediaViewerScreen(
          mediaList: mediaList,
          initialIndex: initialIndex,
          reportPath: reportState?.currentReportPath,
          onDelete: (indices) async {
            if (questionIndex != null &&
                answerIndex != null &&
                reportState != null) {
              for (final index
                  in indices.toList()..sort((a, b) => b.compareTo(a))) {
                await reportState.removeMedia(
                  questionIndex,
                  answerIndex,
                  index,
                );
              }
              await reportState.saveReport();
            }
          },
          startInSelectionMode: startInSelectionMode,
        ),
      ),
    );
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
          autofocus: true,
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

class _SyncDialog extends StatefulWidget {
  final ReportState reportState;
  final String targetLang;
  final List<int> unsyncIndices;
  final VoidCallback onSyncApplied;
  final VoidCallback onSkipSync;

  const _SyncDialog({
    required this.reportState,
    required this.targetLang,
    required this.unsyncIndices,
    required this.onSyncApplied,
    required this.onSkipSync,
  });

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  final TextEditingController _jsonController = TextEditingController();

  String get _syncJson => widget.reportState.generateSyncJson();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final loc = AppLocalizations.of(context)!;
    try {
      await Clipboard.setData(ClipboardData(text: _syncJson));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.jsonCopiedToClipboard)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.copyError(e.toString()))));
      }
    }
  }

  Future<void> _saveToFile() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/sync_answers_${widget.targetLang}.json');
      await file.writeAsString(_syncJson);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.fileSaved(file.path))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.saveError(e.toString()))));
      }
    }
  }

  Future<void> _loadFromFile() async {
    final loc = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _jsonController.text = content;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.readError(e.toString()))));
      }
    }
  }

  void _applySync() {
    final loc = AppLocalizations.of(context)!;
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.pasteTranslatedJson)));
      return;
    }

    try {
      widget.reportState.applySyncAnswers(jsonText);
      Navigator.pop(context);
      widget.onSyncApplied();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.syncComplete)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.invalidJsonError(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    return AlertDialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
      contentPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.all(24),
      shape: isMobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Text(loc.syncAnswersTitle(widget.targetLang)),
      content: SizedBox(
        width: isMobile ? double.infinity : 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.useAnyAi,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.aiPromptExample,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.aiPromptExample2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loc.unsyncedQuestionsCount(widget.unsyncIndices.length),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: Text(loc.copyButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveToFile,
                      icon: const Icon(Icons.download),
                      label: Text(loc.downloadButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                loc.pasteTranslatedJson,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: loc.pasteJsonHere,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.border,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _loadFromFile,
                icon: const Icon(Icons.upload_file),
                label: Text(loc.loadFromFileButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onSkipSync();
          },
          child: Text(
            loc.cancel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _applySync,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border, width: 2),
          ),
          child: Text(loc.syncButton),
        ),
        if (isMobile) const SizedBox(height: 100),
      ],
    );
  }
}

class _SyncMenuDialog extends StatefulWidget {
  final ReportState reportState;
  final List<int> unsyncIndices;
  final VoidCallback onApplied;

  const _SyncMenuDialog({
    required this.reportState,
    required this.unsyncIndices,
    required this.onApplied,
  });

  @override
  State<_SyncMenuDialog> createState() => _SyncMenuDialogState();
}

class _SyncMenuDialogState extends State<_SyncMenuDialog> {
  final TextEditingController _jsonController = TextEditingController();

  String get _syncJson => widget.reportState.generateSyncJson();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: _syncJson));
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.jsonCopiedToClipboard)));
      }
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.copyError(e.toString()))));
      }
    }
  }

  Future<void> _saveToFile() async {
    try {
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/sync_answers.json');
      await file.writeAsString(_syncJson);

      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.fileSaved(file.path))));
      }
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.saveError(e.toString()))));
      }
    }
  }

  Future<void> _loadFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _jsonController.text = content;
      });
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.readError(e.toString()))));
      }
    }
  }

  void _applySync() {
    final loc = AppLocalizations.of(context)!;
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.pasteTranslatedJson)));
      return;
    }

    try {
      widget.reportState.applySyncAnswers(jsonText);
      Navigator.pop(context);
      widget.onApplied();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.syncComplete)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.invalidJsonError(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final unsyncCount = widget.reportState.getUnsyncQuestionIndices().length;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unsyncCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning),
            ),
            child: Text(
              loc.unsyncedQuestionsCount(unsyncCount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success),
            ),
            child: Text(
              loc.allAnswersSynced,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greyBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.greyBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.instructionsLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(loc.syncStep1),
              Text(loc.syncStep2),
              Text(loc.syncStep3),
              Text(loc.syncStep4),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          loc.aiPromptLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.greyBorder),
          ),
          child: Text(
            loc.aiPromptContent,
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy),
                label: Text(loc.copyJsonButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveToFile,
                icon: const Icon(Icons.download),
                label: Text(loc.downloadButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          loc.uploadTranslatedJsonLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _jsonController,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: loc.pasteJsonHere,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _loadFromFile,
          icon: const Icon(Icons.upload_file),
          label: Text(loc.loadFromFileButton),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.syncMenuTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: content,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        loc.close,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applySync,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: Text(loc.syncButton),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      return AlertDialog(
        title: Text(loc.syncMenuTitle),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(child: content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              loc.close,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: _applySync,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border, width: 2),
            ),
            child: Text(loc.syncButton),
          ),
        ],
      );
    }
  }
}
