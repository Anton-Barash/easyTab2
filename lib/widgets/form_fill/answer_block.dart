import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/widgets/form_fill/media_grid.dart';
import 'package:flutter/material.dart';

/// Блок одного ответа: текстовое поле, медиа и панель действий.
class AnswerBlock extends StatefulWidget {
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
  State<AnswerBlock> createState() => _AnswerBlockState();
}

class _AnswerBlockState extends State<AnswerBlock> {
  /// Флаг подсветки «новый чужой ответ». Устанавливается один раз при первом
  /// построении (если ответ действительно новый и чужой), затем через 2 сек
  /// сбрасывается — анимация плавно возвращает нормальный цвет.
  bool _highlighted = false;

  @override
  void initState() {
    super.initState();
    _checkForeignNew();
  }

  @override
  void didUpdateWidget(covariant AnswerBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ответ мог смениться (другой rid) — перепроверяем подсветку.
    if (oldWidget.answer['rid'] != widget.answer['rid']) {
      _checkForeignNew();
    }
  }

  void _checkForeignNew() {
    final rid = widget.answer['rid']?.toString();
    final authorId = widget.answer['authorId']?.toString();
    final isForeign = widget.reportState.isForeignNewAnswer(
      widget.qid,
      rid,
      authorId,
      authorIsAnonymous: widget.answer['authorIsAnonymous'] == true,
    );
    if (!isForeign) return;
    setState(() => _highlighted = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlighted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.answer;
    final loc = AppLocalizations.of(context)!;
    final attention = answer['attention'] == true;
    final isMobile = MediaQuery.of(context).size.width <= 800;
    // «Фантомный» ряд: реального ответа ещё нет в данных (новый отчёт).
    final isFake = answer['fake'] == true;

    final report = widget.reportState.currentReport;
    String? exampleText;
    if (report != null && widget.questionIndex < report.questions.length) {
      final question = report.questions[widget.questionIndex];
      final questionLoc = question.getLocalization(report.currentLanguage);
      exampleText = questionLoc?.example;
    }

    // Нормальный фон (attention или grey). Подсветка «новый чужой ответ»
    // приоритетна — она перекрывает и attention, и grey на 2 секунды.
    final Color normalColor = attention
        ? AppColors.attentionBackground
        : AppColors.greyBackground;
    final Color animatedColor = _highlighted
        ? AppColors.foreignAnswerHighlight
        : normalColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(bottom: isMobile ? 6 : 12),
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: animatedColor,
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
            controller: widget.controller,
            maxLines: null,
            enabled: widget.enabled,
            // Автоматически предлагать заглавную букву в начале
            // предложения (после точки).
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: widget.enabled ? AppColors.textDark : AppColors.textLight,
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
          if (!isFake && ((answer['media'] as List?)?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: MediaGrid(
                mediaList: answer['media'] as List,
                questionIndex: widget.questionIndex,
                answerIndex: widget.answerIndex,
                reportState: widget.reportState,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  color: AppColors.textPrimary,
                  onPressed: widget.onShowMediaPicker,
                ),
                Tooltip(
                  message: loc.attachmentsTitle,
                  child: Builder(
                    builder: (context) {
                      final count = widget.reportState.attachmentsCountForAnswer(
                        widget.questionIndex,
                        widget.answerIndex,
                      );
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.attach_file_outlined),
                            color: AppColors.textPrimary,
                            onPressed: widget.onShowAttachments,
                          ),
                          if (count > 0)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (!isFake)
                  Tooltip(
                    message: loc.needsWorkTooltip,
                    child: IconButton(
                      icon: const Icon(Icons.edit_note),
                      color: widget.needsWork
                          ? AppColors.warning
                          : AppColors.greyDisabled,
                      onPressed: () {
                        final newValue = !widget.needsWork;
                        widget.onNeedsWorkChanged(newValue);
                        widget.reportState.updateAnswerNeedsWork(
                          widget.questionIndex,
                          widget.answerIndex,
                          newValue,
                        );
                        widget.onMarkAsUnsaved();
                      },
                    ),
                  ),
                if (!isFake)
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
                        widget.reportState.updateAnswerAttention(
                          widget.questionIndex,
                          widget.answerIndex,
                          !attention,
                        );
                        widget.onMarkAsUnsaved();
                      },
                    ),
                  ),
                if (!isFake &&
                    widget.reportState.hasAnswersInOtherLanguages(
                      widget.questionIndex,
                      widget.answerIndex,
                    ))
                  IconButton(
                    icon: const Icon(Icons.lock, color: AppColors.textLight),
                    onPressed: widget.onShowLockDialog,
                    tooltip: loc.lockAnswerTooltip,
                  ),
                if (!isFake) const Spacer(),
                if (!isFake)
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppColors.errorLight),
                    onPressed:
                        (widget.reportState
                                    .currentReport
                                    ?.translations[widget.qid]
                                    ?.values
                                    .firstOrNull
                                    ?.length ??
                                1) >
                            1
                        ? widget.onShowDeleteAnswerDialog
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
