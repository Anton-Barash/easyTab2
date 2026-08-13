import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Диалог синхронизации ответов для конкретного языка.
///
/// Позволяет скопировать JSON с ответами, сохранить его в файл,
/// загрузить переведённый JSON из файла и применить синхронизацию.
class SyncDialog extends StatefulWidget {
  final ReportState reportState;
  final String targetLang;
  final List<int> unsyncIndices;
  final VoidCallback onSyncApplied;
  final VoidCallback onSkipSync;

  const SyncDialog({
    super.key,
    required this.reportState,
    required this.targetLang,
    required this.unsyncIndices,
    required this.onSyncApplied,
    required this.onSkipSync,
  });

  @override
  State<SyncDialog> createState() => SyncDialogState();
}

class SyncDialogState extends State<SyncDialog> {
  final TextEditingController _jsonController = TextEditingController();

  String get _syncJson => widget.reportState.generateSyncJson();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final loc = AppLocalizations.of(context)!;
    try {
      await Clipboard.setData(ClipboardData(text: _syncJson));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.jsonCopiedToClipboard)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.copyError(e.toString()))));
      }
    }
  }

  Future<void> _saveToFile() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/sync_answers_${widget.targetLang}.json');
      await file.writeAsString(_syncJson);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.fileSaved(file.path))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.saveError(e.toString()))));
      }
    }
  }

  Future<void> _loadFromFile() async {
    final loc = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _jsonController.text = content;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.readError(e.toString()))));
      }
    }
  }

  void _applySync() {
    final loc = AppLocalizations.of(context)!;
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.pasteTranslatedJson)));
      return;
    }

    try {
      widget.reportState.applySyncAnswers(jsonText);
      Navigator.pop(context);
      widget.onSyncApplied();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.syncComplete)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.invalidJsonError(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    return AlertDialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(40),
      contentPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.all(24),
      shape: isMobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Text(loc.syncAnswersTitle(widget.targetLang)),
      content: SizedBox(
        width: isMobile ? double.infinity : 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.useAnyAi,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.aiPromptExample,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.aiPromptExample2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loc.unsyncedQuestionsCount(widget.unsyncIndices.length),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: Text(loc.copyButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveToFile,
                      icon: const Icon(Icons.download),
                      label: Text(loc.downloadButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                loc.pasteTranslatedJson,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: loc.pasteJsonHere,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.border,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _loadFromFile,
                icon: const Icon(Icons.upload_file),
                label: Text(loc.loadFromFileButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onSkipSync();
          },
          child: Text(
            loc.cancel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _applySync,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border, width: 2),
          ),
          child: Text(loc.syncButton),
        ),
        if (isMobile) const SizedBox(height: 100),
      ],
    );
  }
}
