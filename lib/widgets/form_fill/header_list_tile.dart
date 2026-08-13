import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Плитка шапки отчёта в списке вопросов (list view).
class HeaderListTile extends StatelessWidget {
  final Report report;
  final ReportState reportState;
  final bool isMobile;
  final VoidCallback onNavigateToHeader;

  const HeaderListTile({
    super.key,
    required this.report,
    required this.reportState,
    required this.isMobile,
    required this.onNavigateToHeader,
  });

  Future<void> _pickHeaderImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await reportState.addHeaderImage(File(image.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final headerImagePath = report.headerImagePath;
    final hasImage = headerImagePath != null && headerImagePath.isNotEmpty;

    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
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
                onTap: _pickHeaderImage,
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
                onTap: _pickHeaderImage,
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
      ),
    );
  }
}
