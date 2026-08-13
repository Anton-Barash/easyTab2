import 'package:easy_tab/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Элемент выпадающего меню выбора (например, языка или фильтра).
class PickerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const PickerItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(color: AppColors.border, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
