import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../providers/report_provider.dart';
import '../models/report_models.dart';

enum ViewMode { list, card }

class FormFillScreen extends StatefulWidget {
  FormFillScreen({super.key});

  @override
  _FormFillScreenState createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  final Map<String, Map<int, TextEditingController>> _answerControllers = {};
  ViewMode _viewMode = ViewMode.list;
  bool _isSidePanelCollapsed = false;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _answerControllers.values
        .expand((map) => map.values)
        .forEach((c) => c.dispose());
    _pageController.dispose();
    super.dispose();
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
      final answers = report.answers[qid] ?? [Answer()];
      for (int j = 0; j < answers.length; j++) {
        if (!_answerControllers[qid]!.containsKey(j)) {
          _answerControllers[qid]![j] = TextEditingController(
            text: answers[j].text,
          );
          _answerControllers[qid]![j]!.addListener(() {
            reportState.updateAnswerText(
              i,
              j,
              _answerControllers[qid]![j]!.text,
            );
          });
        }
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
                  reportState.setLanguage(lang);
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
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              reportState.addQuestion(
                _viewMode == ViewMode.card ? _currentPage : null,
              );
            },
            tooltip: 'Добавить вопрос',
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
            ],
            onSelected: (value) async {
              if (value == 0) {
                if (!kIsWeb) {
                  final htmlPath = await reportState.getHtmlPreviewPath(
                    report.reportName,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('HTML сохранён: $htmlPath')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Просмотр HTML — скоро!')),
                    );
                  }
                }
              } else if (value == 1) {
                await reportState.saveReport();
                final zipPath = await reportState.exportZip();
                if (zipPath != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ZIP сохранён: $zipPath')),
                  );
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
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFf8f7f2),
              child: CustomPaint(painter: DottedPatternPainter()),
            ),
          ),
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isSidePanelCollapsed ? 40 : 280,
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
                        width: 280,
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
                                  final qid = i.toString();
                                  final answers =
                                      report.answers[qid] ?? [Answer()];
                                  final answerCount = answers
                                      .where((a) => !a.isEmpty)
                                      .length;
                                  final attentionCount = answers
                                      .where((a) => a.attention)
                                      .length;
                                  final emptyCount = answers
                                      .where((a) => a.isEmpty)
                                      .length;

                                  final lang = report.currentLanguage;
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
                                          });
                                          _pageController.animateToPage(
                                            i,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.ease,
                                          );
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                                          q.getDisplayName(
                                                            lang,
                                                          ) ??
                                                          'Без названия',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Color(
                                                          0xFF424242,
                                                        ),
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
                                                            FontWeight.w500,
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
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '$attentionCount',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
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
        ],
      ),
    );
  }

  Widget _buildListView(ReportState reportState, Report report) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: report.questions.length,
      itemBuilder: (ctx, i) {
        final qid = i.toString();
        final q = report.questions[i];
        final answers = report.answers[qid] ?? [Answer()];
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
    final qid = index.toString();
    final report = reportState.currentReport!;
    final q = report.questions[index];
    final lang = report.currentLanguage;
    final loc = q.getLocalization(lang);
    final hasTranslation = q.hasTranslation(lang);
    final answers = report.answers[qid] ?? [Answer()];

    final width = isCardView ? 600.0 : double.infinity;

    return Container(
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(width: 2, color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFf3f4f6),
              border: Border(
                bottom: BorderSide(width: 1.5, color: const Color(0xFFe5e7eb)),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            ],
                          ),
                          if (loc?.example?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Пример: ${loc?.example}',
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
                if (!hasTranslation && q.hasSomeTranslation())
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFfff3cd),
                        border: Border.all(
                          width: 1,
                          color: const Color(0xFFffc107),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            size: 18,
                            color: Color(0xFF856404),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Перевод на ${report.currentLanguage} отсутствует. Доступно на: ${q.getAvailableLanguages().where((l) => l != report.currentLanguage).join(', ')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF856404),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (loc?.example?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFe0f2fe),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: Color(0xFF0369a1),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Пример: ${loc?.example}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF0369a1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                    qid,
                    answers[j],
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, color: Color(0xFF424242)),
                    label: const Text(
                      'Добавить ответ',
                      style: TextStyle(color: Color(0xFF424242)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFe5e7eb),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => reportState.addAnswer(index),
                  ),
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
              Expanded(
                child: TextField(
                  controller: _answerControllers[qid]![j],
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Введите ответ...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFe5e7eb)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFe5e7eb)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFef4444)),
                onPressed:
                    (reportState.currentReport?.answers[qid]?.length ?? 1) > 1
                    ? () => reportState.removeAnswer(i, j)
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
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, color: Color(0xFF424242)),
                  label: const Text(
                    'Фото/Видео',
                    style: TextStyle(color: Color(0xFF424242)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFe5e7eb),
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
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
