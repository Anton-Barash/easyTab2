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
  final Map<int, TextEditingController> _questionControllers = {};
  ViewMode _viewMode = ViewMode.list;
  bool _isSidePanelOpen = true;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _answerControllers.values
        .expand((map) => map.values)
        .forEach((c) => c.dispose());
    _questionControllers.values.forEach((c) => c.dispose());
    _pageController.dispose();
    super.dispose();
  }

  TextEditingController _getQuestionController(int index, String initialText) {
    if (!_questionControllers.containsKey(index)) {
      _questionControllers[index] = TextEditingController(text: initialText);
    }
    return _questionControllers[index]!;
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
              reportState.addQuestion();
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
                if (kIsWeb) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('HTML не поддерживается на вебе'),
                      ),
                    );
                  }
                  return;
                }
                await reportState.saveReport();
                final path = await reportState.getHtmlPreviewPath(
                  reportState.currentReportPath!,
                );
                try {
                  await Process.start('start', [path]);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка открытия: $e')),
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
              if (_viewMode == ViewMode.card)
                _buildSidePanel(reportState, report),
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

  Widget _buildSidePanel(ReportState reportState, Report report) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isSidePanelOpen ? 280 : 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: const Color(0xFF999999), width: 1),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFcccccc), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: _isSidePanelOpen
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              children: [
                if (_isSidePanelOpen)
                  const Text(
                    'Навигация',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF424242),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    _isSidePanelOpen ? Icons.chevron_left : Icons.chevron_right,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSidePanelOpen = !_isSidePanelOpen;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: report.questions.length,
              itemBuilder: (ctx, index) {
                final qid = index.toString();
                final answers = report.answers[qid] ?? [];
                final answerCount = answers.where((a) => !a.isEmpty).length;
                final attentionCount = answers.where((a) => a.attention).length;
                final emptyCount = answers.where((a) => a.isEmpty).length;

                return InkWell(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFFf0f0f0)
                          : Colors.white,
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFFe0e0e0)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: _isSidePanelOpen
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? const Color(0xFF333333)
                                : const Color(0xFFe0e0e0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: _currentPage == index
                                    ? Colors.white
                                    : const Color(0xFF424242),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (_isSidePanelOpen) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  report.questions[index].text.isNotEmpty
                                      ? report.questions[index].text
                                      : 'Вопрос ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (answerCount > 0)
                                      Text(
                                        '💬 $answerCount',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF666666),
                                        ),
                                      ),
                                    if (attentionCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '⚠️ $attentionCount',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFf59e0b),
                                        ),
                                      ),
                                    ],
                                    if (emptyCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '○ $emptyCount',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF999999),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(ReportState reportState, Report report) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ListView.builder(
        itemCount: report.questions.length,
        itemBuilder: (context, index) =>
            _buildQuestionCard(context, index, reportState, false),
      ),
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
    final answers = report.answers[index.toString()] ?? [Answer()];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      constraints: isCardView ? const BoxConstraints(maxWidth: 600) : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(width: 1, color: const Color(0xFFcccccc)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFe0e0e0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF424242),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _getQuestionController(index, q.text),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color(0xFF424242),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Введите вопрос...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (text) =>
                      reportState.updateQuestionText(index, text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...answers.asMap().entries.map(
            (entry) => _buildAnswerItem(
              context,
              index,
              entry.key,
              entry.value,
              reportState,
            ),
          ),
          if (!isCardView) ...[
            const SizedBox(height: 8),
            _buildSmallButton(
              '➕ Добавить ответ',
              () => reportState.addAnswer(index),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerItem(
    BuildContext context,
    int questionIndex,
    int answerIndex,
    Answer answer,
    ReportState reportState,
  ) {
    final qid = questionIndex.toString();
    final isAttention = answer.attention;
    final answers = reportState.currentReport!.answers[qid]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isAttention ? const Color(0xFFfffbeb) : const Color(0xFFf9f9f9),
        border: Border.all(
          color: isAttention
              ? const Color(0xFFf59e0b)
              : const Color(0xFFdddddd),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _answerControllers[qid]![answerIndex],
                  maxLines: null,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF424242),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Введите ответ...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  InkWell(
                    onTap: () => reportState.updateAnswerAttention(
                      questionIndex,
                      answerIndex,
                      !isAttention,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isAttention
                            ? const Color(0xFFfef3c7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF999999),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isAttention
                                ? const Color(0xFFd97706)
                                : const Color(0xFF999999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (answers.length > 1) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () =>
                          reportState.removeAnswer(questionIndex, answerIndex),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFfee2e2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFdc2626),
                            width: 1,
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            '×',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFFdc2626),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (answer.media.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: answer.media.length,
                itemBuilder: (ctx, mediaIndex) {
                  final media = answer.media[mediaIndex];
                  return Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFcccccc),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: media.type.startsWith('image')
                              ? (!kIsWeb && media.localPath != null
                                    ? Image.file(
                                        File(media.localPath!),
                                        width: 80,
                                        height: 80,
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
                                ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => reportState.removeMedia(
                              questionIndex,
                              answerIndex,
                              mediaIndex,
                            ),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFFdc2626),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: Text(
                                  '×',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          _buildSquareMediaButton(
            questionIndex,
            answerIndex,
            reportState,
            answer.attention,
          ),
        ],
      ),
    );
  }

  Widget _buildSquareMediaButton(
    int questionIndex,
    int answerIndex,
    ReportState reportState,
    bool isAttention,
  ) {
    return InkWell(
      onTap: () => _showMediaPicker(
        context,
        questionIndex,
        answerIndex,
        reportState,
        isAttention,
      ),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFe8e8e8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFcccccc), width: 1),
        ),
        child: const Center(
          child: Icon(Icons.add_a_photo, size: 22, color: Color(0xFF666666)),
        ),
      ),
    );
  }

  Widget _buildSmallButton(String text, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFe8e8e8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: Color(0xFF424242)),
        ),
      ),
    );
  }

  Future<void> _showMediaPicker(
    BuildContext context,
    int questionIndex,
    int answerIndex,
    ReportState reportState,
    bool isAttention,
  ) async {
    final picker = ImagePicker();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Выбрать фото из галереи'),
              onTap: () async {
                Navigator.pop(ctx);
                final images = await picker.pickMultiImage();
                for (final image in images) {
                  if (!kIsWeb) {
                    await reportState.addMedia(
                      questionIndex,
                      answerIndex,
                      File(image.path),
                      isAttention,
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Сделать фото'),
              onTap: () async {
                Navigator.pop(ctx);
                final image = await picker.pickImage(
                  source: ImageSource.camera,
                );
                if (image != null && !kIsWeb) {
                  await reportState.addMedia(
                    questionIndex,
                    answerIndex,
                    File(image.path),
                    isAttention,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Выбрать видео'),
              onTap: () async {
                Navigator.pop(ctx);
                final video = await picker.pickVideo(
                  source: ImageSource.gallery,
                );
                if (video != null && !kIsWeb) {
                  await reportState.addMedia(
                    questionIndex,
                    answerIndex,
                    File(video.path),
                    isAttention,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Снять видео'),
              onTap: () async {
                Navigator.pop(ctx);
                final video = await picker.pickVideo(
                  source: ImageSource.camera,
                );
                if (video != null && !kIsWeb) {
                  await reportState.addMedia(
                    questionIndex,
                    answerIndex,
                    File(video.path),
                    isAttention,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoThumbnailWidget extends StatefulWidget {
  final String? localPath;

  const _VideoThumbnailWidget({this.localPath});

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
        maxWidth: 80,
        maxHeight: 80,
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
        width: 80,
        height: 80,
        fit: BoxFit.cover,
      );
    }
    return const Center(
      child: Icon(Icons.videocam, size: 30, color: Color(0xFF999999)),
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
