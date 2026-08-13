import 'package:easy_tab/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Опция выбора разрешения/типа доступа (например, Public / Private).
class PermissionOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String groupValue;
  final VoidCallback? onTap;

  const PermissionOption({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.groupValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}
