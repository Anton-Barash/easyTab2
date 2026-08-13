import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/widgets/form_fill/answer_block.dart';
import 'package:flutter/material.dart';

/// Карточка одного вопроса со списком ответов (list/card view).
class QuestionCard extends StatelessWidget {
  final int index;
  final ReportState reportState;
  final bool isCardView;
  final TextEditingController? Function(String qid, int answerIndex)
  answerControllerFor;
  final bool Function(String qid, int answerIndex) answerEnabledFor;
  final bool needsWork;
  final ValueChanged<bool> onNeedsWorkChanged;
  final VoidCallback onMarkAsUnsaved;
  final VoidCallback onQuestionNumberTap;
  final ValueChanged<String> onEditQuestion;
  final VoidCallback onAddQuestionAbove;
  final VoidCallback onAddQuestionBelow;
  final Future<void> Function() onDeleteQuestion;
  final void Function(int answerIndex) onShowMediaPicker;
  final void Function(int answerIndex, String qid) onShowLockDialog;
  final void Function(int answerIndex) onShowDeleteAnswerDialog;

  const QuestionCard({
    super.key,
    required this.index,
    required this.reportState,
    required this.isCardView,
    required this.answerControllerFor,
    required this.answerEnabledFor,
    required this.needsWork,
    required this.onNeedsWorkChanged,
    required this.onMarkAsUnsaved,
    required this.onQuestionNumberTap,
    required this.onEditQuestion,
    required this.onAddQuestionAbove,
    required this.onAddQuestionBelow,
    required this.onDeleteQuestion,
    required this.onShowMediaPicker,
    required this.onShowLockDialog,
    required this.onShowDeleteAnswerDialog,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final report = reportState.currentReport!;
    final q = report.questions[index];
    final lang = report.currentLanguage;
    final questionLoc = q.getLocalization(lang);
    final answers = report.getAnswersForQuestion(index, lang);

    final isMobile = MediaQuery.of(context).size.width <= 800;

    final width = isCardView && !isMobile ? 600.0 : double.infinity;

    return Container(
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? const Border(
                top: BorderSide(width: 2, color: AppColors.border),
                bottom: BorderSide(width: 2, color: AppColors.border),
              )
            : Border.all(width: 2, color: AppColors.border),
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: isMobile
                ? const EdgeInsets.fromLTRB(0, 4, 4, 0)
                : const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              border: const Border(
                bottom: BorderSide(width: 1.5, color: AppColors.grey200),
              ),
              borderRadius: isMobile
                  ? BorderRadius.zero
                  : const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile)
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: onQuestionNumberTap,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: () => onEditQuestion('name'),
                          child: Text(
                            questionLoc?.name ??
                                q.getDisplayName(lang) ??
                                loc.noName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ),
                      if (questionLoc?.description?.isNotEmpty ?? false)
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          color: AppColors.textLight,
                          onPressed: () => onEditQuestion('description'),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        color: Colors.white,
                        elevation: 4,
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'add_above',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 18),
                                const SizedBox(width: 8),
                                Text(loc.newQuestionAbove),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'add_below',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 18),
                                const SizedBox(width: 8),
                                Text(loc.newQuestionBelow),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: AppColors.errorLight,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  loc.deleteThisQuestion,
                                  style: const TextStyle(
                                    color: AppColors.errorLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'add_above') {
                            onAddQuestionAbove();
                          } else if (value == 'add_below') {
                            onAddQuestionBelow();
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(loc.deleteQuestionTitle),
                                content: Text(loc.deleteQuestionConfirm),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(loc.cancel),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(loc.delete),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true &&
                                report.questions.length > 1) {
                              await onDeleteQuestion();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                if (!isMobile)
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: GestureDetector(
                                    onTap: () => onEditQuestion('name'),
                                    child: Text(
                                      questionLoc?.name ??
                                          q.getDisplayName(lang) ??
                                          loc.noName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDark,
                                      ),
                                      softWrap: true,
                                    ),
                                  ),
                                ),
                                if (questionLoc?.description?.isNotEmpty ??
                                    false)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.help_outline,
                                      size: 20,
                                    ),
                                    color: AppColors.textLight,
                                    onPressed: () =>
                                        onEditQuestion('description'),
                                  ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  color: Colors.white,
                                  elevation: 4,
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'add_above',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.add, size: 18),
                                          const SizedBox(width: 8),
                                          Text(loc.newQuestionAbove),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'add_below',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.add, size: 18),
                                          const SizedBox(width: 8),
                                          Text(loc.newQuestionBelow),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: AppColors.errorLight,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            loc.deleteThisQuestion,
                                            style: const TextStyle(
                                              color: AppColors.errorLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'add_above') {
                                      onAddQuestionAbove();
                                    } else if (value == 'add_below') {
                                      onAddQuestionBelow();
                                    } else if (value == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(loc.deleteQuestionTitle),
                                          content: Text(
                                            loc.deleteQuestionConfirm,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(loc.cancel),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(loc.delete),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true &&
                                          report.questions.length > 1) {
                                        await onDeleteQuestion();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (questionLoc?.example?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${questionLoc?.example}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: isMobile
                ? const EdgeInsets.all(8)
                : const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int j = 0; j < answers.length; j++)
                  AnswerBlock(
                    questionIndex: index,
                    answerIndex: j,
                    reportState: reportState,
                    qid: index.toString(),
                    answer: answers[j],
                    controller: answerControllerFor(index.toString(), j),
                    enabled: answerEnabledFor(index.toString(), j),
                    needsWork: needsWork,
                    onShowMediaPicker: () => onShowMediaPicker(j),
                    onNeedsWorkChanged: onNeedsWorkChanged,
                    onMarkAsUnsaved: onMarkAsUnsaved,
                    onShowLockDialog: () =>
                        onShowLockDialog(j, index.toString()),
                    onShowDeleteAnswerDialog: () =>
                        onShowDeleteAnswerDialog(j),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      color: AppColors.textPrimary,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.grey100,
                        side: const BorderSide(
                          color: AppColors.grey200,
                          width: 1.5,
                        ),
                      ),
                      onPressed: () {
                        reportState.addAnswer(index);
                        onMarkAsUnsaved();
                      },
                      tooltip: loc.addAnswerTooltip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
