import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/widgets/form_fill/header_field.dart';
import 'package:easy_tab/widgets/form_fill/header_photo_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Показывает модальное bottom-sheet окно редактирования шапки отчёта.
///
/// Извлечён из form_fill_screen в отдельный файл для улучшения
/// структуры и поддерживаемости кода. Сохраняет все возможности:
/// редактирование полей (productType, factory, model),
/// добавление/замена/удаление фото, валидацию и сохранение отчёта.
Future<void> showEditHeaderDialog({
  required BuildContext context,
  required ReportState reportState,
}) async {
  final report = reportState.currentReport;
  if (report == null) return;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    isDismissible: true,
    builder: (ctx) => _EditHeaderBottomSheet(
      reportState: reportState,
      report: report,
    ),
  );
}

// ======================= Внутренний виджет =======================

class _EditHeaderBottomSheet extends StatefulWidget {
  final ReportState reportState;
  final Report report;

  const _EditHeaderBottomSheet({
    required this.reportState,
    required this.report,
  });

  @override
  State<_EditHeaderBottomSheet> createState() =>
      _EditHeaderBottomSheetState();
}

class _EditHeaderBottomSheetState extends State<_EditHeaderBottomSheet> {
  late final TextEditingController _productTypeController;
  late final TextEditingController _factoryController;
  late final TextEditingController _modelController;

  late final bool _hadHeaderImageBefore;

  String? _tempPhotoPath;
  Uint8List? _tempPhotoBytes;
  String? _tempPhotoFileName;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final report = widget.report;
    final reportState = widget.reportState;

    _productTypeController = TextEditingController(text: report.productType);
    _factoryController = TextEditingController(text: report.factory);
    _modelController = TextEditingController(text: report.model);

    _hadHeaderImageBefore =
        report.headerImagePath != null && report.headerImagePath!.isNotEmpty;

    if (_hadHeaderImageBefore &&
        !kIsWeb &&
        reportState.currentReportPath != null) {
      final sourceFile = File(
        '${reportState.currentReportPath}/${report.headerImagePath}',
      );
      if (sourceFile.existsSync()) {
        final tempDir = Directory.systemTemp;
        final tempFile = File(
          '${tempDir.path}/header_edit_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        sourceFile.copySync(tempFile.path);
        _tempPhotoPath = tempFile.path;
      }
    }
  }

  @override
  void dispose() {
    _productTypeController.dispose();
    _factoryController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _hasImage => _tempPhotoPath != null || _tempPhotoBytes != null;

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      widget.reportState.updateHeaderInfo(
        productType: _productTypeController.text.trim(),
        factory: _factoryController.text.trim(),
        model: _modelController.text.trim(),
      );
      try {
        if (kIsWeb) {
          if (_tempPhotoBytes != null) {
            await widget.reportState.addHeaderImageFromBytes(
              _tempPhotoBytes!,
              _tempPhotoFileName ?? 'header.jpg',
            );
          } else if (_hadHeaderImageBefore) {
            await widget.reportState.removeHeaderImage();
          }
        } else {
          if (_tempPhotoPath != null) {
            await widget.reportState.addHeaderImage(File(_tempPhotoPath!));
          } else if (_hadHeaderImageBefore) {
            await widget.reportState.removeHeaderImage();
          }
        }
      } catch (e) {
        debugPrint('Header image error: $e');
      }
      await widget.reportState.saveReport();
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===== Drag handle =====
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Header: title + close button =====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.editHeader,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(
                  color: AppColors.grey200,
                  thickness: 1,
                  height: 1,
                ),
              ),

              // ===== Scrollable content =====
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // === Секция: Основная информация ===
                      _SectionLabel(label: loc.headerInfo),
                      _GroupBox(
                        child: Column(
                          children: [
                            HeaderField(
                              label: loc.productType,
                              controller: _productTypeController,
                            ),
                            const SizedBox(height: 16),
                            HeaderField(
                              label: loc.factory,
                              controller: _factoryController,
                            ),
                            const SizedBox(height: 16),
                            HeaderField(
                              label: loc.model,
                              controller: _modelController,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // === Секция: Фото ===
                      _SectionLabel(label: loc.photo),
                      _GroupBox(
                        child: HeaderPhotoPicker(
                          hasImage: _hasImage,
                          imagePath: kIsWeb ? null : _tempPhotoPath,
                          imageBytes: kIsWeb ? _tempPhotoBytes : null,
                          loc: loc,
                          onImagePathChanged: (path) {
                            setState(() {
                              _tempPhotoPath = path;
                              _tempPhotoBytes = null;
                              _tempPhotoFileName = null;
                            });
                          },
                          onImageBytesChanged: (bytes) {
                            setState(() {
                              _tempPhotoBytes = bytes;
                              _tempPhotoPath = null;
                              _tempPhotoFileName =
                                  'header_'
                                  '${DateTime.now().millisecondsSinceEpoch}.jpg';
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // ===== Action buttons =====
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isSaving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(
                            color: AppColors.greyBorder,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: Text(
                          loc.cancel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.grey300,
                          disabledForegroundColor: AppColors.grey500,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                loc.save,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= Декоративные компоненты =======================

/// Заголовок секции в форме редактирования шапки.
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.border,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Контейнер с рамкой и тенью для группировки полей одной секции.
class _GroupBox extends StatelessWidget {
  final Widget child;

  const _GroupBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greyBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200, width: 1.5),
      ),
      child: child,
    );
  }
}
