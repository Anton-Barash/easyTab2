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
                // Скрепка — прикреплённые файлы отчёта.
                // Единый стиль с соседними иконками: IconButton + Icon(Icons.attach_file).
                // Бейдж показывает количество вложений только у данного ответа.
                Tooltip(
                  message: loc.attachmentsTitle,
                  child: Builder(
                    builder: (context) {
                      final count = reportState.attachmentsCountForAnswer(
                        questionIndex,
                        answerIndex,
                      );
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            // Icons.attach_file не рендерится в CanvasKit web,
                            // поэтому рисуем тот же глиф вручную через CustomPaint.
                            icon: const CustomPaint(
                              size: Size(24, 24),
                              painter: _PaperclipPainter(),
                            ),
                            color: AppColors.textPrimary,
                            onPressed: onShowAttachments,
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

/// Рисует глиф скрепки (Icons.attach_file) вручную.
/// Материал-иконка attach_file не рендерится в CanvasKit web,
/// поэтому повторяем её путь векторно — иконка однотонная,
/// как остальные кнопки в приложении.
class _PaperclipPainter extends CustomPainter {
  const _PaperclipPainter({this.color = AppColors.textPrimary});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Масштабируем 24x24 путь под фактический размер виджета,
    // чтобы IconButton-констрейнты не сжали глиф до нуля.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    // Путь скопирован из Icons.attach_file (Material Icons, 24x24).
    final path = Path()
      ..moveTo(16.5, 6)
      ..lineTo(16.5, 17.5)
      ..cubicTo(16.5, 19.71, 14.71, 21.5, 12.5, 21.5)
      ..cubicTo(10.29, 21.5, 6.29, 19.71, 8.5, 17.5)
      ..lineTo(8.5, 5)
      ..cubicTo(8.5, 3.62, 9.62, 2.5, 11, 2.5)
      ..cubicTo(12.38, 2.5, 14.88, 3.62, 13.5, 5)
      ..lineTo(13.5, 15.5)
      ..cubicTo(13.5, 16.05, 12.05, 16.5, 12.5, 16.5)
      ..cubicTo(12.95, 16.5, 11.95, 16.05, 11.5, 15.5)
      ..lineTo(11.5, 6)
      ..lineTo(10, 6)
      ..lineTo(10, 15.5)
      ..cubicTo(10, 16.88, 11.12, 18, 12.5, 18)
      ..cubicTo(13.88, 18, 16.38, 16.88, 15, 15.5)
      ..lineTo(15, 5)
      ..cubicTo(15, 2.79, 13.21, 1, 11, 1)
      ..cubicTo(8.79, 1, 4.79, 2.79, 7, 5)
      ..lineTo(7, 17.5)
      ..cubicTo(7, 20.54, 9.46, 23, 12.5, 23)
      ..cubicTo(15.54, 23, 21.04, 20.54, 18, 17.5)
      ..lineTo(18, 6)
      ..lineTo(16.5, 6)
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperclipPainter oldDelegate) =>
      oldDelegate.color != color;
}
