import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/report_provider.dart';
import '../models/report_models.dart';

import 'dart:async';

enum ViewMode { list, card }

class FormFillScreen extends StatefulWidget {
  FormFillScreen({super.key});

  @override
  _FormFillScreenState createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  final Map<String, Map<int, TextEditingController>> _answerControllers = {};
  final Map<String, Map<int, Timer?>> _debounceTimers = {};
  ViewMode _viewMode = ViewMode.list;
  bool _isSidePanelCollapsed = false;
  final PageController _pageController = PageController();
  final ScrollController _listScrollController = ScrollController();
  int _currentPage = 0;
  final Map<int, bool> _needsWorkMap = {};
  Set<int> _blockedQuestionIndices = {};
  bool _isUpdatingControllers = false;
  final Map<String, Map<int, bool>> _enabledAnswers = {};

  @override
  void dispose() {
    _answerControllers.values
        .expand((map) => map.values)
        .forEach((c) => c.dispose());
    _debounceTimers.values
        .expand((map) => map.values)
        .forEach((timer) => timer?.cancel());
    _pageController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _handleLanguageChange(String lang) {
    final reportState = context.read<ReportState>();
    final report = reportState.currentReport;
    if (report == null) return;

    final unsyncIndices = reportState.getUnsyncQuestionIndices();
    if (unsyncIndices.isNotEmpty) {
      _showSyncDialog(lang, unsyncIndices);
    } else {
      reportState.setLanguage(lang);
    }
  }

  void _showSyncDialog(String targetLang, List<int> unsyncIndices) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SyncDialog(
        reportState: context.read<ReportState>(),
        targetLang: targetLang,
        unsyncIndices: unsyncIndices,
        onSyncApplied: () {
          final reportState = context.read<ReportState>();
          reportState.setLanguage(targetLang);
          _blockedQuestionIndices.clear();
        },
        onSkipSync: () {
          final reportState = context.read<ReportState>();
          reportState.setLanguage(targetLang);
          setState(() {
            _blockedQuestionIndices = unsyncIndices.toSet();
          });
        },
      ),
    );
  }

  void _showSyncMenuDialog() {
    final reportState = context.read<ReportState>();
    final report = reportState.currentReport;
    if (report == null) return;

    final unsyncIndices = reportState.getUnsyncQuestionIndices();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SyncMenuDialog(
        reportState: reportState,
        unsyncIndices: unsyncIndices,
        onApplied: () {},
      ),
    );
  }

  void _showDeleteAnswerDialog(
    BuildContext context,
    int i,
    int j,
    ReportState reportState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить ответ?'),
        content: const Text(
          'Вы уверены, что хотите удалить этот ответ?\n\nЭто действие невозможно отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFdc2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              reportState.removeAnswer(i, j);
              Navigator.pop(ctx);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showLockDialog(
    BuildContext context,
    int i,
    int j,
    String qid,
    ReportState reportState,
  ) {
    final currentAnswer = reportState.currentReport?.getAnswersForQuestion(
      i,
      reportState.currentReport!.currentLanguage,
    )[j];
    final currentText = currentAnswer?.text ?? '';

    final TextEditingController replaceController = TextEditingController(
      text: currentText,
    );
    final TextEditingController newController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Изменение ответа'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Внимание! Изменение этого ответа приведет к удалению текста в других локализациях.',
                style: TextStyle(color: Color(0xFFef4444)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Заменить существующий ответ:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: replaceController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Введите новый текст ответа',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFe5e7eb)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Или добавить новый ответ:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Введите текст нового ответа',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFe5e7eb)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563eb),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _enabledAnswers[qid]![j] = true;
              });

              if (newController.text.isNotEmpty) {
                reportState.addAnswer(i);
                final newJ =
                    (reportState.currentReport
                            ?.getAnswersForQuestion(
                              i,
                              reportState.currentReport!.currentLanguage,
                            )
                            .length ??
                        1) -
                    1;
                reportState.updateAnswerText(i, newJ, newController.text);
              } else if (replaceController.text.isNotEmpty &&
                  replaceController.text != currentText) {
                reportState.updateAnswerText(i, j, replaceController.text);
              }

              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportState = context.watch<ReportState>();
    final report = reportState.currentReport;

    if (report == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Новый отчёт'),
          backgroundColor: const Color(0xFFe0e0e0),
          foregroundColor: const Color(0xFF424242),
          elevation: 0,
        ),
        body: const Center(child: Text('Нет отчёта')),
      );
    }

    for (int i = 0; i < report.questions.length; i++) {
      final qid = i.toString();
      if (!_answerControllers.containsKey(qid)) {
        _answerControllers[qid] = {};
      }
      if (!_enabledAnswers.containsKey(qid)) {
        _enabledAnswers[qid] = {};
      }
      if (!_debounceTimers.containsKey(qid)) {
        _debounceTimers[qid] = {};
      }
      final answers = report.getAnswersForQuestion(i, report.currentLanguage);

      final existingIndices = _answerControllers[qid]!.keys.toList();
      for (final j in existingIndices) {
        if (j >= answers.length) {
          _answerControllers[qid]![j]?.dispose();
          _answerControllers[qid]!.remove(j);
          _enabledAnswers[qid]!.remove(j);
          _debounceTimers[qid]![j]?.cancel();
          _debounceTimers[qid]!.remove(j);
        }
      }

      for (int j = 0; j < answers.length; j++) {
        if (!_answerControllers[qid]!.containsKey(j)) {
          _answerControllers[qid]![j] = TextEditingController(
            text: answers[j].text,
          );
          _answerControllers[qid]![j]!.addListener(() {
            if (!_isUpdatingControllers) {
              // Cancel previous timer
              _debounceTimers[qid]?[j]?.cancel();
              // Create new timer to update after 300ms of inactivity
              _debounceTimers[qid]![j] = Timer(
                const Duration(milliseconds: 300),
                () {
                  reportState.updateAnswerText(
                    i,
                    j,
                    _answerControllers[qid]![j]!.text,
                  );
                },
              );
            }
          });
        } else {
          final controller = _answerControllers[qid]![j]!;
          if (controller.text != answers[j].text) {
            _isUpdatingControllers = true;
            controller.text = answers[j].text;
            _isUpdatingControllers = false;
          }
        }

        final hasOtherAnswers = reportState.hasAnswersInOtherLanguages(i, j);
        _enabledAnswers[qid]![j] = !hasOtherAnswers;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(report.reportName),
        backgroundColor: const Color(0xFFe0e0e0),
        foregroundColor: const Color(0xFF424242),
        elevation: 0,
        actions: [
          if (report.availableLanguages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: PopupMenuButton<String>(
                icon: Row(
                  children: [
                    const Icon(Icons.language),
                    const SizedBox(width: 4),
                    Text(
                      report.currentLanguage,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                itemBuilder: (ctx) => report.availableLanguages
                    .map(
                      (lang) => PopupMenuItem(
                        value: lang,
                        child: Row(
                          children: [
                            Text(lang),
                            if (lang == report.currentLanguage)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check, size: 16),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onSelected: (lang) {
                  _handleLanguageChange(lang);
                },
              ),
            ),
          IconButton(
            icon: Icon(
              _viewMode == ViewMode.list ? Icons.grid_view : Icons.list,
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == ViewMode.list
                    ? ViewMode.card
                    : ViewMode.list;
              });
              if (_viewMode == ViewMode.card) {
                Future.delayed(Duration.zero, () {
                  _pageController.jumpToPage(_currentPage);
                });
              }
            },
            tooltip: 'Переключить вид',
          ),
          PopupMenuButton(
            icon: const Icon(Icons.menu),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.visibility),
                    SizedBox(width: 8),
                    Text('Просмотр HTML'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.save_alt),
                    SizedBox(width: 8),
                    Text('Сохранить ZIP'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 8),
                    Text('Поделиться'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 3,
                child: Row(
                  children: [
                    Icon(Icons.sync),
                    SizedBox(width: 8),
                    Text('Синхронизировать переводы'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 4,
                child: Row(
                  children: [
                    Icon(Icons.table_chart),
                    SizedBox(width: 8),
                    Text('Экспорт в Excel'),
                  ],
                ),
              ),
            ],
            onSelected: (value) async {
              if (value == 0) {
                final htmlContent = reportState.generateHtmlContent();
                try {
                  await Clipboard.setData(ClipboardData(text: htmlContent));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('HTML скопирован в буфер обмена'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка копирования: $e')),
                    );
                  }
                }
                // Also offer to save to file on non-web platforms
                if (!kIsWeb) {
                  try {
                    final directory = await FilePicker.platform
                        .getDirectoryPath();
                    if (directory != null) {
                      final filePath = '$directory/report.html';
                      final file = File(filePath);
                      await file.writeAsString(htmlContent);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('HTML сохранён: $filePath')),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка сохранения: $e')),
                      );
                    }
                  }
                }
              } else if (value == 4) {
                final excelHtml = reportState.generateExcelHtmlContent();
                try {
                  await Clipboard.setData(ClipboardData(text: excelHtml));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Excel HTML скопирован в буфер обмена'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка копирования: $e')),
                    );
                  }
                }
              } else if (value == 1) {
                if (kIsWeb) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Сохранение ZIP недоступно на вебе'),
                      ),
                    );
                  }
                  return;
                }
                await reportState.saveReport();
                try {
                  final directory = await FilePicker.platform
                      .getDirectoryPath();
                  if (directory != null) {
                    final zipPath = await reportState.exportZip(
                      customSavePath: directory,
                    );
                    if (zipPath != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ZIP сохранён: $zipPath')),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка сохранения ZIP: $e')),
                    );
                  }
                }
              } else if (value == 2) {
                if (kIsWeb) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Поделиться недоступно на вебе'),
                      ),
                    );
                  }
                  return;
                }
                await reportState.saveReport();
                final zipPath = await reportState.exportZip();
                if (zipPath != null && mounted) {
                  await reportState.shareZip(zipPath);
                }
              } else if (value == 3) {
                _showSyncMenuDialog();
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth <= 800;
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: const Color(0xFFf8f7f2),
                  child: CustomPaint(painter: DottedPatternPainter()),
                ),
              ),
              if (!isMobile)
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isSidePanelCollapsed ? 40 : 220,
                      child: _isSidePanelCollapsed
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSidePanelCollapsed = false;
                                });
                              },
                              child: Container(
                                width: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    right: BorderSide(
                                      width: 2,
                                      color: const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 16),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFF424242),
                                    ),
                                    const SizedBox(height: 8),
                                    RotatedBox(
                                      quarterTurns: 3,
                                      child: Text(
                                        'Вопросы',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF424242),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              width: 220,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  right: BorderSide(
                                    width: 2,
                                    color: const Color(0xFF333333),
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        const Text(
                                          'Вопросы',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Color(0xFF424242),
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left),
                                          onPressed: () {
                                            setState(() {
                                              _isSidePanelCollapsed = true;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      itemCount: report.questions.length,
                                      itemBuilder: (ctx, i) {
                                        final lang = report.currentLanguage;
                                        final answers = report
                                            .getAnswersForQuestion(i, lang);
                                        final answerCount = answers
                                            .where((a) => !a.isEmpty)
                                            .length;
                                        final attentionCount = answers
                                            .where((a) => a.attention)
                                            .length;

                                        final q = report.questions[i];
                                        final loc = q.getLocalization(lang);
                                        final hasTranslation = q.hasTranslation(
                                          lang,
                                        );

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Material(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _currentPage = i;
                                                });
                                                if (_viewMode ==
                                                    ViewMode.card) {
                                                  _pageController.animateToPage(
                                                    i,
                                                    duration: const Duration(
                                                      milliseconds: 300,
                                                    ),
                                                    curve: Curves.ease,
                                                  );
                                                } else {
                                                  _scrollToQuestion(i);
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    width: 1.5,
                                                    color:
                                                        _viewMode ==
                                                                ViewMode.card &&
                                                            _currentPage == i
                                                        ? const Color(
                                                            0xFF3b82f6,
                                                          )
                                                        : const Color(
                                                            0xFFe5e7eb,
                                                          ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFF333333,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Center(
                                                            child: Text(
                                                              '${i + 1}',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            loc?.name ??
                                                                q.getDisplayName(
                                                                  lang,
                                                                ) ??
                                                                'Без названия',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: Color(
                                                                    0xFF424242,
                                                                  ),
                                                                ),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    if (!hasTranslation &&
                                                        q.hasSomeTranslation())
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFfff3cd,
                                                          ),
                                                          border: Border.all(
                                                            width: 1,
                                                            color: const Color(
                                                              0xFFffc107,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'Переключите язык',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                              0xFF856404,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                answerCount > 0
                                                                ? const Color(
                                                                    0xFFd1fae5,
                                                                  )
                                                                : const Color(
                                                                    0xFFe5e7eb,
                                                                  ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            '$answerCount',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color:
                                                                  answerCount >
                                                                      0
                                                                  ? const Color(
                                                                      0xFF065f46,
                                                                    )
                                                                  : const Color(
                                                                      0xFF6b7280,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        if (attentionCount > 0)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFfff3cd,
                                                                  ),
                                                              border: Border.all(
                                                                width: 1,
                                                                color:
                                                                    const Color(
                                                                      0xFFfbbf24,
                                                                    ),
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                const Text(
                                                                  '⚡',
                                                                  style:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  '$attentionCount',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    color: Color(
                                                                      0xFF92400e,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        if (_needsWorkMap[i] ==
                                                            true)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFfef3c7,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.edit_note,
                                                              size: 14,
                                                              color: Color(
                                                                0xFFd97706,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Expanded(
                      child: _viewMode == ViewMode.list
                          ? _buildListView(reportState, report)
                          : _buildCardView(reportState, report),
                    ),
                  ],
                ),
              if (isMobile)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: const Color(0xFF333333),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.menu, size: 28),
                            color: const Color(0xFF424242),
                            onPressed: () {
                              setState(() {
                                _isSidePanelCollapsed = false;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'EasyTab',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF424242),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _viewMode == ViewMode.list
                          ? _buildListView(reportState, report)
                          : _buildCardView(reportState, report),
                    ),
                  ],
                ),
              if (isMobile && !_isSidePanelCollapsed)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSidePanelCollapsed = true;
                      });
                    },
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              if (isMobile && !_isSidePanelCollapsed)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 280,
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Text(
                                'Вопросы',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF424242),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _isSidePanelCollapsed = true;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: report.questions.length,
                            itemBuilder: (ctx, i) {
                              final lang = report.currentLanguage;
                              final answers = report.getAnswersForQuestion(
                                i,
                                lang,
                              );
                              final answerCount = answers
                                  .where((a) => !a.isEmpty)
                                  .length;
                              final attentionCount = answers
                                  .where((a) => a.attention)
                                  .length;

                              final q = report.questions[i];
                              final loc = q.getLocalization(lang);
                              final hasTranslation = q.hasTranslation(lang);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentPage = i;
                                        _isSidePanelCollapsed = true;
                                      });
                                      if (_viewMode == ViewMode.card) {
                                        _pageController.animateToPage(
                                          i,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.ease,
                                        );
                                      } else {
                                        _scrollToQuestion(i);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          width: 1.5,
                                          color:
                                              _viewMode == ViewMode.card &&
                                                  _currentPage == i
                                              ? const Color(0xFF3b82f6)
                                              : const Color(0xFFe5e7eb),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF333333,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  loc?.name ??
                                                      q.getDisplayName(lang) ??
                                                      'Без названия',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF424242),
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (!hasTranslation &&
                                              q.hasSomeTranslation())
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFfff3cd),
                                                border: Border.all(
                                                  width: 1,
                                                  color: const Color(
                                                    0xFFffc107,
                                                  ),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Переключите язык',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF856404),
                                                ),
                                              ),
                                            ),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: answerCount > 0
                                                      ? const Color(0xFFd1fae5)
                                                      : const Color(0xFFe5e7eb),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '$answerCount',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: answerCount > 0
                                                        ? const Color(
                                                            0xFF065f46,
                                                          )
                                                        : const Color(
                                                            0xFF6b7280,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              if (attentionCount > 0)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFfff3cd,
                                                    ),
                                                    border: Border.all(
                                                      width: 1,
                                                      color: const Color(
                                                        0xFFfbbf24,
                                                      ),
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Text(
                                                        '⚡',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '$attentionCount',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Color(
                                                            0xFF92400e,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              const SizedBox(width: 4),
                                              if (_needsWorkMap[i] == true)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFfef3c7,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.edit_note,
                                                    size: 14,
                                                    color: Color(0xFFd97706),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _scrollToQuestion(int index) {
    const itemHeight = 300.0;
    final offset = index * itemHeight;
    _listScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  Widget _buildListView(ReportState reportState, Report report) {
    return ListView.builder(
      controller: _listScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: report.questions.length,
      itemBuilder: (ctx, i) {
        final q = report.questions[i];
        final lang = report.currentLanguage;
        final loc = q.getLocalization(lang);
        final hasTranslation = q.hasTranslation(lang);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildQuestionCard(ctx, i, reportState, false),
        );
      },
    );
  }

  Widget _buildCardView(ReportState reportState, Report report) {
    if (report.questions.isEmpty) {
      return const Center(child: Text('Нет вопросов'));
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
            });
          },
          itemCount: report.questions.length,
          itemBuilder: (context, index) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: _buildQuestionCard(context, index, reportState, true),
            ),
          ),
        ),
        if (report.questions.length > 1) ...[
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildNavButton(
                Icons.chevron_left,
                _currentPage > 0
                    ? () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                      )
                    : null,
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildNavButton(
                Icons.chevron_right,
                _currentPage < report.questions.length - 1
                    ? () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                      )
                    : null,
              ),
            ),
          ),
        ],
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentPage + 1} / ${report.questions.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap != null
              ? const Color(0xFF333333)
              : const Color(0xFFcccccc),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Icon(
            icon,
            color: onTap != null ? Colors.white : const Color(0xFF999999),
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    int index,
    ReportState reportState,
    bool isCardView,
  ) {
    final report = reportState.currentReport!;
    final q = report.questions[index];
    final lang = report.currentLanguage;
    final loc = q.getLocalization(lang);
    final hasTranslation = q.hasTranslation(lang);
    final answers = report.getAnswersForQuestion(index, lang);

    final isMobile = MediaQuery.of(context).size.width <= 800;

    final width = isCardView && !isMobile ? 600.0 : double.infinity;

    return Container(
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? Border(
                top: BorderSide(width: 2, color: const Color(0xFF333333)),
                bottom: BorderSide(width: 2, color: const Color(0xFF333333)),
              )
            : Border.all(width: 2, color: const Color(0xFF333333)),
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: isMobile
                ? const EdgeInsets.fromLTRB(0, 8, 8, 0)
                : const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFf3f4f6),
              border: Border(
                bottom: BorderSide(width: 1.5, color: const Color(0xFFe5e7eb)),
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
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF333333),
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
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Вопрос требует доработки...',
                        child: IconButton(
                          icon: Icon(Icons.edit_note, size: 22),
                          color: _needsWorkMap[index] == true
                              ? const Color(0xFFf59e0b)
                              : const Color(0xFF9ca3af),
                          onPressed: () {
                            setState(() {
                              _needsWorkMap[index] =
                                  !(_needsWorkMap[index] ?? false);
                            });
                          },
                        ),
                      ),
                      if (loc?.description?.isNotEmpty ?? false)
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          color: const Color(0xFF6b7280),
                          onPressed: () => _showEditQuestionDialog(
                            context,
                            index,
                            reportState,
                            'description',
                          ),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        color: Colors.white,
                        elevation: 4,
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'add_above',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 8),
                                Text('Новый вопрос сверху'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'add_below',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 8),
                                Text('Новый вопрос снизу'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Color(0xFFdc2626),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Удалить этот вопрос',
                                  style: TextStyle(color: Color(0xFFdc2626)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'add_above') {
                            reportState.addQuestion(index - 1);
                            if (index > 0) {
                              _pageController.animateToPage(
                                index - 1,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.ease,
                              );
                            }
                          } else if (value == 'add_below') {
                            reportState.addQuestion(index);
                            _pageController.animateToPage(
                              index + 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease,
                            );
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Удалить вопрос?'),
                                content: const Text(
                                  'Вы уверены, что хотите удалить вопрос?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Отмена'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true &&
                                report.questions.length > 1) {
                              // TODO: implement delete question
                            }
                          }
                        },
                      ),
                    ],
                  ),
                if (isMobile)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: GestureDetector(
                      onTap: () => _showEditQuestionDialog(
                        context,
                        index,
                        reportState,
                        'name',
                      ),
                      child: Text(
                        loc?.name ?? q.getDisplayName(lang) ?? 'Без названия',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                if (!isMobile)
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF333333),
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
                                  child: GestureDetector(
                                    onTap: () => _showEditQuestionDialog(
                                      context,
                                      index,
                                      reportState,
                                      'name',
                                    ),
                                    child: Text(
                                      loc?.name ??
                                          q.getDisplayName(lang) ??
                                          'Без названия',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Вопрос требует доработки...',
                                  child: IconButton(
                                    icon: Icon(Icons.edit_note, size: 22),
                                    color: _needsWorkMap[index] == true
                                        ? const Color(0xFFf59e0b)
                                        : const Color(0xFF9ca3af),
                                    onPressed: () {
                                      setState(() {
                                        _needsWorkMap[index] =
                                            !(_needsWorkMap[index] ?? false);
                                      });
                                    },
                                  ),
                                ),
                                if (loc?.description?.isNotEmpty ?? false)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.help_outline,
                                      size: 20,
                                    ),
                                    color: const Color(0xFF6b7280),
                                    onPressed: () => _showEditQuestionDialog(
                                      context,
                                      index,
                                      reportState,
                                      'description',
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  color: Colors.white,
                                  elevation: 4,
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'add_above',
                                      child: Row(
                                        children: [
                                          Icon(Icons.add, size: 18),
                                          SizedBox(width: 8),
                                          Text('Новый вопрос сверху'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'add_below',
                                      child: Row(
                                        children: [
                                          Icon(Icons.add, size: 18),
                                          SizedBox(width: 8),
                                          Text('Новый вопрос снизу'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: Color(0xFFdc2626),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Удалить этот вопрос',
                                            style: TextStyle(
                                              color: Color(0xFFdc2626),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'add_above') {
                                      reportState.addQuestion(index - 1);
                                      if (index > 0) {
                                        _pageController.animateToPage(
                                          index - 1,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.ease,
                                        );
                                      }
                                    } else if (value == 'add_below') {
                                      reportState.addQuestion(index);
                                      _pageController.animateToPage(
                                        index + 1,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.ease,
                                      );
                                    } else if (value == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Удалить вопрос?'),
                                          content: const Text(
                                            'Вы уверены, что хотите удалить вопрос?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Отмена'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Удалить'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true &&
                                          report.questions.length > 1) {
                                        // TODO: implement delete question
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (loc?.example?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${loc?.example}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF0369a1),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int j = 0; j < answers.length; j++)
                  _buildAnswerBlock(
                    context,
                    index,
                    j,
                    reportState,
                    index.toString(),
                    answers[j],
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      color: const Color(0xFF424242),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFf3f4f6),
                        side: const BorderSide(
                          color: Color(0xFFe5e7eb),
                          width: 1.5,
                        ),
                      ),
                      onPressed: () => reportState.addAnswer(index),
                      tooltip: 'Добавить ответ',
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

  Widget _buildAnswerBlock(
    BuildContext context,
    int i,
    int j,
    ReportState reportState,
    String qid,
    Answer answer,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: answer.attention
            ? const Color(0xFFfff7ed)
            : const Color(0xFFf9fafb),
        border: Border.all(
          width: 1.5,
          color: answer.attention
              ? const Color(0xFFfed7aa)
              : const Color(0xFFe5e7eb),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.warning_amber,
                  color: answer.attention
                      ? const Color(0xFFf97316)
                      : const Color(0xFFd1d5db),
                ),
                onPressed: () {
                  reportState.updateAnswerAttention(i, j, !answer.attention);
                },
                tooltip: answer.attention
                    ? 'Снять отметку "Внимание"'
                    : 'Отметить "Внимание"',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _answerControllers[qid]![j],
                  maxLines: null,
                  enabled: _enabledAnswers[qid]?[j] ?? true,
                  style: TextStyle(
                    color: (_enabledAnswers[qid]?[j] ?? true)
                        ? Color(0xFF111827)
                        : Color(0xFF6b7280),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Введите ответ...',
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
              ),
              if (reportState.hasAnswersInOtherLanguages(i, j))
                IconButton(
                  icon: const Icon(Icons.lock, color: Color(0xFF6b7280)),
                  onPressed: () =>
                      _showLockDialog(context, i, j, qid, reportState),
                  tooltip: 'Открыть для редактирования',
                ),
              IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFef4444)),
                onPressed:
                    (reportState.currentReport?.answers[qid]?.length ?? 1) > 1
                    ? () => _showDeleteAnswerDialog(context, i, j, reportState)
                    : null,
                tooltip: 'Удалить ответ',
              ),
            ],
          ),
          if (answer.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: answer.media.asMap().entries.map((entry) {
                  final mediaIndex = entry.key;
                  final media = entry.value;
                  return Stack(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFf3f4f6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            width: 2,
                            color: media.attention
                                ? const Color(0xFFf59e0b)
                                : const Color(0xFFe5e7eb),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: media.type.startsWith('image')
                              ? (!kIsWeb && media.localPath != null
                                    ? Image.file(
                                        File(media.localPath!),
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.image,
                                          size: 30,
                                          color: Color(0xFF999999),
                                        ),
                                      ))
                              : _VideoThumbnailWidget(
                                  localPath: media.localPath,
                                  size: 70,
                                ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: () =>
                              reportState.removeMedia(i, j, mediaIndex),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 1.5,
                                color: const Color(0xFFe5e7eb),
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Color(0xFF6b7280),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  color: const Color(0xFF424242),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFf3f4f6),
                    side: const BorderSide(
                      color: Color(0xFFe5e7eb),
                      width: 1.5,
                    ),
                  ),
                  onPressed: () => _showMediaPicker(context, i, j, false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMediaPicker(
    BuildContext context,
    int questionIndex,
    int answerIndex,
    bool isAttention,
  ) async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить медиа'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Сделать видео'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    XFile? file;

    if (source == ImageSource.camera) {
      file = await picker.pickImage(source: source);
    } else {
      file = await picker.pickImage(source: source);
    }

    if (file != null) {
      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавление медиа на вебе — скоро!')),
          );
        }
        return;
      }
      await context.read<ReportState>().addMedia(
        questionIndex,
        answerIndex,
        File(file.path),
        isAttention,
      );
    }
  }
}

class _VideoThumbnailWidget extends StatefulWidget {
  final String? localPath;
  final int size;

  const _VideoThumbnailWidget({this.localPath, this.size = 80});

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    if (kIsWeb || widget.localPath == null) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.localPath!,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.size,
        maxHeight: widget.size,
        quality: 50,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailBytes != null) {
      return Image.memory(
        _thumbnailBytes!,
        width: widget.size.toDouble(),
        height: widget.size.toDouble(),
        fit: BoxFit.cover,
      );
    }
    return const Center(
      child: Icon(Icons.videocam, size: 30, color: Color(0xFF999999)),
    );
  }
}

void _showEditQuestionDialog(
  BuildContext context,
  int questionIndex,
  ReportState reportState,
  String fieldType,
) {
  final report = reportState.currentReport;
  if (report == null) return;

  final q = report.questions[questionIndex];
  final lang = report.currentLanguage;
  final loc = q.getLocalization(lang);

  String currentValue = '';
  String title = '';

  if (fieldType == 'name') {
    title = 'Редактировать название';
    currentValue = loc?.name ?? q.getDisplayName(lang) ?? '';
  } else if (fieldType == 'description') {
    title = 'Редактировать расшифровку';
    currentValue = loc?.description ?? '';
  }

  final controller = TextEditingController(text: currentValue);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: fieldType == 'description' ? 3 : 1,
        autofocus: true,
        decoration: InputDecoration(
          hintText: fieldType == 'name'
              ? 'Введите название...'
              : 'Введите расшифровку...',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () {
            final newValue = controller.text.trim();
            if (fieldType == 'name') {
              reportState.updateQuestionLocalization(
                questionIndex,
                lang,
                newValue,
                loc?.description,
                loc?.example,
              );
            } else if (fieldType == 'description') {
              reportState.updateQuestionLocalization(
                questionIndex,
                lang,
                loc?.name,
                newValue,
                loc?.example,
              );
            }
            Navigator.pop(ctx);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class _SyncDialog extends StatefulWidget {
  final ReportState reportState;
  final String targetLang;
  final List<int> unsyncIndices;
  final VoidCallback onSyncApplied;
  final VoidCallback onSkipSync;

  const _SyncDialog({
    required this.reportState,
    required this.targetLang,
    required this.unsyncIndices,
    required this.onSyncApplied,
    required this.onSkipSync,
  });

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  final TextEditingController _jsonController = TextEditingController();

  String get _syncJson => widget.reportState.generateSyncJson();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: _syncJson));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON скопирован в буфер обмена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка копирования: $e')));
      }
    }
  }

  Future<void> _saveToFile() async {
    try {
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/sync_answers_${widget.targetLang}.json');
      await file.writeAsString(_syncJson);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Файл сохранён: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  Future<void> _loadFromFile() async {
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
        ).showSnackBar(SnackBar(content: Text('Ошибка чтения файла: $e')));
      }
    }
  }

  void _applySync() {
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вставьте переведённый JSON')),
      );
      return;
    }

    try {
      widget.reportState.applySyncAnswers(jsonText);
      Navigator.pop(context);
      widget.onSyncApplied();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Синхронизация завершена')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: неверный формат JSON - $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Синхронизация ответов (${widget.targetLang})'),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFC107)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Воспользуйтесь любым доступным ИИ.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Пример промта: Изучи json, если в какой-то локализации нет ответа, но он есть в другой локализации, то переведи и вставь перевод; если ответов нет нигде, то оставь пустое поле.',
                      style: TextStyle(fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Пример промта для ИИ: "В этом json есть ответы на разных языках. Заполни пустые ответы переводами ответов, которые уже есть."',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Несинхронизированных вопросов: ${widget.unsyncIndices.length}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: const Text('Копировать'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
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
                      label: const Text('Скачать'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Вставьте переведённый JSON:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Вставьте JSON сюда...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF333333),
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
                label: const Text('Загрузить из файла'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe0e0e0),
                  foregroundColor: const Color(0xFF424242),
                  side: const BorderSide(color: Color(0xFF333333), width: 2),
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
          child: const Text(
            'Отказаться',
            style: TextStyle(color: Color(0xFF64748b)),
          ),
        ),
        ElevatedButton(
          onPressed: _applySync,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563eb),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF333333), width: 2),
          ),
          child: const Text('Синхронизировать'),
        ),
      ],
    );
  }
}

class _SyncMenuDialog extends StatefulWidget {
  final ReportState reportState;
  final List<int> unsyncIndices;
  final VoidCallback onApplied;

  const _SyncMenuDialog({
    required this.reportState,
    required this.unsyncIndices,
    required this.onApplied,
  });

  @override
  State<_SyncMenuDialog> createState() => _SyncMenuDialogState();
}

class _SyncMenuDialogState extends State<_SyncMenuDialog> {
  final TextEditingController _jsonController = TextEditingController();

  String get _syncJson => widget.reportState.generateSyncJson();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: _syncJson));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON скопирован в буфер обмена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка копирования: $e')));
      }
    }
  }

  Future<void> _saveToFile() async {
    try {
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/sync_answers.json');
      await file.writeAsString(_syncJson);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Файл сохранён: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  Future<void> _loadFromFile() async {
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
        ).showSnackBar(SnackBar(content: Text('Ошибка чтения файла: $e')));
      }
    }
  }

  void _applySync() {
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вставьте переведённый JSON')),
      );
      return;
    }

    try {
      widget.reportState.applySyncAnswers(jsonText);
      Navigator.pop(context);
      widget.onApplied();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Синхронизация завершена')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: неверный формат JSON - $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unsyncCount = widget.reportState.getUnsyncQuestionIndices().length;

    return AlertDialog(
      title: const Text('Синхронизация переводов'),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unsyncCount > 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFC107)),
                  ),
                  child: Text(
                    'Несинхронизированных вопросов: $unsyncCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4EDDA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF28A745)),
                  ),
                  child: const Text(
                    'Все ответы синхронизированы!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF155724),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDEE2E6)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Инструкция:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text('1. Скопируйте или скачайте JSON с текущими ответами'),
                    Text('2. Отправьте в ИИ для перевода пустых полей'),
                    Text('3. Вставьте результат или загрузите файл'),
                    Text('4. Нажмите "Синхронизировать"'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Пример промта для ИИ:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFDEE2E6)),
                ),
                child: const Text(
                  '"В этом json есть ответы на разных языках. Заполни пустые ответы переводами ответов, которые уже есть."',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: const Text('Копировать JSON'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
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
                      label: const Text('Скачать'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Загрузите переведённый JSON:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: 'Вставьте JSON сюда...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF333333),
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
                label: const Text('Загрузить из файла'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe0e0e0),
                  foregroundColor: const Color(0xFF424242),
                  side: const BorderSide(color: Color(0xFF333333), width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Закрыть',
            style: TextStyle(color: Color(0xFF64748b)),
          ),
        ),
        ElevatedButton(
          onPressed: _applySync,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563eb),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF333333), width: 2),
          ),
          child: const Text('Синхронизировать'),
        ),
      ],
    );
  }
}

class DottedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFcbc7bc)
      ..style = PaintingStyle.fill;

    const dotSize = 1.0;
    const spacing = 20.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
