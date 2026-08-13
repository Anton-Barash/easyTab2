import 'package:easy_tab/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Заголовок секции формы.
class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.border,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
