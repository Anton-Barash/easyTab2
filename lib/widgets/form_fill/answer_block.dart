import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/widgets/form_fill/media_grid.dart';
import 'package:flutter/material.dart';

/// Блок одного ответа: текстовое поле, медиа и панель действий.
class AnswerBlock extends StatelessWidget {
  final int questionIndex;
  final int answerIndex;
  final ReportState reportState;
  final String qid;
  final Map<String, dynamic> answer;
  final TextEditingController? controller;
  final bool enabled;
  final bool needsWork;
  final VoidCallback onShowMediaPicker;
  final VoidCallback onShowAttachments;
  final ValueChanged<bool> onNeedsWorkChanged;
  final VoidCallback onMarkAsUnsaved;
  final VoidCallback onShowLockDialog;
  final VoidCallback onShowDeleteAnswerDialog;

  const AnswerBlock({
    super.key,
    required this.questionIndex,
    required this.answerIndex,
    required this.reportState,
    required this.qid,
    required this.answer,
    required this.controller,
    required this.enabled,
    required this.needsWork,
    required this.onShowMediaPicker,
    required this.onShowAttachments,
    required this.onNeedsWorkChanged,
    required this.onMarkAsUnsaved,
    required this.onShowLockDialog,
    required this.onShowDeleteAnswerDialog,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final attention = answer['attention'] == true;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    final report = reportState.currentReport;
    String? exampleText;
    if (report != null && questionIndex < report.questions.length) {
      final question = report.questions[questionIndex];
      final questionLoc = question.getLocalization(report.currentLanguage);
      exampleText = questionLoc?.example;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 6 : 12),
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: attention
            ? AppColors.attentionBackground
            : AppColors.greyBackground,
        border: Border.all(
          width: 1.5,
          color: attention ? AppColors.attentionBorder : AppColors.grey200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exampleText?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                exampleText!,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: AppColors.textLight,
                  fontStyle: FontStyle.italic,
                ),
                softWrap: true,
              ),
            ),
          TextField(
            controller: controller,
            maxLines: null,
            enabled: enabled,
            // Автоматически предлагать заглавную букву в начале
            // предложения (после точки).
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: enabled ? AppColors.textDark : AppColors.textLight,
            ),
            decoration: InputDecoration(
              hintText: loc.enterAnswer,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if ((answer['media'] as List?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: MediaGrid(
                mediaList: answer['media'] as List,
                questionIndex: questionIndex,
                answerIndex: answerIndex,
                reportState: reportState,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  color: AppColors.textPrimary,
                  onPressed: onShowMediaPicker,
                ),
                // Скрепка — прикреплённые файлы отчёта (с бейджем количества).
                Tooltip(
                  message: loc.attachmentsTitle,
                  child: Builder(
                    builder: (context) {
                      final count = reportState.attachmentsCount;
                      return IconButton(
                        icon: Badge(
                          isLabelVisible: count > 0,
                          label: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: AppColors.primary,
                          child: const Icon(Icons.attach_file),
                        ),
                        color: AppColors.textPrimary,
                        onPressed: onShowAttachments,
                      );
                    },
                  ),
                ),
                Tooltip(
                  message: loc.needsWorkTooltip,
                  child: IconButton(
                    icon: const Icon(Icons.edit_note),
                    color: needsWork
                        ? AppColors.warning
                        : AppColors.greyDisabled,
                    onPressed: () {
                      final newValue = !needsWork;
                      onNeedsWorkChanged(newValue);
                      reportState.updateAnswerNeedsWork(
                        questionIndex,
                        answerIndex,
                        newValue,
                      );
                      onMarkAsUnsaved();
                    },
                  ),
                ),
                Tooltip(
                  message: attention
                      ? loc.removeAttentionMark
                      : loc.addAttentionMark,
                  child: IconButton(
                    icon: Icon(
                      Icons.warning_amber,
                      color: attention
                          ? AppColors.warning
                          : AppColors.greyBorder,
                    ),
                    onPressed: () {
                      reportState.updateAnswerAttention(
                        questionIndex,
                        answerIndex,
                        !attention,
                      );
                      onMarkAsUnsaved();
                    },
                  ),
                ),
                if (reportState.hasAnswersInOtherLanguages(
                  questionIndex,
                  answerIndex,
                ))
                  IconButton(
                    icon: const Icon(Icons.lock, color: AppColors.textLight),
                    onPressed: onShowLockDialog,
                    tooltip: loc.lockAnswerTooltip,
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.errorLight),
                  onPressed:
                      (reportState
                                  .currentReport
                                  ?.translations[qid]
                                  ?.values
                                  .firstOrNull
                                  ?.length ??
                              1) >
                          1
                      ? onShowDeleteAnswerDialog
                      : null,
                  tooltip: loc.deleteAnswerTooltip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
