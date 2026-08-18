import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/widgets/form_fill/picker_item.dart';
import 'package:easy_tab/widgets/form_fill/section_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Виджет выбора/замены фото шапки отчёта (в едином стиле дизайн-системы).
///
/// Стиль: секционный блок с закруглённой рамкой Outline (8px),
/// превью 180px с опцией замены/удаления, кнопки в стиле других
/// модалок (AppColors.border, скругление 8px).
class HeaderPhotoPicker extends StatelessWidget {
  final bool hasImage;
  final String? imagePath;
  final Uint8List? imageBytes;
  final AppLocalizations loc;
  final ValueChanged<String?> onImagePathChanged;

  /// Callback для web — возвращает байты выбранного файла.
  /// Если null, используется только imagePath (native).
  final ValueChanged<Uint8List?>? onImageBytesChanged;

  const HeaderPhotoPicker({
    super.key,
    required this.hasImage,
    required this.imagePath,
    this.imageBytes,
    required this.loc,
    required this.onImagePathChanged,
    this.onImageBytesChanged,
  });

  Future<void> _pickImage(BuildContext context) async {
    final action = await _showSourceDialog(context);
    if (action == null) return;

    final picker = ImagePicker();
    XFile? image;

    if (action == 'camera') {
      image = await picker.pickImage(source: ImageSource.camera);
    } else if (action == 'gallery') {
      image = await picker.pickImage(source: ImageSource.gallery);
    }

    if (image == null) return;

    if (kIsWeb && onImageBytesChanged != null) {
      final bytes = await image.readAsBytes();
      onImageBytesChanged!(bytes);
    } else {
      onImagePathChanged(image.path);
    }
  }

  Future<String?> _showSourceDialog(BuildContext context) async {
    return showDialog<String>(
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.photo,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
            fontSize: 13,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greyBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.grey200, width: 1.5),
          ),
          child: hasImage && (imagePath != null || imageBytes != null)
              ? Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: imageBytes != null
                                    ? MemoryImage(imageBytes!)
                                    : fileImageProvider(imagePath!),
                                fit: BoxFit.cover,
                              ),
                            ),
                            height: 180,
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Material(
                              color: Colors.transparent,
                              child: Ink(
                                decoration: const ShapeDecoration(
                                  color: Colors.black54,
                                  shape: CircleBorder(),
                                ),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    onImagePathChanged(null);
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => onImagePathChanged(null),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(
                                color: AppColors.greyBorder,
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(loc.deletePhoto),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textDark,
                              side: const BorderSide(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(loc.changePhoto),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pickImage(context),
                    child: Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.greyBorder,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.grey100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 28,
                              color: AppColors.border,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            loc.addPhoto,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc.photoFromGallery,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
