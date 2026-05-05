
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

  void newReport(String name, List<Question> questions, List<String> languages) {
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
    final newIndex = index == null ? _currentReport!.questions.length : index + 1;
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

  void updateQuestionLocalization(int index, String langCode, String? name, String? description, String? example) {
    if (_currentReport == null || index >= _currentReport!.questions.length) return;
    final loc = _currentReport!.questions[index].localizations[langCode] ?? QuestionLocalization();
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
    final lang = _currentReport!.currentLanguage;

    if (_currentReport!.answers.containsKey(qid) &&
        _currentReport!.answers[qid]!.containsKey(lang) &&
        _currentReport!.answers[qid]![lang]!.length > 1) {
      _currentReport!.answers[qid]![lang]!.removeAt(answerIndex);
      notifyListeners();
    }
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
          _currentReport!.answers[qid]![otherLang]![answerIndex].isEmpty = true;
        }
      }
    }

    if (_currentReport!.answers.containsKey(qid) &&
        _currentReport!.answers[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.answers[qid]![lang]!.length) {
      _currentReport!.answers[qid]![lang]![answerIndex].text = text;
      _currentReport!.answers[qid]![lang]![answerIndex].isEmpty =
          text.isEmpty && _currentReport!.answers[qid]![lang]![answerIndex].media.isEmpty;
      notifyListeners();
    }
  }

  void updateAnswerAttention(int questionIndex, int answerIndex, bool attention) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;
    if (_currentReport!.answers.containsKey(qid) &&
        _currentReport!.answers[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.answers[qid]![lang]!.length) {
      _currentReport!.answers[qid]![lang]![answerIndex].attention = attention;
      notifyListeners();
    }
  }

  Future<void> addMedia(int questionIndex, int answerIndex, File file, bool isAttention) async {
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
        answerIndex >= _currentReport!.answers[qid]![lang]!.length) return;

    final counter = isAttention ? _currentReport!.mediaCounter['X']! : _currentReport!.mediaCounter['photos']!;
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
    _currentReport!.answers[qid]![lang]![answerIndex].isEmpty = false;

    if (isAttention) {
      _currentReport!.mediaCounter['X'] = counter + 1;
    } else {
      _currentReport!.mediaCounter['photos'] = counter + 1;
    }

    notifyListeners();
  }

  Future<void> removeMedia(int questionIndex, int answerIndex, int mediaIndex) async {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;
    if (!_currentReport!.answers.containsKey(qid) ||
        !_currentReport!.answers[qid]!.containsKey(lang) ||
        answerIndex >= _currentReport!.answers[qid]![lang]!.length ||
        mediaIndex >= _currentReport!.answers[qid]![lang]![answerIndex].media.length) return;

    final media = _currentReport!.answers[qid]![lang]![answerIndex].media[mediaIndex];
    if (_currentReportPath != null && media.localPath != null) {
      final file = File(media.localPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _currentReport!.answers[qid]![lang]![answerIndex].media.removeAt(mediaIndex);
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
              final dateTime = timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : DateTime.now();
              reports.add(ReportInfo(
                folderName: entity.path,
                name: name,
                dateTime: dateTime,
              ));
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
    return '$folderPath/report.html';
  }

  String _generateHtml() {
    if (_currentReport == null) return '<html><body>Нет отчёта</body></html>';
    final lang = _currentReport!.currentLanguage;
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="ru">');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln('  <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('  <title>${_currentReport!.reportName}</title>');
    buffer.writeln('  <style>');
    buffer.writeln('    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f8f7f2; }');
    buffer.writeln('    .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border: 2px solid #333; border-radius: 12px; }');
    buffer.writeln('    h1 { color: #424242; margin-bottom: 10px; }');
    buffer.writeln('    .lang-indicator { color: #666; font-size: 14px; margin-bottom: 5px; }');
    buffer.writeln('    .date { color: #666; margin-bottom: 30px; }');
    buffer.writeln('    .question { margin: 20px 0; padding: 15px; background: #f5f5f5; border: 1px solid #333; border-radius: 8px; }');
    buffer.writeln('    .question h3 { margin: 0 0 10px 0; color: #424242; }');
    buffer.writeln('    .description { color: #666; font-size: 14px; margin-bottom: 10px; }');
    buffer.writeln('    .example { color: #666; font-size: 13px; font-style: italic; margin-bottom: 15px; }');
    buffer.writeln('    .answer { color: #333; font-size: 16px; margin-bottom: 10px; padding: 10px; border-radius: 4px; }');
    buffer.writeln('    .answer.attention { background: #fffbeb; border: 1px solid #f59e0b; }');
    buffer.writeln('    .media { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; }');
    buffer.writeln('    .media img { max-width: 100px; max-height: 100px; border: 1px solid #333; border-radius: 4px; }');
    buffer.writeln('    .media .video { width: 100px; height: 100px; display: flex; align-items: center; justify-content: center; background: #e0e0e0; border: 1px solid #333; border-radius: 4px; font-size: 24px; }');
    buffer.writeln('    .translation-hint { background: #fff3cd; border: 1px solid #ffc107; padding: 10px; border-radius: 4px; margin-bottom: 10px; font-size: 14px; color: #856404; }');
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('  <div class="container">');
    buffer.writeln('    <h1>${_currentReport!.reportName}</h1>');
    buffer.writeln('    <div class="lang-indicator">Язык: $lang</div>');
    buffer.writeln('    <div class="date">${DateTime.fromMillisecondsSinceEpoch(_currentReport!.timestamp).toLocal().toString().substring(0, 16)}</div>');
    buffer.writeln('    <div class="questions">');
    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final q = _currentReport!.questions[i];
      final loc = q.getLocalization(lang);
      final hasTranslation = q.hasTranslation(lang);
      final hasSome = q.hasSomeTranslation();
      final answers = _currentReport!.getAnswersForQuestion(i, lang);
      buffer.writeln('      <div class="question">');
      if (!hasTranslation && hasSome) {
        final otherLangs = q.getAvailableLanguages().where((l) => l != lang).join(', ');
        buffer.writeln('        <div class="translation-hint">Перевод на $lang отсутствует. Доступно на: $otherLangs</div>');
      }
      buffer.writeln('        <h3>${loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}'}</h3>');
      if (loc?.description?.isNotEmpty ?? false) {
        buffer.writeln('        <div class="description">${loc?.description}</div>');
      }
      if (loc?.example?.isNotEmpty ?? false) {
        buffer.writeln('        <div class="example">Пример: ${loc?.example}</div>');
      }
      for (int j = 0; j < answers.length; j++) {
        final a = answers[j];
        buffer.writeln('        <div class="answer${a.attention ? ' attention' : ''}">');
        if (a.text.isNotEmpty) {
          buffer.writeln('          <div>${a.text}</div>');
        }
        if (a.media.isNotEmpty) {
          buffer.writeln('          <div class="media">');
          for (final media in a.media) {
            final folder = media.attention ? 'X' : 'photos';
            if (media.type.startsWith('image')) {
              buffer.writeln('            <img src="$folder/${media.name}" alt="${media.name}">');
            } else {
              buffer.writeln('            <div class="video">🎥</div>');
            }
          }
          buffer.writeln('          </div>');
        }
        buffer.writeln('        </div>');
      }
      buffer.writeln('      </div>');
    }
    buffer.writeln('    </div>');
    buffer.writeln('  </div>');
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
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('Вопрос ($lang)');
    sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue('Расшифровка ($lang)');
    sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('Ответ');
    sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue('Внимание');
    sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue('Медиа');
    row++;

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final q = _currentReport!.questions[i];
      final loc = q.getLocalization(lang);
      final answers = _currentReport!.getAnswersForQuestion(i, lang);

      for (int j = 0; j < answers.length; j++) {
        final a = answers[j];
        final mediaNames = a.media.map((m) => '${m.attention ? 'X' : 'photos'}/${m.name}').join('; ');

        if (j == 0) {
          sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(loc?.name ?? q.getDisplayName(lang) ?? '');
          sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(loc?.description ?? '');
        }
        sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(a.text);
        sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(a.attention ? 'Да' : 'Нет');
        sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue(mediaNames);
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
      
      // Row 0 is helper (ignored), Row 1 is language codes
      final langRow = rows[1];
      final languages = <String>[];
      final langColumns = <String, int>{}; // lang -> start column
      
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
          
          final name = (startCol < row.length && row[startCol]?.value != null) ? row[startCol]!.value.toString().trim() : '';
          final desc = (startCol + 1 < row.length && row[startCol + 1]?.value != null) ? row[startCol + 1]!.value.toString().trim() : '';
          final example = (startCol + 2 < row.length && row[startCol + 2]?.value != null) ? row[startCol + 2]!.value.toString().trim() : '';
          
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
      final safeName = _currentReport!.reportName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
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

        final hasAnswer = answers.any((a) => !a.isEmpty);
        if (hasAnswer) hasAnswerInAnyLang = true;
        if (!hasAnswer) hasEmptyInAnyLang = true;
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
        if (!answer.isEmpty) {
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

      final qIndex = _currentReport!.questions.indexWhere((q) => q.id == questionId);
      if (qIndex == -1) continue;

      final qid = qIndex.toString();
      if (!_currentReport!.answers.containsKey(qid)) {
        _currentReport!.answers[qid] = {};
      }

      for (final lang in languages) {
        if (!_currentReport!.availableLanguages.contains(lang)) continue;
        _currentReport!.answers[qid]![lang] = [];
      }

      for (final variant in variants) {
        final texts = (variant as List).cast<String>();
        for (int langIndex = 0; langIndex < languages.length; langIndex++) {
          final lang = languages[langIndex];
          if (!_currentReport!.availableLanguages.contains(lang)) continue;

          final text = langIndex < texts.length ? texts[langIndex] : '';
          final answersList = _currentReport!.answers[qid]![lang];
          if (answersList != null) {
            answersList.add(Answer()..text = text..isEmpty = text.isEmpty);
          }
        }
      }
    }

    notifyListeners();
  }
}

