import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/screens/full_media_viewer_screen.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/widgets/media_item_widget.dart';
import 'package:flutter/material.dart';

/// Сетка миниатюр медиа-файлов ответа (максимум 8 видимых, далее "+N").
///
/// Здесь нет чекбоксов — множественный выбор/удаление выполняется
/// внутри полноэкранного просмотрщика [FullMediaViewerScreen]:
///   — тап по фото открывает одиночный просмотр;
///   — долгое нажатие открывает просмотрщик в режиме сетки с выбором
///     (это фото уже отмечено).
class MediaGrid extends StatelessWidget {
  final List mediaList;
  final int questionIndex;
  final int answerIndex;
  final ReportState reportState;

  const MediaGrid({
    super.key,
    required this.mediaList,
    required this.questionIndex,
    required this.answerIndex,
    required this.reportState,
  });

  Future<void> _openViewer(
    BuildContext context, {
    required int initialIndex,
    required bool startSelectionMode,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => FullMediaViewerScreen(
          mediaList: mediaList,
          initialIndex: initialIndex,
          reportPath: reportState.currentReportPath,
          onDelete: (indices) async {
            for (final index in indices.toList()..sort((a, b) => b.compareTo(a))) {
              await reportState.removeMedia(
                questionIndex,
                answerIndex,
                index,
              );
            }
            await reportState.saveReport();
          },
          startInSelectionMode: startSelectionMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const maxVisible = 8;
    final visibleCount = mediaList.length > maxVisible
        ? maxVisible
        : mediaList.length;
    final items = <Widget>[];

    for (int idx = 0; idx < visibleCount; idx++) {
      final media = mediaList[idx] as Map<String, dynamic>;
      final isLastExtra =
          idx == maxVisible - 1 && mediaList.length > maxVisible;

      if (isLastExtra) {
        // Показываем "+N"
        items.add(
          GestureDetector(
            onTap: () => _openViewer(
              context,
              initialIndex: idx,
              startSelectionMode: false,
            ),
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(width: 2, color: AppColors.grey200),
              ),
              child: Center(
                child: Text(
                  '+${mediaList.length - 7}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        items.add(
          MediaItemWidget(
            media: media,
            reportPath: reportState.currentReportPath,
            onTap: () => _openViewer(
              context,
              initialIndex: idx,
              startSelectionMode: false,
            ),
            onLongPress: () => _openViewer(
              context,
              initialIndex: idx,
              startSelectionMode: true,
            ),
          ),
        );
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }
}