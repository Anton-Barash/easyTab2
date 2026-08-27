import 'package:flutter/material.dart';
import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';

/// Экран просмотра/редактирования расшифровки вопроса.
///
/// По умолчанию открывается в режиме просмотра (только чтение).
/// Чтобы отредактировать, нужно нажать иконку-карандаш — тогда появятся
/// кнопки «Отмена» и «Сохранить».
class TranscriptionEditor extends StatefulWidget {
  const TranscriptionEditor({
    super.key,
    required this.questionIndex,
    required this.reportState,
    this.onSaved,
  });

  final int questionIndex;
  final ReportState reportState;
  final VoidCallback? onSaved;

  @override
  State<TranscriptionEditor> createState() => _TranscriptionEditorState();
}

class _TranscriptionEditorState extends State<TranscriptionEditor> {
  late final TextEditingController _controller;
  bool _isEditing = false;
  late String _originalValue;

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    final report = widget.reportState.currentReport;
    final q = report?.questions[widget.questionIndex];
    final questionLoc = q?.getLocalization(report?.currentLanguage ?? '');
    _originalValue = questionLoc?.description ?? '';
    _controller = TextEditingController(text: _originalValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    // Ставим курсор в конец текста.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _controller.text = _originalValue;
      _isEditing = false;
    });
  }

  void _save() {
    final newValue = _controller.text;
    final report = widget.reportState.currentReport;
    final q = report?.questions[widget.questionIndex];
    final questionLoc = q?.getLocalization(report?.currentLanguage ?? '');

    widget.reportState.updateQuestionLocalization(
      widget.questionIndex,
      report?.currentLanguage ?? '',
      questionLoc?.name,
      newValue,
      questionLoc?.example,
    );

    _originalValue = newValue;
    widget.onSaved?.call();
    setState(() => _isEditing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_loc.saved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final screenPadding = MediaQuery.of(context).padding;

    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: isMobile ? 16 : 18,
          fontWeight: FontWeight.w600,
        );

    final minLines = isMobile ? 8 : 10;
    final maxLines = isMobile ? 18 : 25;
    final maxWidth = isMobile ? double.infinity : 800.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        toolbarHeight: kToolbarHeight + screenPadding.top,
        flexibleSpace: Container(
          height: screenPadding.top,
          color: Colors.white,
        ),
        title: Text(
          _loc.transcription,
          style: titleStyle,
        ),
        centerTitle: false,
        leading: IconButton(
          tooltip: _loc.close,
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              tooltip: _loc.edit,
              icon: const Icon(Icons.edit, color: AppColors.textPrimary),
              onPressed: _startEditing,
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 40,
                vertical: isMobile ? 12 : 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      readOnly: !_isEditing,
                      minLines: minLines,
                      maxLines: maxLines,
                      autofocus: false,
                      expands: false,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: isMobile ? 15 : 16,
                            height: 1.35,
                          ),
                      decoration: InputDecoration(
                        hintText: _isEditing ? _loc.enterDecryption : null,
                        hintMaxLines: 2,
                        filled: true,
                        fillColor: _isEditing
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditing
                                ? AppColors.greyBorder
                                : AppColors.greyBorder.withValues(alpha: 0.4),
                          ),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(10)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary),
                          borderRadius:
                              BorderRadius.all(Radius.circular(10)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _cancelEditing,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: Text(_loc.cancel),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: Text(_loc.save),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
