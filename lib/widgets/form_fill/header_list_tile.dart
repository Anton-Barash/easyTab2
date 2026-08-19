import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:flutter/material.dart';

/// Карточка №0 (шапка отчёта).
///
/// Единая для обоих режимов отображения (список и карточки), за основу
/// взят вид из списка вопросов. Клик по фото открывает просмотрщик,
/// клик по карандашу — панель редактирования.
class HeaderListTile extends StatelessWidget {
  final Report report;
  final ReportState reportState;

  /// Переход к шапке в боковой панели (тап по номеру «0»).
  final VoidCallback onNavigateToHeader;

  /// Открытие панели редактирования шапки (иконка карандаша).
  final VoidCallback onEditHeader;

  /// Добавление фото, когда изображения ещё нет (тап по заглушке).
  final VoidCallback onPhotoAreaTap;

  /// Просмотр существующего фото (тап по изображению).
  final VoidCallback onViewPhoto;

  const HeaderListTile({
    super.key,
    required this.report,
    required this.reportState,
    required this.onNavigateToHeader,
    required this.onEditHeader,
    required this.onPhotoAreaTap,
    required this.onViewPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final headerImagePath = report.headerImagePath;
    final hasImage = headerImagePath != null && headerImagePath.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(width: 2, color: AppColors.border),
          bottom: BorderSide(width: 2, color: AppColors.border),
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
                  onTap: onNavigateToHeader,
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
                Expanded(
                  child: Text(
                    loc.headerInfo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEditHeader,
                  icon: const Icon(
                    Icons.edit,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  tooltip: loc.editHeader,
                ),
              ],
            ),
          ),
          if (reportState.isUploadingHeader)
            Container(
              width: double.infinity,
              height: 150,
              color: AppColors.grey100,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.border),
              ),
            )
          else if (hasImage)
            GestureDetector(
              onTap: onViewPhoto,
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
              ),
            )
          else
            GestureDetector(
              onTap: onPhotoAreaTap,
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${report.productType} | ${report.factory} | ${report.model}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (report.dateTimestamp != null)
                  Text(
                    DateTime.fromMillisecondsSinceEpoch(
                      report.dateTimestamp!,
                    ).toLocal().toString().substring(0, 10),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
