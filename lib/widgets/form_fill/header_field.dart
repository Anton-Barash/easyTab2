import 'package:easy_tab/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Подписанное текстовое поле для редактирования шапки отчёта.
class HeaderField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const HeaderField({super.key, required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
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
          decoration: const InputDecoration(
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.greyBorder),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.greyBorder),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            isDense: true,
          ),
          style: const TextStyle(color: AppColors.textDark, fontSize: 15),
        ),
      ],
    );
  }
}
