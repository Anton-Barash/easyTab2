import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/screens/full_media_viewer_screen.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/widgets/media_item_widget.dart';
import 'package:flutter/material.dart';

/// Сетка миниатюр медиа-файлов ответа (максимум 8 видимых, далее "+N").
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [];
    const maxVisible = 8;
    final visibleCount = mediaList.length > maxVisible
        ? maxVisible
        : mediaList.length;

    for (int idx = 0; idx < visibleCount; idx++) {
      final media = mediaList[idx] as Map<String, dynamic>;
      final isLastExtra =
          idx == maxVisible - 1 && mediaList.length > maxVisible;

      if (isLastExtra) {
        // Показываем "+N"
        items.add(
          GestureDetector(
            onTap: () => _showFullMediaViewer(
              context,
              mediaList,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
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
        // Обычный медиа‑элемент
        items.add(
          MediaItemWidget(
            media: media,
            reportPath: reportState.currentReportPath,
            onTap: () => _showFullMediaViewer(
              context,
              mediaList,
              initialIndex: idx,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
            ),
            onLongPress: () => _showFullMediaViewer(
              context,
              mediaList,
              initialIndex: idx,
              questionIndex: questionIndex,
              answerIndex: answerIndex,
              reportState: reportState,
              startInSelectionMode: true,
            ),
            onDelete: () async {
              final loc = AppLocalizations.of(context)!;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(loc.deleteMediaTitle),
                  content: Text(loc.deleteMediaConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(loc.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: Text(loc.delete),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await reportState.removeMedia(questionIndex, answerIndex, idx);
                await reportState.saveReport();
              }
            },
          ),
        );
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }
}

void _showFullMediaViewer(
  BuildContext context,
  List mediaList, {
  int initialIndex = 0,
  int? questionIndex,
  int? answerIndex,
  ReportState? reportState,
  bool startInSelectionMode = false,
}) {
  // Снимаем фокус с текстовых полей, чтобы после закрытия просмотрщика
  // PageView не прокручивался к полю с курсором.
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (ctx) => FullMediaViewerScreen(
        mediaList: mediaList,
        initialIndex: initialIndex,
        reportPath: reportState?.currentReportPath,
        onDelete: (indices) async {
          if (questionIndex != null &&
              answerIndex != null &&
              reportState != null) {
            for (final index
                in indices.toList()..sort((a, b) => b.compareTo(a))) {
              await reportState.removeMedia(
                questionIndex,
                answerIndex,
                index,
              );
            }
            await reportState.saveReport();
          }
        },
        startInSelectionMode: startInSelectionMode,
      ),
    ),
  );
}
