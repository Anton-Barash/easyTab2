import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import '../models/report_models.dart';

const String reportFilename = 'report.json';
const String exportDir = 'reports';

const int maxLanguages = 5;

const Map<String, int> languagePriority = {'RU': 0, 'EN': 1, 'ZH': 2};

const Map<int, String> languageColors = {
  1: '#888888',
  2: '#27ae60',
  3: '#8e44ad',
  4: '#2c7da0',
};

List<String> sortLanguages(List<String> languages) {
  final sorted = List<String>.from(languages);
  sorted.sort((a, b) {
    final priorityA = languagePriority[a] ?? 999;
    final priorityB = languagePriority[b] ?? 999;
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }
    return a.compareTo(b);
  });
  if (sorted.length > maxLanguages) {
    return sorted.sublist(0, maxLanguages);
  }
  return sorted;
}

String getLanguageColor(int index) {
  if (index == 0) return '#888888';
  return languageColors[index] ?? '#888888';
}

class ReportInfo {
  final String folderName;
  final String name;
  final DateTime dateTime;

  ReportInfo({
    required this.folderName,
    required this.name,
    required this.dateTime,
  });
}

class ReportState extends ChangeNotifier {
  Report? _currentReport;
  String? _currentReportPath;

  Report? get currentReport => _currentReport;
  String? get currentReportPath => _currentReportPath;

  void newReport(
    String name,
    List<Question> questions,
    List<String> languages,
  ) {
    _currentReport = Report(
      reportName: name,
      availableLanguages: languages,
      currentLanguage: languages.isNotEmpty ? languages[0] : 'RU',
      questions: questions,
      answers: {},
      mediaCounter: {'photos': 1, 'X': 1},
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    for (int i = 0; i < questions.length; i++) {
      _currentReport!.answers[i.toString()] = {};
      for (final lang in languages) {
        _currentReport!.answers[i.toString()]![lang] = [Answer()];
      }
    }
    _currentReportPath = null;
    notifyListeners();
  }

  void setLanguage(String langCode) {
    if (_currentReport == null) return;
    if (_currentReport!.availableLanguages.contains(langCode)) {
      _currentReport!.currentLanguage = langCode;
      notifyListeners();
    }
  }

  void addQuestion([int? index]) {
    if (_currentReport == null) return;
    final newIndex = index == null
        ? _currentReport!.questions.length
        : index + 1;
    final newQuestion = Question(
      id: DateTime.now().millisecondsSinceEpoch,
      localizations: {},
    );
    for (final lang in _currentReport!.availableLanguages) {
      newQuestion.localizations[lang] = QuestionLocalization();
    }
    _currentReport!.questions.insert(newIndex, newQuestion);

    final newAnswers = <String, Map<String, List<Answer>>>{};
    _currentReport!.answers.forEach((key, langMap) {
      final k = int.parse(key);
      if (k >= newIndex) {
        newAnswers[(k + 1).toString()] = langMap;
      } else {
        newAnswers[key] = langMap;
      }
    });

    newAnswers[newIndex.toString()] = {};
    for (final lang in _currentReport!.availableLanguages) {
      newAnswers[newIndex.toString()]![lang] = [Answer()];
    }

    _currentReport!.answers = newAnswers;
    notifyListeners();
  }

  void updateQuestionLocalization(
    int index,
    String langCode,
    String? name,
    String? description,
    String? example,
  ) {
    if (_currentReport == null || index >= _currentReport!.questions.length)
      return;
    final loc =
        _currentReport!.questions[index].localizations[langCode] ??
        QuestionLocalization();
    if (name != null) loc.name = name;
    if (description != null) loc.description = description;
    if (example != null) loc.example = example;
    _currentReport!.questions[index].localizations[langCode] = loc;
    notifyListeners();
  }

  void addAnswer(int questionIndex) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;

    if (!_currentReport!.answers.containsKey(qid)) {
      _currentReport!.answers[qid] = {};
    }
    if (!_currentReport!.answers[qid]!.containsKey(lang)) {
      _currentReport!.answers[qid]![lang] = [Answer()];
    }
    _currentReport!.answers[qid]![lang]!.add(Answer());

    notifyListeners();
  }

  void removeAnswer(int questionIndex, int answerIndex) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    for (final lang in _currentReport!.availableLanguages) {
      if (_currentReport!.answers.containsKey(qid) &&
          _currentReport!.answers[qid]!.containsKey(lang) &&
          _currentReport!.answers[qid]![lang]!.length > 1) {
        // Delete media files if they exist
        final answer = _currentReport!.answers[qid]![lang]![answerIndex];
        for (final media in answer.media) {
          if (media.localPath != null && !kIsWeb) {
            try {
              final file = File(media.localPath!);
              if (file.existsSync()) {
                file.deleteSync();
              }
            } catch (e) {
              if (kDebugMode) print('Error deleting media file: $e');
            }
          }
        }
        _currentReport!.answers[qid]![lang]!.removeAt(answerIndex);
      }
    }

    notifyListeners();
  }

  void updateAnswerText(int questionIndex, int answerIndex, String text) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;

    if (text.isNotEmpty) {
      for (final otherLang in _currentReport!.availableLanguages) {
        if (otherLang == lang) continue;
        if (_currentReport!.answers.containsKey(qid) &&
            _currentReport!.answers[qid]!.containsKey(otherLang) &&
            answerIndex < _currentReport!.answers[qid]![otherLang]!.length) {
          _currentReport!.answers[qid]![otherLang]![answerIndex].text = '';
          final a = _currentReport!.answers[qid]![otherLang]![answerIndex];
          _currentReport!.answers[qid]![otherLang]![answerIndex].isEmpty =
              a.text.isEmpty && a.media.isEmpty && !a.attention;
        }
      }
    }

    if (_currentReport!.answers.containsKey(qid) &&
        _currentReport!.answers[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.answers[qid]![lang]!.length) {
      _currentReport!.answers[qid]![lang]![answerIndex].text = text;
      final a = _currentReport!.answers[qid]![lang]![answerIndex];
      _currentReport!.answers[qid]![lang]![answerIndex].isEmpty =
          a.text.isEmpty && a.media.isEmpty && !a.attention;
      notifyListeners();
    }
  }

  void updateAnswerAttention(
    int questionIndex,
    int answerIndex,
    bool attention,
  ) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    for (final lang in _currentReport!.availableLanguages) {
      if (_currentReport!.answers.containsKey(qid) &&
          _currentReport!.answers[qid]!.containsKey(lang) &&
          answerIndex < _currentReport!.answers[qid]![lang]!.length) {
        _currentReport!.answers[qid]![lang]![answerIndex].attention = attention;
        final a = _currentReport!.answers[qid]![lang]![answerIndex];
        _currentReport!.answers[qid]![lang]![answerIndex].isEmpty =
            a.text.isEmpty && a.media.isEmpty && !attention;
      }
    }
    notifyListeners();
  }

  Future<void> addMedia(
    int questionIndex,
    int answerIndex,
    File file,
    bool isAttention,
  ) async {
    if (_currentReport == null) return;

    if (_currentReportPath == null) {
      final folderPath = await _generateFolderName();
      _currentReportPath = folderPath;
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      await Directory('$folderPath/photos').create(recursive: true);
      await Directory('$folderPath/X').create(recursive: true);
    }

    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;
    if (!_currentReport!.answers.containsKey(qid) ||
        !_currentReport!.answers[qid]!.containsKey(lang) ||
        answerIndex >= _currentReport!.answers[qid]![lang]!.length)
      return;

    final counter = isAttention
        ? _currentReport!.mediaCounter['X']!
        : _currentReport!.mediaCounter['photos']!;
    final ext = file.path.split('.').last;
    final fileName = '${counter.toString().padLeft(3, '0')}.$ext';

    final folderName = isAttention ? 'X' : 'photos';
    final destFolder = Directory('$_currentReportPath/$folderName');
    if (!await destFolder.exists()) {
      await destFolder.create(recursive: true);
    }

    final destPath = File('${destFolder.path}/$fileName');
    await file.copy(destPath.path);

    final mediaItem = MediaItem(
      name: fileName,
      type: _getMimeType(file.path),
      attention: isAttention,
      originalName: file.path.split(Platform.pathSeparator).last,
      localPath: destPath.path,
    );

    _currentReport!.answers[qid]![lang]![answerIndex].media.add(mediaItem);
    final a = _currentReport!.answers[qid]![lang]![answerIndex];
    _currentReport!.answers[qid]![lang]![answerIndex].isEmpty =
        a.text.isEmpty && a.media.isEmpty && !a.attention;

    if (isAttention) {
      _currentReport!.mediaCounter['X'] = counter + 1;
    } else {
      _currentReport!.mediaCounter['photos'] = counter + 1;
    }

    notifyListeners();
  }

  Future<void> removeMedia(
    int questionIndex,
    int answerIndex,
    int mediaIndex,
  ) async {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;
    if (!_currentReport!.answers.containsKey(qid) ||
        !_currentReport!.answers[qid]!.containsKey(lang) ||
        answerIndex >= _currentReport!.answers[qid]![lang]!.length ||
        mediaIndex >=
            _currentReport!.answers[qid]![lang]![answerIndex].media.length)
      return;

    final media =
        _currentReport!.answers[qid]![lang]![answerIndex].media[mediaIndex];
    if (_currentReportPath != null && media.localPath != null) {
      final file = File(media.localPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _currentReport!.answers[qid]![lang]![answerIndex].media.removeAt(
      mediaIndex,
    );
    final a = _currentReport!.answers[qid]![lang]![answerIndex];
    _currentReport!.answers[qid]![lang]![answerIndex].isEmpty =
        a.text.isEmpty && a.media.isEmpty && !a.attention;
    notifyListeners();
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return 'image/$ext';
    } else if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return 'video/$ext';
    }
    return 'application/octet-stream';
  }

  Future<String> _getReportsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${appDir.path}/$exportDir');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir.path;
  }

  Future<String> _generateFolderName() async {
    final now = DateTime.now();
    final baseName = 'report_${now.millisecondsSinceEpoch}';
    final reportsDir = await _getReportsDir();
    return '$reportsDir/$baseName';
  }

  Future<bool> saveReport() async {
    if (_currentReport == null) return false;
    try {
      String folderPath;
      if (_currentReportPath == null) {
        folderPath = await _generateFolderName();
        _currentReportPath = folderPath;
      } else {
        folderPath = _currentReportPath!;
      }
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      await Directory('$folderPath/photos').create(recursive: true);
      await Directory('$folderPath/X').create(recursive: true);

      final jsonFile = File('$folderPath/$reportFilename');
      final jsonData = _currentReport!.toJson();
      await jsonFile.writeAsString(jsonEncode(jsonData));
      await _saveHtmlPreview(folderPath);
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error saving report: $e');
      return false;
    }
  }

  Future<bool> loadReport(String folderName) async {
    try {
      final folder = Directory(folderName);
      if (!await folder.exists()) return false;
      final jsonFile = File('${folder.path}/$reportFilename');
      if (!await jsonFile.exists()) return false;
      final jsonString = await jsonFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      _currentReport = Report.fromJson(jsonData, folderPath: folderName);
      _currentReportPath = folderName;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error loading report: $e');
      return false;
    }
  }

  Future<List<ReportInfo>> loadReportList() async {
    final reportsDir = await _getReportsDir();
    final dir = Directory(reportsDir);
    if (!await dir.exists()) return [];
    final List<ReportInfo> reports = [];
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final jsonFile = File('${entity.path}/$reportFilename');
          if (await jsonFile.exists()) {
            try {
              final jsonString = await jsonFile.readAsString();
              final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
              final name = jsonData['reportName'] as String? ?? 'Без названия';
              final timestamp = jsonData['timestamp'] as int?;
              final dateTime = timestamp != null
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                  : DateTime.now();
              reports.add(
                ReportInfo(
                  folderName: entity.path,
                  name: name,
                  dateTime: dateTime,
                ),
              );
            } catch (e) {
              continue;
            }
          }
        }
      }
      reports.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    } catch (e) {
      if (kDebugMode) print('Error loading report list: $e');
    }
    return reports;
  }

  Future<bool> deleteReport(String folderName) async {
    try {
      final folder = Directory(folderName);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('Error deleting report: $e');
      return false;
    }
  }

  Future<void> _saveHtmlPreview(String folderPath) async {
    if (_currentReport == null) return;
    final htmlContent = _generateHtml();
    final htmlFile = File('$folderPath/report.html');
    await htmlFile.writeAsString(htmlContent);
  }

  Future<String> getHtmlPreviewPath(String folderPath) async {
    final htmlContent = _generateHtml();
    final path = '$folderPath/report.html';
    final file = File(path);
    await file.writeAsString(htmlContent);
    return path;
  }

  String generateHtmlContent() {
    return _generateHtml();
  }

  String generateExcelHtmlContent() {
    return _generateExcelHtml();
  }

  String _generateHtml() {
    if (_currentReport == null) return '<html><body>Нет отчёта</body></html>';
    final reportName = _currentReport!.reportName;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      _currentReport!.timestamp,
    ).toLocal().toString().substring(0, 16);
    final allLanguages = _currentReport!.availableLanguages;
    final languages = sortLanguages(allLanguages);
    final buffer = StringBuffer();

    final List<String> allMediaData = [];
    final List<List<List<Map<String, dynamic>>>> allMediaByQandAandLang = [];

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final List<List<Map<String, dynamic>>> questionMedia = [];

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        final List<Map<String, dynamic>> langMedia = [];

        for (final a in answers) {
          for (final media in a.media) {
            final relativePath = media.attention ? 'X/${media.name}' : 'photos/${media.name}';
            final mediaMap = {
              'name': media.name,
              'type': media.type,
              'localPath': relativePath,
            };
            langMedia.add(mediaMap);
            allMediaData.add(jsonEncode(mediaMap));
          }
        }
        questionMedia.add(langMedia);
      }
      allMediaByQandAandLang.add(questionMedia);
    }

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="ru">');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln(
      '  <meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );
    buffer.writeln('  <title>${reportName} - Excel таблица</title>');
    buffer.writeln('  <style>');
    buffer.writeln('    * {');
    buffer.writeln('      margin: 0;');
    buffer.writeln('      padding: 0;');
    buffer.writeln('      box-sizing: border-box;');
    buffer.writeln('    }');
    buffer.writeln('    body {');
    buffer.writeln(
      '      font-family: \'Segoe UI\', \'Calibri\', \'Arial\', sans-serif;',
    );
    buffer.writeln('      background: #e9e9e9;');
    buffer.writeln('      padding: 20px;');
    buffer.writeln('    }');
    buffer.writeln('    .language-switcher {');
    buffer.writeln('      margin-bottom: 15px;');
    buffer.writeln('      display: flex;');
    buffer.writeln('      gap: 10px;');
    buffer.writeln('      flex-wrap: wrap;');
    buffer.writeln('    }');
    buffer.writeln('    .lang-btn {');
    buffer.writeln('      padding: 8px 16px;');
    buffer.writeln('      border: 1px solid #a0a0a0;');
    buffer.writeln('      background: white;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('      font-size: 14px;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('    }');
    buffer.writeln('    .lang-btn.active {');
    buffer.writeln('      background: #00B0F0;');
    buffer.writeln('      color: white;');
    buffer.writeln('      border-color: #00B0F0;');
    buffer.writeln('    }');
    buffer.writeln('    .excel-wrapper {');
    buffer.writeln('      background: white;');
    buffer.writeln('      border: 1px solid #a0a0a0;');
    buffer.writeln('      display: inline-block;');
    buffer.writeln('      box-shadow: 2px 2px 8px rgba(0,0,0,0.1);');
    buffer.writeln('    }');
    buffer.writeln('    table {');
    buffer.writeln('      border-collapse: collapse;');
    buffer.writeln('      font-size: 13px;');
    buffer.writeln('      table-layout: auto;');
    buffer.writeln('    }');
    buffer.writeln('    th, td {');
    buffer.writeln('      padding: 6px 10px;');
    buffer.writeln('      vertical-align: top;');
    buffer.writeln('      border-bottom: 1px solid #d0d0d0;');
    buffer.writeln('    }');
    buffer.writeln('    th {');
    buffer.writeln('      background: #f3f3f3;');
    buffer.writeln('      font-weight: 600;');
    buffer.writeln('      text-align: center;');
    buffer.writeln('      color: #2c2c2c;');
    buffer.writeln('    }');
    buffer.writeln('    .media-item {');
    buffer.writeln('      display: inline-block;');
    buffer.writeln('      margin: 2px;');
    buffer.writeln('      padding: 4px 8px;');
    buffer.writeln('      background: #f0f0f0;');
    buffer.writeln('      border: 1px solid #d0d0d0;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('      font-size: 12px;');
    buffer.writeln('    }');
    buffer.writeln('    .media-item:hover {');
    buffer.writeln('      background: #e0e0e0;');
    buffer.writeln('    }');
    buffer.writeln('    /* Modal styles */');
    buffer.writeln('    .modal {');
    buffer.writeln('      display: none;');
    buffer.writeln('      position: fixed;');
    buffer.writeln('      z-index: 1000;');
    buffer.writeln('      left: 0;');
    buffer.writeln('      top: 0;');
    buffer.writeln('      width: 100%;');
    buffer.writeln('      height: 100%;');
    buffer.writeln('      background-color: rgba(0,0,0,0.9);');
    buffer.writeln('      overflow: auto;');
    buffer.writeln('    }');
    buffer.writeln('    .modal.white-bg {');
    buffer.writeln('      background-color: rgba(255,255,255,0.95);');
    buffer.writeln('    }');
    buffer.writeln('    .modal-content {');
    buffer.writeln('      position: relative;');
    buffer.writeln('      margin: auto;');
    buffer.writeln('      top: 50%;');
    buffer.writeln('      transform: translateY(-50%);');
    buffer.writeln('      max-width: 90%;');
    buffer.writeln('      max-height: 90%;');
    buffer.writeln('      text-align: center;');
    buffer.writeln('    }');
    buffer.writeln('    .modal-img, .modal-video {');
    buffer.writeln('      max-width: 100%;');
    buffer.writeln('      max-height: 90vh;');
    buffer.writeln('      transition: transform 0.1s ease;');
    buffer.writeln('    }');
    buffer.writeln('    .close {');
    buffer.writeln('      position: absolute;');
    buffer.writeln('      top: 15px;');
    buffer.writeln('      right: 35px;');
    buffer.writeln('      color: #f1f1f1;');
    buffer.writeln('      font-size: 40px;');
    buffer.writeln('      font-weight: bold;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('      z-index: 1001;');
    buffer.writeln('    }');
    buffer.writeln('    .white-bg .close {');
    buffer.writeln('      color: #333;');
    buffer.writeln('    }');
    buffer.writeln('    .controls {');
    buffer.writeln('      position: fixed;');
    buffer.writeln('      bottom: 30px;');
    buffer.writeln('      left: 50%;');
    buffer.writeln('      transform: translateX(-50%);');
    buffer.writeln('      display: flex;');
    buffer.writeln('      gap: 15px;');
    buffer.writeln('      z-index: 1001;');
    buffer.writeln('    }');
    buffer.writeln('    .control-btn {');
    buffer.writeln('      padding: 12px 24px;');
    buffer.writeln('      font-size: 24px;');
    buffer.writeln('      background: rgba(0,0,0,0.6);');
    buffer.writeln('      color: white;');
    buffer.writeln('      border: 2px solid white;');
    buffer.writeln('      border-radius: 50%;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('      width: 60px;');
    buffer.writeln('      height: 60px;');
    buffer.writeln('      display: flex;');
    buffer.writeln('      align-items: center;');
    buffer.writeln('      justify-content: center;');
    buffer.writeln('    }');
    buffer.writeln('    .white-bg .control-btn {');
    buffer.writeln('      background: rgba(0,0,0,0.6);');
    buffer.writeln('      color: white;');
    buffer.writeln('      border-color: white;');
    buffer.writeln('    }');
    buffer.writeln('    .control-btn:hover {');
    buffer.writeln('      background: rgba(0,0,0,0.7);');
    buffer.writeln('    }');
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    buffer.writeln('<div class="language-switcher">');
    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      buffer.writeln(
        '  <button class="lang-btn ${li == 0 ? "active" : ""}" data-lang="$li" onclick="switchLanguage($li)">$lang</button>',
      );
    }
    buffer.writeln('</div>');

    buffer.writeln('<div class="excel-wrapper">');
    buffer.writeln('  <table>');
    buffer.writeln('    <tr>');
    buffer.writeln('      <th colspan="5">${reportName} | ${dateTime}</th>');
    buffer.writeln('    </tr>');

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final q = _currentReport!.questions[i];
      final questionNames = <String>[];
      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final loc = q.getLocalization(lang);
        questionNames.add(
          loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}',
        );
      }

      final List<List<Answer>> answersByLang = List.generate(
        languages.length,
        (_) => [],
      );

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);

        for (final a in answers) {
          if (a.text.isNotEmpty) {
            answersByLang[li].add(a);
          }
        }
      }

      final maxAnswers = answersByLang
          .map((l) => l.length)
          .reduce((a, b) => a > b ? a : b);

      final answerHasAttention = <bool>[];
      for (int ai = 0; ai < maxAnswers; ai++) {
        bool hasAtt = false;
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length &&
              answersByLang[li][ai].attention) {
            hasAtt = true;
          }
        }
        answerHasAttention.add(hasAtt);
      }

      String questionCellContent(int li) {
        return questionNames[li];
      }

      String answerCellContent(int ai, int li) {
        if (ai < answersByLang[li].length) {
          return answersByLang[li][ai].text;
        }
        return '';
      }

      String mediaCellContent(int ai, int li, int qIndex) {
        if (ai != 0) return '';

        final List<Map<String, dynamic>> mediaList =
            allMediaByQandAandLang[qIndex][li];
        final parts = <String>[];

        for (int mi = 0; mi < mediaList.length; mi++) {
          final media = mediaList[mi];
          final onClick = "openModal(${qIndex}, ${li}, ${mi})";
          parts.add(
            '<span class="media-item" onclick="$onClick">${media['name']}</span>',
          );
        }

        return parts.join('');
      }

      for (int ai = 0; ai < maxAnswers; ai++) {
        buffer.writeln('    <tr>');

        if (ai == 0) {
          buffer.writeln(
            '      <td style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
          );
        } else {
          buffer.writeln(
            '      <td style="background:#fafafa;width:40px;"></td>',
          );
        }

        if (ai == 0) {
          final qContentParts = <String>[];
          for (int li = 0; li < languages.length; li++) {
            final style = li == 0 ? '' : 'display:none;';
            qContentParts.add(
              '<span class="question-lang-$li" style="$style">${questionCellContent(li)}</span>',
            );
          }
          buffer.writeln(
            '      <td style="background:#fafafa;font-weight:500;width:160px;">${qContentParts.join('')}</td>',
          );
        } else {
          buffer.writeln(
            '      <td style="background:#fafafa;width:160px;"></td>',
          );
        }

        if (answerHasAttention[ai]) {
          buffer.writeln(
            '      <td style="text-align:center;vertical-align:middle;width:30px;background:#fff3cd;"><span style="font-weight:bold;color:#ef4444;">!</span></td>',
          );
        } else {
          buffer.writeln(
            '      <td style="text-align:center;vertical-align:middle;width:30px;"></td>',
          );
        }

        final aContentParts = <String>[];
        for (int li = 0; li < languages.length; li++) {
          final style = li == 0 ? '' : 'display:none;';
          aContentParts.add(
            '<span class="answer-lang-$li" style="$style">${answerCellContent(ai, li)}</span>',
          );
        }
        buffer.writeln(
          '      <td style="background:${answerHasAttention[ai] ? '#fff3cd' : 'white'};width:300px;">${aContentParts.join('')}</td>',
        );

        if (ai == 0) {
          final mContentParts = <String>[];
          for (int li = 0; li < languages.length; li++) {
            final style = li == 0 ? '' : 'display:none;';
            mContentParts.add(
              '<span class="media-lang-$li" style="$style">${mediaCellContent(ai, li, i)}</span>',
            );
          }
          buffer.writeln(
            '      <td style="background:#fafafa;width:200px;">${mContentParts.join('')}</td>',
          );
        } else {
          buffer.writeln(
            '      <td style="background:#fafafa;width:200px;"></td>',
          );
        }

        buffer.writeln('    </tr>');
      }
    }
    buffer.writeln('  </table>');
    buffer.writeln('</div>');

    // Modal
    buffer.writeln('<div id="mediaModal" class="modal">');
    buffer.writeln(
      '  <span class="close" onclick="closeModal()">&times;</span>',
    );
    buffer.writeln('  <div class="modal-content">');
    buffer.writeln(
      '    <img id="modalImg" class="modal-img" style="display:none;" />',
    );
    buffer.writeln(
      '    <video id="modalVideo" class="modal-video" controls style="display:none;"></video>',
    );
    buffer.writeln('  </div>');
    buffer.writeln('  <div class="controls">');
    buffer.writeln(
      '    <button class="control-btn" onclick="toggleBg()">⬜</button>',
    );
    buffer.writeln(
      '    <button class="control-btn" onclick="zoomOut()">&minus;</button>',
    );
    buffer.writeln(
      '    <button class="control-btn" onclick="fitToScreen()">⛶</button>',
    );
    buffer.writeln(
      '    <button class="control-btn" onclick="zoomIn()">+</button>',
    );
    buffer.writeln('  </div>');
    buffer.writeln('</div>');

    // JavaScript
    buffer.writeln('<script>');
    buffer.writeln('  let currentZoom = 1;');
    buffer.writeln('  let currentMedia = null;');
    buffer.writeln('  let currentElement = null;');
    buffer.writeln('  let isDragging = false;');
    buffer.writeln('  let startX = 0, startY = 0;');
    buffer.writeln('  let translateX = 0, translateY = 0;');
    buffer.writeln('  let isFitMode = false;');
    buffer.writeln('  let lastZoom = 1, lastTranslateX = 0, lastTranslateY = 0;');
    buffer.writeln('  let isWhiteBg = false;');
    buffer.writeln('  const allLanguages = ${jsonEncode(languages)};');

    // Media data
    buffer.writeln('  const mediaData = [');
    for (int i = 0; i < _currentReport!.questions.length; i++) {
      buffer.writeln('    [');
      for (int li = 0; li < languages.length; li++) {
        buffer.writeln('      [');
        for (int mi = 0; mi < allMediaByQandAandLang[i][li].length; mi++) {
          final media = allMediaByQandAandLang[i][li][mi];
          buffer.writeln('        ${jsonEncode(media)},');
        }
        buffer.writeln('      ],');
      }
      buffer.writeln('    ],');
    }
    buffer.writeln('  ];');

    buffer.writeln('  function switchLanguage(li) {');
    buffer.writeln('    // Update buttons');
    buffer.writeln(
      '    document.querySelectorAll(".lang-btn").forEach(btn => btn.classList.remove("active"));',
    );
    buffer.writeln(
      '    document.querySelector(\'.lang-btn[data-lang="\' + li + \'"]\').classList.add("active");',
    );

    buffer.writeln('    // Update content');
    buffer.writeln('    for (let l = 0; l < allLanguages.length; l++) {');
    buffer.writeln('      const display = l === li ? "" : "none";');
    buffer.writeln(
      '      document.querySelectorAll(".question-lang-" + l).forEach(el => el.style.display = display);',
    );
    buffer.writeln(
      '      document.querySelectorAll(".answer-lang-" + l).forEach(el => el.style.display = display);',
    );
    buffer.writeln(
      '      document.querySelectorAll(".media-lang-" + l).forEach(el => el.style.display = display);',
    );
    buffer.writeln('    }');
    buffer.writeln('  }');

    buffer.writeln('  function applyTransform(el) {');
    buffer.writeln('    el.style.transform = "translate(" + translateX + "px, " + translateY + "px) scale(" + currentZoom + ")";');
    buffer.writeln('  }');

    buffer.writeln('  function openModal(qIndex, li, mi) {');
    buffer.writeln('    const media = mediaData[qIndex][li][mi];');
    buffer.writeln('    const modal = document.getElementById("mediaModal");');
    buffer.writeln('    const modalImg = document.getElementById("modalImg");');
    buffer.writeln(
      '    const modalVideo = document.getElementById("modalVideo");',
    );

    buffer.writeln('    currentMedia = media;');
    buffer.writeln('    currentZoom = 1;');
    buffer.writeln('    translateX = 0;');
    buffer.writeln('    translateY = 0;');
    buffer.writeln('    isFitMode = false;');

    buffer.writeln('    if (media.type.startsWith("image")) {');
    buffer.writeln('      modalImg.style.display = "block";');
    buffer.writeln('      modalVideo.style.display = "none";');
    buffer.writeln('      modalImg.src = media.localPath;');
    buffer.writeln('      currentElement = modalImg;');
    buffer.writeln('    } else {');
    buffer.writeln('      modalImg.style.display = "none";');
    buffer.writeln('      modalVideo.style.display = "block";');
    buffer.writeln('      modalVideo.src = media.localPath;');
    buffer.writeln('      currentElement = modalVideo;');
    buffer.writeln('    }');
    buffer.writeln('    applyTransform(currentElement);');
    buffer.writeln('    modal.style.display = "block";');
    buffer.writeln('  }');

    buffer.writeln('  function closeModal() {');
    buffer.writeln(
      '    document.getElementById("mediaModal").style.display = "none";',
    );
    buffer.writeln('  }');

    buffer.writeln('  function zoomIn() {');
    buffer.writeln('    if (currentZoom < 3) {');
    buffer.writeln('      currentZoom += 0.2;');
    buffer.writeln('      applyTransform(currentElement);');
    buffer.writeln('    }');
    buffer.writeln('  }');

    buffer.writeln('  function zoomOut() {');
    buffer.writeln('    if (currentZoom > 0.3) {');
    buffer.writeln('      currentZoom -= 0.2;');
    buffer.writeln('      applyTransform(currentElement);');
    buffer.writeln('    }');
    buffer.writeln('  }');

    buffer.writeln('  function fitToScreen() {');
    buffer.writeln('    if (!isFitMode) {');
    buffer.writeln('      lastZoom = currentZoom;');
    buffer.writeln('      lastTranslateX = translateX;');
    buffer.writeln('      lastTranslateY = translateY;');
    buffer.writeln('      currentZoom = 1;');
    buffer.writeln('      translateX = 0;');
    buffer.writeln('      translateY = 0;');
    buffer.writeln('      isFitMode = true;');
    buffer.writeln('    } else {');
    buffer.writeln('      currentZoom = lastZoom;');
    buffer.writeln('      translateX = lastTranslateX;');
    buffer.writeln('      translateY = lastTranslateY;');
    buffer.writeln('      isFitMode = false;');
    buffer.writeln('    }');
    buffer.writeln('    applyTransform(currentElement);');
    buffer.writeln('  }');

    buffer.writeln('  function toggleBg() {');
    buffer.writeln('    const modal = document.getElementById("mediaModal");');
    buffer.writeln('    if (isWhiteBg) {');
    buffer.writeln('      modal.classList.remove("white-bg");');
    buffer.writeln('      isWhiteBg = false;');
    buffer.writeln('    } else {');
    buffer.writeln('      modal.classList.add("white-bg");');
    buffer.writeln('      isWhiteBg = true;');
    buffer.writeln('    }');
    buffer.writeln('  }');

    // Drag
    buffer.writeln('  document.addEventListener("mousedown", function(e) {');
    buffer.writeln('    if (e.target === currentElement) {');
    buffer.writeln('      e.preventDefault();');
    buffer.writeln('      isDragging = true;');
    buffer.writeln('      startX = e.clientX - translateX;');
    buffer.writeln('      startY = e.clientY - translateY;');
    buffer.writeln('    }');
    buffer.writeln('  });');

    buffer.writeln('  document.addEventListener("mousemove", function(e) {');
    buffer.writeln('    if (!isDragging || !currentElement) return;');
    buffer.writeln('    translateX = e.clientX - startX;');
    buffer.writeln('    translateY = e.clientY - startY;');
    buffer.writeln('    applyTransform(currentElement);');
    buffer.writeln('  });');

    buffer.writeln('  document.addEventListener("mouseup", function() {');
    buffer.writeln('    isDragging = false;');
    buffer.writeln('  });');

    // Wheel zoom
    buffer.writeln('  document.addEventListener("wheel", function(e) {');
    buffer.writeln('    if (currentElement && document.getElementById("mediaModal").style.display === "block") {');
    buffer.writeln('      e.preventDefault();');
    buffer.writeln('      const delta = e.deltaY > 0 ? -0.1 : 0.1;');
    buffer.writeln('      let newZoom = currentZoom + delta;');
    buffer.writeln('      if (newZoom > 3) newZoom = 3;');
    buffer.writeln('      if (newZoom < 0.3) newZoom = 0.3;');
    buffer.writeln('      currentZoom = newZoom;');
    buffer.writeln('      applyTransform(currentElement);');
    buffer.writeln('    }');
    buffer.writeln('  }, { passive: false });');

    // Close modal on background click
    buffer.writeln(
      '  document.getElementById("mediaModal").onclick = function(event) {',
    );
    buffer.writeln('    if (event.target === this) {');
    buffer.writeln('      closeModal();');
    buffer.writeln('    }');
    buffer.writeln('  }');

    // Close on escape key
    buffer.writeln('  document.onkeydown = function(event) {');
    buffer.writeln('    if (event.key === "Escape") {');
    buffer.writeln('      closeModal();');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln('</script>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  String _generateExcelHtml() {
    if (_currentReport == null) return '<html><body>Нет отчёта</body></html>';
    final reportName = _currentReport!.reportName;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      _currentReport!.timestamp,
    ).toLocal().toString().substring(0, 16);
    final allLanguages = _currentReport!.availableLanguages;
    final languages = sortLanguages(allLanguages);
    final langDisplay = languages.join(' / ');
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="ru">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );
    buffer.writeln('<title>${reportName} - Excel таблица</title>');
    buffer.writeln(
      '<style>table{border-collapse:collapse;font-size:13px;}th,td{padding:6px 10px;vertical-align:top;border-bottom:1px solid #d0d0d0;}th{background:#f3f3f3;font-weight:600;text-align:center;color:#2c2c2c;}</style>',
    );
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln(
      '<tr><th colspan="5">${reportName} | Язык: ${langDisplay} | ${dateTime}</th></tr>',
    );
    buffer.writeln('</thead>');
    buffer.writeln('<tbody>');

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final q = _currentReport!.questions[i];
      final questionNames = <String>[];
      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final loc = q.getLocalization(lang);
        questionNames.add(
          loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}',
        );
      }

      final List<String> allMediaNames = [];
      final List<List<Answer>> answersByLang = List.generate(
        languages.length,
        (_) => [],
      );

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);

        for (final a in answers) {
          if (a.text.isNotEmpty) {
            answersByLang[li].add(a);
          }
        }

        for (final a in answers) {
          for (final media in a.media) {
            allMediaNames.add(media.name);
          }
        }
      }

      final maxAnswers = answersByLang
          .map((l) => l.length)
          .reduce((a, b) => a > b ? a : b);

      final answerHasAttention = <bool>[];
      for (int ai = 0; ai < maxAnswers; ai++) {
        bool hasAtt = false;
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length &&
              answersByLang[li][ai].attention) {
            hasAtt = true;
          }
        }
        answerHasAttention.add(hasAtt);
      }

      final photoCellContent = allMediaNames.isNotEmpty
          ? allMediaNames.join(', ')
          : '';

      String questionCellContent() {
        final parts = <String>[];
        for (int li = 0; li < languages.length; li++) {
          if (li == 0) {
            parts.add(questionNames[li]);
          } else {
            final color = getLanguageColor(li);
            parts.add(
              '<span style="font-size:10px;color:$color;">${questionNames[li]}</span>',
            );
          }
        }
        return parts.join('<br>');
      }

      String answerCellContent(int ai) {
        final parts = <String>[];
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length) {
            final text = answersByLang[li][ai].text;
            if (li == 0) {
              parts.add('<div>$text</div>');
            } else {
              final color = getLanguageColor(li);
              parts.add(
                '<div style="font-size:10px;color:$color;">$text</div>',
              );
            }
          }
        }
        return parts.join('');
      }

      if (maxAnswers == 0) {
        buffer.writeln('<tr>');
        buffer.writeln(
          '<td style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
        );
        buffer.writeln(
          '<td style="background:#fafafa;font-weight:500;width:160px;">${questionCellContent()}</td>',
        );
        buffer.writeln('<td style="text-align:center;width:30px;"></td>');
        buffer.writeln('<td style="background:white;width:300px;"></td>');
        buffer.writeln('<td style="background:#fafafa;width:200px;"></td>');
        buffer.writeln('</tr>');
      } else {
        for (int ai = 0; ai < maxAnswers; ai++) {
          buffer.writeln('<tr>');

          if (ai == 0) {
            buffer.writeln(
              '<td rowspan="$maxAnswers" style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
            );
          }

          if (ai == 0) {
            buffer.writeln(
              '<td rowspan="$maxAnswers" style="background:#fafafa;font-weight:500;width:160px;">${questionCellContent()}</td>',
            );
          }

          if (answerHasAttention[ai]) {
            buffer.writeln(
              '<td style="text-align:center;vertical-align:middle;width:30px;background:#fff3cd;"><span style="font-weight:bold;color:#ef4444;">!</span></td>',
            );
          } else {
            buffer.writeln(
              '<td style="text-align:center;vertical-align:middle;width:30px;"></td>',
            );
          }

          buffer.writeln(
            '<td style="background:${answerHasAttention[ai] ? '#fff3cd' : 'white'};width:300px;">${answerCellContent(ai)}</td>',
          );

          buffer.writeln(
            '<td style="background:#fafafa;width:200px;">${ai == 0 ? photoCellContent : ''}</td>',
          );

          buffer.writeln('</tr>');
        }
      }
    }

    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  Uint8List _generateExcel() {
    if (_currentReport == null) return Uint8List(0);
    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    int row = 1;
    final lang = _currentReport!.currentLanguage;
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(
      'Вопрос ($lang)',
    );
    sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(
      'Расшифровка ($lang)',
    );
    sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('Ответ');
    sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(
      'Внимание',
    );
    sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue('Медиа');
    row++;

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final q = _currentReport!.questions[i];
      final loc = q.getLocalization(lang);
      final answers = _currentReport!.getAnswersForQuestion(i, lang);

      for (int j = 0; j < answers.length; j++) {
        final a = answers[j];
        final mediaNames = a.media
            .map((m) => '${m.attention ? 'X' : 'photos'}/${m.name}')
            .join('; ');

        if (j == 0) {
          sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(
            loc?.name ?? q.getDisplayName(lang) ?? '',
          );
          sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(
            loc?.description ?? '',
          );
        }
        sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(
          a.text,
        );
        sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(
          a.attention ? 'Да' : 'Нет',
        );
        sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue(
          mediaNames,
        );
        row++;
      }
    }

    return Uint8List.fromList(excel.encode()!);
  }

  Future<Report?> parseTemplate(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.sheets.values.first;

      final rows = sheet.rows;
      if (rows.length < 3) return null;

      final langRow = rows[1];
      final languages = <String>[];
      final langColumns = <String, int>{};

      for (int col = 0; col < langRow.length; col++) {
        final cell = langRow[col];
        if (cell != null && cell.value != null) {
          final lang = cell.value.toString().trim().toUpperCase();
          if (lang.isNotEmpty && !languages.contains(lang)) {
            languages.add(lang);
            langColumns[lang] = col;
          }
        }
      }

      if (languages.isEmpty) {
        languages.add('RU');
      }

      final questions = <Question>[];

      for (int rowIdx = 2; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        final question = Question(
          id: DateTime.now().millisecondsSinceEpoch + rowIdx,
          localizations: {},
        );

        bool hasData = false;

        for (final lang in languages) {
          final startCol = langColumns[lang];
          if (startCol == null) continue;

          final name = (startCol < row.length && row[startCol]?.value != null)
              ? row[startCol]!.value.toString().trim()
              : '';
          final desc =
              (startCol + 1 < row.length && row[startCol + 1]?.value != null)
              ? row[startCol + 1]!.value.toString().trim()
              : '';
          final example =
              (startCol + 2 < row.length && row[startCol + 2]?.value != null)
              ? row[startCol + 2]!.value.toString().trim()
              : '';

          question.localizations[lang] = QuestionLocalization(
            name: name.isEmpty ? null : name,
            description: desc.isEmpty ? null : desc,
            example: example.isEmpty ? null : example,
          );

          if (name.isNotEmpty || desc.isNotEmpty) {
            hasData = true;
          }
        }

        if (hasData) {
          questions.add(question);
        }
      }

      final report = Report(
        reportName: 'Новый отчёт',
        availableLanguages: languages,
        currentLanguage: languages[0],
        questions: questions,
        answers: {},
        mediaCounter: {'photos': 1, 'X': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      for (int i = 0; i < questions.length; i++) {
        report.answers[i.toString()] = {};
        for (final lang in languages) {
          report.answers[i.toString()]![lang] = [Answer()];
        }
      }

      return report;
    } catch (e) {
      if (kDebugMode) print('Error parsing template: $e');
      return null;
    }
  }

  Future<String?> exportZip() async {
    if (_currentReport == null || _currentReportPath == null) return null;
    try {
      await saveReport();

      final excelBytes = _generateExcel();
      final excelFile = File('$_currentReportPath/report.xlsx');
      await excelFile.writeAsBytes(excelBytes);

      final folderPath = _currentReportPath!;
      final reportsDir = await _getReportsDir();
      final safeName = _currentReport!.reportName
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(' ', '_');
      final zipPath = '$reportsDir/$safeName.zip';
      final zipFile = File(zipPath);
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      final dir = Directory(folderPath);
      await for (final entity in dir.list()) {
        if (entity is File) {
          encoder.addFile(entity, entity.uri.pathSegments.last);
        } else if (entity is Directory) {
          encoder.addDirectory(entity);
        }
      }
      encoder.close();
      return zipPath;
    } catch (e) {
      if (kDebugMode) print('Error exporting zip: $e');
      return null;
    }
  }

  Future<void> shareZip(String zipPath) async {
    if (kIsWeb) return;
    try {
      await Share.shareXFiles([XFile(zipPath)], text: 'EasyTab Report');
    } catch (e) {
      if (kDebugMode) print('Error sharing zip: $e');
    }
  }

  List<int> getUnsyncQuestionIndices() {
    if (_currentReport == null) return [];
    final unsyncIndices = <int>[];
    final languages = _currentReport!.availableLanguages;

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      bool hasAnswerInAnyLang = false;
      bool hasEmptyInAnyLang = false;
      bool hasDifferentCount = false;
      int? answerCount;

      for (final lang in languages) {
        final answers = _currentReport!.getAnswersForQuestion(i, lang);

        if (answerCount == null) {
          answerCount = answers.length;
        } else if (answerCount != answers.length) {
          hasDifferentCount = true;
        }

        final hasAnswer = answers.any((a) => a.text.isNotEmpty);
        if (hasAnswer) hasAnswerInAnyLang = true;
        final hasEmptyText = answers.any((a) => a.text.isEmpty);
        if (hasEmptyText) hasEmptyInAnyLang = true;
      }

      if (hasAnswerInAnyLang && hasEmptyInAnyLang || hasDifferentCount) {
        unsyncIndices.add(i);
      }
    }
    return unsyncIndices;
  }

  bool get needsSync {
    return getUnsyncQuestionIndices().isNotEmpty;
  }

  String generateSyncJson() {
    if (_currentReport == null) return '{}';
    final unsyncIndices = getUnsyncQuestionIndices();
    if (unsyncIndices.isEmpty) return '{}';

    final data = <String, dynamic>{
      'languages': _currentReport!.availableLanguages,
      'questions': <Map<String, dynamic>>[],
    };

    for (final idx in unsyncIndices) {
      final q = _currentReport!.questions[idx];
      final answerVariants = <List<String>>[];

      for (final lang in _currentReport!.availableLanguages) {
        final answers = _currentReport!.getAnswersForQuestion(idx, lang);
        for (int a = 0; a < answers.length; a++) {
          if (a >= answerVariants.length) {
            answerVariants.add([]);
          }
          final text = answers[a].text;
          answerVariants[a].add(text);
        }
      }

      (data['questions'] as List).add({
        'id': q.id,
        'answer_variants': answerVariants,
      });
    }

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Map<String, dynamic>? validateSyncJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (!data.containsKey('languages')) return null;
      if (!data.containsKey('questions')) return null;

      final languages = (data['languages'] as List).cast<String>();
      final questions = data['questions'] as List;

      for (final q in questions) {
        if (q is! Map) return null;
        if (!q.containsKey('id')) return null;
        if (!q.containsKey('answer_variants')) return null;

        final variants = q['answer_variants'] as List;
        for (final variant in variants) {
          if (variant is! List) return null;
          if ((variant as List).length != languages.length) return null;
        }
      }

      return data;
    } catch (e) {
      return null;
    }
  }

  void clearAnswersInLanguage(String langCode) {
    if (_currentReport == null) return;

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final qid = i.toString();
      if (_currentReport!.answers.containsKey(qid) &&
          _currentReport!.answers[qid]!.containsKey(langCode)) {
        _currentReport!.answers[qid]![langCode] = [Answer()];
      }
    }
    notifyListeners();
  }

  bool hasAnswersInOtherLanguages(int questionIndex, int answerIndex) {
    if (_currentReport == null) return false;
    final qid = questionIndex.toString();
    final currentLang = _currentReport!.currentLanguage;

    if (!_currentReport!.answers.containsKey(qid)) return false;

    for (final lang in _currentReport!.availableLanguages) {
      if (lang == currentLang) continue;
      if (_currentReport!.answers[qid]!.containsKey(lang) &&
          answerIndex < _currentReport!.answers[qid]![lang]!.length) {
        final answer = _currentReport!.answers[qid]![lang]![answerIndex];
        if (answer.text.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  void applySyncAnswers(String jsonStr) {
    if (_currentReport == null) return;
    final data = validateSyncJson(jsonStr);
    if (data == null) return;

    final languages = (data['languages'] as List).cast<String>();
    final questions = data['questions'] as List;

    for (final qData in questions) {
      final questionId = qData['id'] as int;
      final variants = qData['answer_variants'] as List;

      final qIndex = _currentReport!.questions.indexWhere(
        (q) => q.id == questionId,
      );
      if (qIndex == -1) continue;

      final qid = qIndex.toString();
      if (!_currentReport!.answers.containsKey(qid)) {
        _currentReport!.answers[qid] = {};
      }

      // Collect all attention flags across all languages for this question
      final allAttentionFlags = <List<bool>>[];
      for (final lang in _currentReport!.availableLanguages) {
        if (_currentReport!.answers[qid]!.containsKey(lang)) {
          allAttentionFlags.add(
            _currentReport!.answers[qid]![lang]!.map((a) => a.attention).toList()
          );
        }
      }
      // Determine for each answer index: is there ANY language with attention=true?
      final maxAnswers = allAttentionFlags.fold<int>(
        0,
        (max, list) => list.length > max ? list.length : max
      );
      final shouldHaveAttention = List.filled(maxAnswers, false);
      for (int i = 0; i < maxAnswers; i++) {
        for (final flags in allAttentionFlags) {
          if (i < flags.length && flags[i]) {
            shouldHaveAttention[i] = true;
            break;
          }
        }
      }

      // Save existing media lists before clearing answers
      final savedMedia = <String, List<List<MediaItem>>>{};
      for (final lang in _currentReport!.availableLanguages) {
        if (_currentReport!.answers[qid]!.containsKey(lang)) {
          final existingAnswers = _currentReport!.answers[qid]![lang]!;
          savedMedia[lang] = existingAnswers.map((a) => a.media).toList();
        }
      }

      // Clear answers for all languages in sync data
      for (final lang in languages) {
        if (!_currentReport!.availableLanguages.contains(lang)) continue;
        _currentReport!.answers[qid]![lang] = [];
      }

      // Now restore answers, media, and apply consistent attention flags!
      for (
        int variantIndex = 0;
        variantIndex < variants.length;
        variantIndex++
      ) {
        final variant = variants[variantIndex];
        final texts = (variant as List).cast<String>();
        for (int langIndex = 0; langIndex < languages.length; langIndex++) {
          final lang = languages[langIndex];
          if (!_currentReport!.availableLanguages.contains(lang)) continue;

          final text = langIndex < texts.length ? texts[langIndex] : '';
          final answersList = _currentReport!.answers[qid]![lang];
          if (answersList != null) {
            // Get saved media for this answer index
            List<MediaItem> media = [];
            if (savedMedia.containsKey(lang) &&
                variantIndex < savedMedia[lang]!.length) {
              media = savedMedia[lang]![variantIndex];
            }

            // Get consistent attention flag
            bool attention = variantIndex < shouldHaveAttention.length
                ? shouldHaveAttention[variantIndex]
                : false;

            answersList.add(
              Answer()
                ..text = text
                ..attention = attention
                ..media = media
                ..isEmpty = text.isEmpty && media.isEmpty && !attention,
            );
          }
        }
      }
    }

    notifyListeners();
  }
}
