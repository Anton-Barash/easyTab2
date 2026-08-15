import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/widgets/form_fill/picker_item.dart';
import 'package:easy_tab/widgets/form_fill/section_title.dart';
import 'package:flutter/foundation.dart';
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

  Future<void> _pickHeaderImage(BuildContext context) async {
    // Снимаем фокус с текстовых полей, чтобы после добавления фото
    // список не прокручивался к полю с курсором.
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

    if (action == null) return;

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
        const SnackBar(content: Text('Неверный формат файла')),
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
        const SnackBar(content: Text('Файл слишком большой (макс. 10MB)')),
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
        const SnackBar(content: Text('Фото добавлено')),
      );
    } catch (e) {
      debugPrint('Header photo error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
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
                onTap: () => _pickHeaderImage(context),
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
                onTap: () => _pickHeaderImage(context),
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
