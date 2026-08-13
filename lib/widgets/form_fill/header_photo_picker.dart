import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/file_image.dart';
import 'package:easy_tab/widgets/form_fill/picker_item.dart';
import 'package:easy_tab/widgets/form_fill/section_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Виджет выбора/замены фото шапки отчёта.
///
/// Используется внутри диалога редактирования шапки.
/// Поддерживает камеру и галерею (как обычные карточки медиа).
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
            fontWeight: FontWeight.w500,
            color: AppColors.grey800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        if (hasImage && (imagePath != null || imageBytes != null)) ...[
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  image: DecorationImage(
                    image: imageBytes != null
                        ? MemoryImage(imageBytes!)
                        : fileImageProvider(imagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => onImagePathChanged(null),
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
              onPressed: () => _pickImage(context),
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
            onTap: () => _pickImage(context),
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
}
