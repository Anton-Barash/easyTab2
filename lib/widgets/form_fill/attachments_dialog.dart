import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report_models.dart';
import '../../providers/report_provider.dart';
import '../../services/mime_utils.dart';
import '../../utils/app_colors.dart';
import '../../utils/open_html.dart';
import '../../utils/platform_io.dart'
    if (dart.library.html) '../../utils/platform_io_web.dart';

/// Модальное окно «Прикреплённые файлы» — список всех attachments
/// текущего отчёта, сгруппированный по вопросам.
///
/// Функции:
///  - список файлов с разбивкой по вопросам;
///  - «Добавить новый файл» — FilePicker (any, ≤55 MB);
///  - «три точки» → «Удалить» — удалить файл с сервера и из списка;
///  - тап по имени файла — открыть/скачать (presigned URL);
///  - текстовое примечание о лимите 55 MB и отсутствии сжатия.
Future<void> showAttachmentsDialog(
  BuildContext context, {
  required int questionIndex,
  required int answerIndex,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => _AttachmentsDialog(
      questionIndex: questionIndex,
      answerIndex: answerIndex,
    ),
  );
}

class _AttachmentsDialog extends StatelessWidget {
  final int questionIndex;
  final int answerIndex;

  const _AttachmentsDialog({
    required this.questionIndex,
    required this.answerIndex,
  });

  Future<void> _addNewFile(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final picked = result.files.first;
    final fileName = picked.name;
    final mimeType = mimeTypeFromFilename(fileName);

    bool ok;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) {
        _showSnack(context, loc.attachmentsUploadFailed);
        return;
      }
      if (bytes.length > ReportState.kMaxAttachmentBytes) {
        _showSnack(context, loc.attachmentsTooLarge);
        return;
      }
      ok = await reportState.addAttachmentFromBytes(
        questionIndex: questionIndex,
        answerIndex: answerIndex,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    } else {
      final path = picked.path;
      if (path == null) {
        _showSnack(context, loc.attachmentsUploadFailed);
        return;
      }
      final fileSize = await File(path).length();
      if (!context.mounted) return;
      if (fileSize > ReportState.kMaxAttachmentBytes) {
        _showSnack(context, loc.attachmentsTooLarge);
        return;
      }
      ok = await reportState.addAttachmentFromFile(
        questionIndex: questionIndex,
        answerIndex: answerIndex,
        filePath: path,
        fileName: fileName,
        mimeType: mimeType,
      );
    }

    if (!ok && context.mounted) {
      _showSnack(context, loc.attachmentsUploadFailed);
    }
  }

  Future<void> _deleteFile(BuildContext context, Attachment a) async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();
    final ok = await reportState.removeAttachment(a.id);
    if (context.mounted) {
      _showSnack(
        context,
        ok ? loc.attachmentsDeleted : loc.attachmentsUploadFailed,
      );
    }
  }

  Future<void> _openFile(BuildContext context, Attachment a) async {
    final loc = AppLocalizations.of(context)!;
    final reportState = context.read<ReportState>();
    final url = await reportState.getAttachmentUrl(a);
    if (!context.mounted) return;

    if (url != null && url.isNotEmpty) {
      if (kIsWeb) {
        openHtmlInBrowserUrl(url);
      } else {
        // На native — открываем через системный обработчик.
        // Если webUrl ведёт на http(s) — используем OpenFile через
        // скачанный временный файл. Для простоты: если есть localPath,
        // открываем локальный файл, иначе — webUrl через OpenFile (если
        // плагин поддерживает URL), иначе показываем ошибку.
        if (a.localPath != null) {
          final res = await OpenFile.open(a.localPath!);
          if (res.type != ResultType.done && context.mounted) {
            _showSnack(context, loc.attachmentsOpenFailed);
          }
        } else {
          // Пытаемся открыть URL напрямую (некоторые плагины это умеют).
          final res = await OpenFile.open(url);
          if (res.type != ResultType.done && context.mounted) {
            _showSnack(context, loc.attachmentsOpenFailed);
          }
        }
      }
    } else {
      _showSnack(context, loc.attachmentsOpenFailed);
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Consumer<ReportState>(
      builder: (ctx, reportState, _) {
        final report = reportState.currentReport;
        final all = reportState.attachments;

        // Группируем attachments по вопросам.
        final byQuestion = <int, List<Attachment>>{};
        for (final a in all) {
          byQuestion.putIfAbsent(a.questionIndex, () => []).add(a);
        }

        // Вопросы, у которых есть файлы, в порядке индексов.
        final questionIndexes = byQuestion.keys.toList()..sort();

        return AlertDialog(
          title: Text(loc.attachmentsTitle),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Примечание о 55MB / без сжатия.
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.attentionBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.attentionBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.attachmentsNote,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Список файлов, сгруппированный по вопросам.
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          loc.attachmentsEmpty,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final qi in questionIndexes) ...[
                      _QuestionHeader(
                        report: report,
                        questionIndex: qi,
                      ),
                      for (final a in byQuestion[qi]!)
                        _AttachmentTile(
                          attachment: a,
                          sizeLabel: _formatSize(a.fileSize),
                          onOpen: () => _openFile(ctx, a),
                          onDelete: () => _deleteFile(ctx, a),
                        ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _addNewFile(ctx),
              icon: const Icon(Icons.add),
              label: Text(loc.attachmentsAddNew),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.cancel),
            ),
          ],
        );
      },
    );
  }
}

class _QuestionHeader extends StatelessWidget {
  final dynamic report;
  final int questionIndex;

  const _QuestionHeader({required this.report, required this.questionIndex});

  @override
  Widget build(BuildContext context) {
    String title = 'Вопрос ${questionIndex + 1}';
    if (report != null && questionIndex < report.questions.length) {
      final q = report.questions[questionIndex];
      final locQ = q.getLocalization(report.currentLanguage);
      final name = locQ?.name;
      if (name != null && name.isNotEmpty) title = name;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final Attachment attachment;
  final String sizeLabel;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _AttachmentTile({
    required this.attachment,
    required this.sizeLabel,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: attachment.isUploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.insert_drive_file, size: 20),
      title: InkWell(
        onTap: attachment.isUploading ? null : onOpen,
        child: Text(
          attachment.fileName,
          style: TextStyle(
            fontSize: 13,
            color: attachment.isUploading
                ? AppColors.textTertiary
                : AppColors.primary,
            decoration: attachment.isUploading
                ? TextDecoration.none
                : TextDecoration.underline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Text(
        sizeLabel,
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        itemBuilder: (menuCtx) => [
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Text(loc.fileMenuDelete),
              ],
            ),
          ),
        ],
        onSelected: (v) {
          if (v == 'delete') onDelete();
        },
      ),
    );
  }
}
