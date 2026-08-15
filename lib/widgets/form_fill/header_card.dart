import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart';
import 'package:easy_tab/widgets/form_fill/info_row.dart';
import 'package:flutter/material.dart';

/// Полная карточка шапки отчёта (card view).
class HeaderCard extends StatelessWidget {
  final Report report;
  final ReportState reportState;
  final VoidCallback onOpenSidePanel;
  final VoidCallback onNavigateToHeader;
  final VoidCallback onEditHeader;

  /// Вызывается при нажатии на область фото (добавление/замена фото).
  /// Если null — область фото не кликабельна.
  final VoidCallback? onPhotoAreaTap;

  const HeaderCard({
    super.key,
    required this.report,
    required this.reportState,
    required this.onOpenSidePanel,
    required this.onNavigateToHeader,
    required this.onEditHeader,
    this.onPhotoAreaTap,
  });

  @override
  Widget build(BuildContext context) {
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
            ? const Border(
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
              border: const Border(
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
                  onTap: onNavigateToHeader,
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
                  onPressed: onOpenSidePanel,
                ),
              ],
            ),
          ),
          if (reportState.isUploadingHeader)
            Container(
              width: double.infinity,
              height: 250,
              color: AppColors.grey100,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.border),
              ),
            )
          else if (hasImage)
            GestureDetector(
              onTap: onPhotoAreaTap,
              child: Container(
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
              ),
            )
          else
            GestureDetector(
              onTap: onPhotoAreaTap,
              child: Container(
                width: double.infinity,
                height: 150,
                color: AppColors.surface,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_a_photo,
                        size: 48,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loc.addPhoto,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(label: loc.productType, value: report.productType),
                const SizedBox(height: 12),
                InfoRow(label: loc.factory, value: report.factory),
                const SizedBox(height: 12),
                InfoRow(label: loc.model, value: report.model),
                const SizedBox(height: 12),
                if (report.dateTimestamp != null)
                  InfoRow(
                    label: loc.date,
                    value: DateTime.fromMillisecondsSinceEpoch(
                      report.dateTimestamp!,
                    ).toLocal().toString().substring(0, 10),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onEditHeader,
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
}
