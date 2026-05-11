import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel_community/excel_community.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import 'package:v_video_compressor/v_video_compressor.dart';
import '../models/report_models.dart';

const String reportFilename = 'report.json';
const String exportDir = 'reports';

const int maxLanguages = 5;

Uint8List _compressImage(Uint8List bytes, int maxSize) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    
    int width = image.width;
    int height = image.height;
    
    if (width <= maxSize && height <= maxSize) {
      return bytes;
    }
    
    double scale = maxSize / (width > height ? width : height);
    width = (width * scale).toInt();
    height = (height * scale).toInt();
    
    final resized = img.copyResize(image, width: width, height: height);
    return img.encodeJpg(resized, quality: 85);
  } catch (e) {
    return bytes;
  }
}

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

List<String> _groupMediaNames(List<String> mediaNames) {
  if (mediaNames.isEmpty) return [];
  
  final Map<String, List<int>> grouped = {};
  
  for (final name in mediaNames) {
    final prefix = name.substring(0, 1);
    final numStr = name.substring(1);
    if (int.tryParse(numStr) != null) {
      if (!grouped.containsKey(prefix)) {
        grouped[prefix] = [];
      }
      grouped[prefix]!.add(int.parse(numStr));
    } else {
      if (!grouped.containsKey('other')) {
        grouped['other'] = [];
      }
      grouped['other']!.add(mediaNames.indexOf(name));
    }
  }
  
  final result = <String>[];
  for (final entry in grouped.entries) {
    if (entry.key == 'other') {
      for (final idx in entry.value) {
        result.add(mediaNames[idx]);
      }
    } else {
      final nums = entry.value..sort();
      if (nums.length == 1) {
        result.add('${entry.key}${nums[0].toString().padLeft(3, '0')}');
      } else {
        result.add('${entry.key}${nums.first.toString().padLeft(3, '0')}-${nums.last.toString().padLeft(3, '0')}');
      }
    }
  }
  
  return result;
}

class ReportInfo {
  final String folderName;
  final String name;
  final DateTime dateTime;
  final String? thumbnailPath;

  ReportInfo({
    required this.folderName,
    required this.name,
    required this.dateTime,
    this.thumbnailPath,
  });
}

class ReportState extends ChangeNotifier {
  Report? _currentReport;
  String? _currentReportPath;
  final Set<String> _compressedVideoPaths = {};

  Report? get currentReport => _currentReport;
  String? get currentReportPath => _currentReportPath;

  void newReport(
    String name,
    List<Question> questions,
    List<String> languages, {
    String productType = 'Аэрогриль',
    String factory = '',
    String model = '',
    String? headerImagePath,
  }) {
    final now = DateTime.now();
    _currentReport = Report(
      reportName: name,
      availableLanguages: languages,
      currentLanguage: languages.isNotEmpty ? languages[0] : 'RU',
      questions: questions,
      translations: {},
      markers: {},
      mediaCounter: {'photos': 1, 'X': 1},
      timestamp: now.millisecondsSinceEpoch,
      productType: productType,
      factory: factory,
      model: model,
      dateTimestamp: now.millisecondsSinceEpoch,
      headerImagePath: headerImagePath,
    );
    for (int i = 0; i < questions.length; i++) {
      _currentReport!.translations[i.toString()] = {};
      _currentReport!.markers[i.toString()] = [AnswerMarkers()];
      for (final lang in languages) {
        _currentReport!.translations[i.toString()]![lang] = [
          TranslationAnswer(),
        ];
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

  void updateHeaderInfo({
    String? productType,
    String? factory,
    String? model,
    int? dateTimestamp,
  }) {
    if (_currentReport == null) return;
    if (productType != null) _currentReport!.productType = productType;
    if (factory != null) _currentReport!.factory = factory;
    if (model != null) _currentReport!.model = model;
    if (dateTimestamp != null) _currentReport!.dateTimestamp = dateTimestamp;
    notifyListeners();
  }

  void updateReportName() {
    if (_currentReport == null) return;
    final productType = _currentReport!.productType.isNotEmpty 
        ? '(${_currentReport!.productType})' 
        : '';
    final factory = _currentReport!.factory.isNotEmpty 
        ? '${_currentReport!.factory} ' 
        : '';
    final model = _currentReport!.model.isNotEmpty 
        ? _currentReport!.model 
        : '';
    _currentReport!.reportName = '$factory$productType $model'.trim();
    notifyListeners();
  }

  Future<void> addHeaderImage(File file) async {
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

    final ext = file.path.split('.').last;
    final fileName = 'header.$ext';
    final destPath = File('$_currentReportPath/$fileName');

    if (_currentReport!.headerImagePath != null) {
      final oldFilePath = File('$_currentReportPath/${_currentReport!.headerImagePath}');
      if (await oldFilePath.exists()) {
        await oldFilePath.delete();
      }
    }

    final mimeType = _getMimeType(file.path);
    if (mimeType.startsWith('image/')) {
      final bytes = await file.readAsBytes();
      final compressed = _compressImage(bytes, 1024);
      await destPath.writeAsBytes(compressed);
    } else {
      await file.copy(destPath.path);
    }

    _currentReport!.headerImagePath = fileName;
    notifyListeners();
  }

  Future<void> removeHeaderImage() async {
    if (_currentReport == null) return;
    if (_currentReportPath != null && _currentReport!.headerImagePath != null) {
      final absolutePath = '$_currentReportPath/${_currentReport!.headerImagePath}';
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentReport!.headerImagePath = null;
    notifyListeners();
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

    final newTranslations = <String, Map<String, List<TranslationAnswer>>>{};
    _currentReport!.translations.forEach((key, langMap) {
      final k = int.parse(key);
      if (k >= newIndex) {
        newTranslations[(k + 1).toString()] = langMap;
      } else {
        newTranslations[key] = langMap;
      }
    });

    final newMarkers = <String, List<AnswerMarkers>>{};
    _currentReport!.markers.forEach((key, markersList) {
      final k = int.parse(key);
      if (k >= newIndex) {
        newMarkers[(k + 1).toString()] = markersList;
      } else {
        newMarkers[key] = markersList;
      }
    });

    newTranslations[newIndex.toString()] = {};
    for (final lang in _currentReport!.availableLanguages) {
      newTranslations[newIndex.toString()]![lang] = [TranslationAnswer()];
    }
    newMarkers[newIndex.toString()] = [AnswerMarkers()];

    _currentReport!.translations = newTranslations;
    _currentReport!.markers = newMarkers;
    notifyListeners();
  }

  void removeQuestion(int index) {
    if (_currentReport == null) return;
    if (index < 0 || index >= _currentReport!.questions.length) return;

    _currentReport!.questions.removeAt(index);

    final newTranslations = <String, Map<String, List<TranslationAnswer>>>{};
    _currentReport!.translations.forEach((key, langMap) {
      final k = int.parse(key);
      if (k == index) {
        return;
      } else if (k > index) {
        newTranslations[(k - 1).toString()] = langMap;
      } else {
        newTranslations[key] = langMap;
      }
    });

    final newMarkers = <String, List<AnswerMarkers>>{};
    _currentReport!.markers.forEach((key, markersList) {
      final k = int.parse(key);
      if (k == index) {
        return;
      } else if (k > index) {
        newMarkers[(k - 1).toString()] = markersList;
      } else {
        newMarkers[key] = markersList;
      }
    });

    _currentReport!.translations = newTranslations;
    _currentReport!.markers = newMarkers;
    notifyListeners();
  }

  void updateQuestionLocalization(
    int index,
    String langCode,
    String? name,
    String? description,
    String? example,
  ) {
    if (_currentReport == null || index >= _currentReport!.questions.length) {
      return;
    }
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

    for (final lang in _currentReport!.availableLanguages) {
      if (!_currentReport!.translations.containsKey(qid)) {
        _currentReport!.translations[qid] = {};
      }
      if (!_currentReport!.translations[qid]!.containsKey(lang)) {
        _currentReport!.translations[qid]![lang] = [TranslationAnswer()];
      }
      _currentReport!.translations[qid]![lang]!.add(TranslationAnswer());
    }

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    _currentReport!.markers[qid]!.add(AnswerMarkers());

    notifyListeners();
  }

  void removeAnswer(int questionIndex, int answerIndex) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    for (final lang in _currentReport!.availableLanguages) {
      if (_currentReport!.translations.containsKey(qid) &&
          _currentReport!.translations[qid]!.containsKey(lang) &&
          _currentReport!.translations[qid]![lang]!.length > 1) {
        _currentReport!.translations[qid]![lang]!.removeAt(answerIndex);
      }
    }

    if (_currentReport!.markers.containsKey(qid) &&
        _currentReport!.markers[qid]!.length > 1) {
      final markers = _currentReport!.markers[qid]![answerIndex];
      for (final media in markers.media) {
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
      _currentReport!.markers[qid]!.removeAt(answerIndex);
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
        if (_currentReport!.translations.containsKey(qid) &&
            _currentReport!.translations[qid]!.containsKey(otherLang) &&
            answerIndex <
                _currentReport!.translations[qid]![otherLang]!.length) {
          _currentReport!.translations[qid]![otherLang]![answerIndex].text = '';
          _currentReport!.translations[qid]![otherLang]![answerIndex].isEmpty =
              true;
        }
      }
    }

    if (_currentReport!.translations.containsKey(qid) &&
        _currentReport!.translations[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.translations[qid]![lang]!.length) {
      _currentReport!.translations[qid]![lang]![answerIndex].text = text;
      _currentReport!.translations[qid]![lang]![answerIndex].isEmpty =
          text.isEmpty;
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

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    _currentReport!.markers[qid]![answerIndex].attention = attention;
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

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

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
    
    final mimeType = _getMimeType(file.path);
    if (mimeType.startsWith('image/')) {
      final bytes = await file.readAsBytes();
      final compressed = _compressImage(bytes, 1024);
      await destPath.writeAsBytes(compressed);
    } else {
      await file.copy(destPath.path);
    }

    final relativePath = '$folderName/$fileName';

    final mediaItem = MediaItem(
      name: fileName,
      type: _getMimeType(file.path),
      attention: isAttention,
      originalName: file.path.split(Platform.pathSeparator).last,
      localPath: relativePath,
      fileSize: await file.length(),
    );

    _currentReport!.markers[qid]![answerIndex].media.add(mediaItem);

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

    if (!_currentReport!.markers.containsKey(qid) ||
        answerIndex >= _currentReport!.markers[qid]!.length ||
        mediaIndex >= _currentReport!.markers[qid]![answerIndex].media.length) {
      return;
    }

    final media = _currentReport!.markers[qid]![answerIndex].media[mediaIndex];
    if (_currentReportPath != null && media.localPath != null) {
      final absolutePath = '$_currentReportPath/${media.localPath}';
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _currentReport!.markers[qid]![answerIndex].media.removeAt(mediaIndex);
    notifyListeners();
  }

  void updateAnswerNeedsWork(
    int questionIndex,
    int answerIndex,
    bool needsWork,
  ) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    _currentReport!.markers[qid]![answerIndex].needsWork = needsWork;
    notifyListeners();
  }

  bool hasAnswersInOtherLanguages(int questionIndex, int answerIndex) {
    return _currentReport?.hasAnswersInOtherLanguages(
          questionIndex,
          answerIndex,
        ) ??
        false;
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

  Future<void> compressAllVideos({
    required Function(int current, int total) onProgress,
  }) async {
    if (_currentReport == null || _currentReportPath == null) return;

    final List<String> videoPaths = [];

    // Collect all video paths
    for (final markerEntry in _currentReport!.markers.entries) {
      for (final answerMarker in markerEntry.value) {
        for (final media in answerMarker.media) {
          if (media.type.startsWith('video/') && media.localPath != null) {
            if (!videoPaths.contains(media.localPath)) {
              videoPaths.add(media.localPath!);
            }
          }
        }
      }
    }

    if (videoPaths.isEmpty) return;

    final compressor = VVideoCompressor();

    // Compress each video
    for (int i = 0; i < videoPaths.length; i++) {
      onProgress(i + 1, videoPaths.length);

      try {
        final relativePath = videoPaths[i];
        final absolutePath = '$_currentReportPath/$relativePath';
        final file = File(absolutePath);

        if (!await file.exists()) continue;

        final fileStat = await file.stat();
        // Skip if video is smaller than 5 MB
        if (fileStat.size < 5 * 1024 * 1024) continue;

        // Compress the video with stronger compression
        final result = await compressor.compressVideo(
          absolutePath,
          const VVideoCompressionConfig.low(),
          onProgress: (progress) {
            // We'll handle progress in the UI
          },
        );

        if (result != null) {
          // Replace original with compressed video
          final compressedFile = File(result.compressedFilePath);
          if (await compressedFile.exists()) {
            await compressedFile.copy(absolutePath);
            await compressedFile.delete();
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error compressing video: $e');
      }
    }
  }

  Future<List<String>> compressVideosWithSettings({
    required int qualityLevel,
    required Function(int current, int total) onProgress,
  }) async {
    if (_currentReport == null || _currentReportPath == null) return [];

    final List<String> compressedVideos = [];
    final List<String> videoPaths = [];

    for (final markerEntry in _currentReport!.markers.entries) {
      for (final answerMarker in markerEntry.value) {
        for (final media in answerMarker.media) {
          if (media.type.startsWith('video/') && media.localPath != null) {
            if (!videoPaths.contains(media.localPath)) {
              videoPaths.add(media.localPath!);
            }
          }
        }
      }
    }

    if (videoPaths.isEmpty) return [];

    final compressor = VVideoCompressor();
    VVideoCompressionConfig config;

    switch (qualityLevel) {
      case 1:
        config = const VVideoCompressionConfig.high();
        break;
      case 2:
        config = const VVideoCompressionConfig.medium();
        break;
      case 3:
      default:
        config = const VVideoCompressionConfig.low();
        break;
    }

    for (int i = 0; i < videoPaths.length; i++) {
      onProgress(i + 1, videoPaths.length);

      try {
        final relativePath = videoPaths[i];
        final absolutePath = '$_currentReportPath/$relativePath';
        
        if (_compressedVideoPaths.contains(relativePath)) {
          continue;
        }

        final file = File(absolutePath);
        if (!await file.exists()) continue;
        
        final fileSize = await file.length();
        if (fileSize <= 5 * 1024 * 1024) {
          continue;
        }

        final result = await compressor.compressVideo(
          absolutePath,
          config,
          onProgress: (progress) {},
        );

        if (result != null) {
          final compressedFile = File(result.compressedFilePath);
          if (await compressedFile.exists()) {
            final compressedSize = await compressedFile.length();
            await compressedFile.copy(absolutePath);
            await compressedFile.delete();
            _compressedVideoPaths.add(relativePath);
            compressedVideos.add(relativePath);
            
            for (final markerEntry in _currentReport!.markers.entries) {
              for (final answerMarker in markerEntry.value) {
                for (final media in answerMarker.media) {
                  if (media.localPath == relativePath) {
                    media.compressedSize = compressedSize;
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error compressing video: $e');
      }
    }

    return compressedVideos;
  }

  void resetCompressedVideos() {
    _compressedVideoPaths.clear();
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
      resetCompressedVideos();
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error loading report: $e');
      return false;
    }
  }

  Future<String?> importProjectFromZip(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        if (kDebugMode) print('ZIP file not found: $zipPath');
        return null;
      }

      final reportsDir = await _getReportsDir();
      final folderName = 'imported_${DateTime.now().millisecondsSinceEpoch}';
      final targetPath = '$reportsDir/$folderName';
      
      if (await Directory(targetPath).exists()) {
        await Directory(targetPath).delete(recursive: true);
      }
      await Directory(targetPath).create(recursive: true);

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.isFile) {
          final filePath = '$targetPath/${file.name}';
          final fileDir = Directory(filePath.substring(0, filePath.lastIndexOf('/')));
          if (!await fileDir.exists()) {
            await fileDir.create(recursive: true);
          }
          await File(filePath).writeAsBytes(file.content);
        }
      }

      final jsonFile = File('$targetPath/report.json');
      if (!await jsonFile.exists()) {
        await Directory(targetPath).delete(recursive: true);
        if (kDebugMode) print('report.json not found in ZIP');
        return null;
      }

      if (kDebugMode) print('Project imported successfully: $targetPath');
      return targetPath;
    } catch (e) {
      if (kDebugMode) print('Error importing project: $e');
      return null;
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
              final headerImagePath = jsonData['headerImagePath'] as String?;
              reports.add(
                ReportInfo(
                  folderName: entity.path,
                  name: name,
                  dateTime: dateTime,
                  thumbnailPath: headerImagePath,
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
          final mediaList = a['media'] as List? ?? [];
          for (final media in mediaList) {
            final relativePath = (media['attention'] == true)
                ? 'X/${media['name']}'
                : 'photos/${media['name']}';
            
            final mediaData = {
              'name': media['name'],
              'type': media['type'],
              'localPath': relativePath,
            };
            langMedia.add(mediaData);
            allMediaData.add(jsonEncode(mediaData));
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
    buffer.writeln('  <title>$reportName - Excel таблица</title>');
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
    buffer.writeln('    .media-thumbnails {');
    buffer.writeln('      display: flex;');
    buffer.writeln('      flex-wrap: wrap;');
    buffer.writeln('      gap: 4px;');
    buffer.writeln('    }');
    buffer.writeln('    .media-thumbnail {');
    buffer.writeln('      width: 50px;');
    buffer.writeln('      height: 50px;');
    buffer.writeln('      object-fit: cover;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('      border: 1px solid #d0d0d0;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('    }');
    buffer.writeln('    .media-more {');
    buffer.writeln('      display: flex;');
    buffer.writeln('      align-items: center;');
    buffer.writeln('      justify-content: center;');
    buffer.writeln('      width: 50px;');
    buffer.writeln('      height: 50px;');
    buffer.writeln('      background: #e0e0e0;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('      border: 1px solid #d0d0d0;');
    buffer.writeln('      font-size: 14px;');
    buffer.writeln('      font-weight: bold;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('    }');
    buffer.writeln('    /* Thumbnail grid modal */');
    buffer.writeln('    .thumbnail-grid-modal {');
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
    buffer.writeln('    .thumbnail-grid {');
    buffer.writeln('      display: grid;');
    buffer.writeln('      grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));');
    buffer.writeln('      gap: 10px;');
    buffer.writeln('      padding: 20px;');
    buffer.writeln('      max-width: 1000px;');
    buffer.writeln('      margin: 50px auto;');
    buffer.writeln('    }');
    buffer.writeln('    .thumbnail-grid-item {');
    buffer.writeln('      width: 100%;');
    buffer.writeln('      aspect-ratio: 1;');
    buffer.writeln('      object-fit: cover;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('      cursor: pointer;');
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
    buffer.writeln('    /* Header styles */');
    buffer.writeln('    .header-row {');
    buffer.writeln('      background: #ffffff !important;');
    buffer.writeln('      color: #6c757d;');
    buffer.writeln('      text-align: center;');
    buffer.writeln('    }');
    buffer.writeln('    .title {');
    buffer.writeln('      font-weight: bold;');
    buffer.writeln('      font-size: 18px;');
    buffer.writeln('    }');
    buffer.writeln('    .border-bold {');
    buffer.writeln('      border-bottom: 2px solid #6c757d !important;');
    buffer.writeln('      font-size: 18px;');
    buffer.writeln('    }');
    buffer.writeln('    .no-border {');
    buffer.writeln('      border-bottom: none !important;');
    buffer.writeln('      font-size: 14px;');
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

    final currentDate = DateTime.now().toLocal().toString().substring(0, 10).split('-').reversed.join('.');

    buffer.writeln('<div class="excel-wrapper">');
    buffer.writeln('  <table>');
    buffer.writeln('    <!-- 1 строка + жирная линия снизу ПО ВСЕЙ ШИРИНЕ -->');
    buffer.writeln('    <tr class="header-row">');
    buffer.writeln('      <td class="border-bold"></td>');
    buffer.writeln('      <td class="title border-bold">${_currentReport!.productType}</td>');
    buffer.writeln('      <td class="border-bold"></td>');
    buffer.writeln('      <td class="border-bold">Фабрика</td>');
    buffer.writeln('      <td class="border-bold">Модель</td>');
    buffer.writeln('    </tr>');
    buffer.writeln('    <!-- 2 строка + НЕТ линии снизу -->');
    final displayDate = _currentReport!.dateTimestamp != null 
        ? DateTime.fromMillisecondsSinceEpoch(_currentReport!.dateTimestamp!).toLocal().toString().substring(0, 10).split('-').reversed.join('.')
        : currentDate;
    buffer.writeln('    <tr class="header-row">');
    buffer.writeln('      <td class="no-border"></td>');
    buffer.writeln('      <td class="no-border">$displayDate</td>');
    buffer.writeln('      <td class="no-border"></td>');
    buffer.writeln('      <td class="no-border">${_currentReport!.factory}</td>');
    buffer.writeln('      <td class="no-border">${_currentReport!.model}</td>');
    buffer.writeln('    </tr>');
    buffer.writeln('    <!-- 3 строка: ОБЪЕДИНЕНА + ФОТО по центру -->');
    buffer.writeln('    <tr class="header-row">');
    buffer.writeln('      <td colspan="5" style="text-align:center; font-weight:bold; padding:8px; color:#6c757d; border-bottom:none;">ФОТО</td>');
    buffer.writeln('    </tr>');
    buffer.writeln('    <!-- Исходная шапка -->');
    buffer.writeln('    <tr>');
    buffer.writeln('      <th colspan="5">$reportName | $dateTime</th>');
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

      final List<List<Map<String, dynamic>>> answersByLang = List.generate(
        languages.length,
        (_) => [],
      );

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        answersByLang[li] = answers;
      }

      final maxAnswers = answersByLang
          .map((l) => l.length)
          .reduce((a, b) => a > b ? a : b);

      final answerHasAttention = <bool>[];
      for (int ai = 0; ai < maxAnswers; ai++) {
        bool hasAtt = false;
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length &&
              answersByLang[li][ai]['attention'] == true) {
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
          return answersByLang[li][ai]['text'] ?? '';
        }
        return '';
      }

      String mediaCellContent(int ai, int li, int qIndex) {
        if (ai != 0) return '';

        final List<Map<String, dynamic>> mediaList =
            allMediaByQandAandLang[qIndex][li];
        final parts = <String>[];

        const int maxVisible = 9;
        final visibleCount = mediaList.length > maxVisible ? maxVisible : mediaList.length;

        for (int mi = 0; mi < visibleCount; mi++) {
          final media = mediaList[mi];
          final onClick = "openModal($qIndex, $li, $mi)";
          final isImage = media['type'].startsWith('image');
          if (isImage) {
            parts.add(
              '<img class="media-thumbnail" src="${media['localPath']}" onclick="$onClick" alt="${media['name']}" />',
            );
          } else {
            parts.add(
              '<img class="media-thumbnail" src="${media['localPath']}" onclick="$onClick" alt="${media['name']}" onerror="this.src=\'data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2250%22 height=%2250%22 viewBox=%220 0 50 50%22><rect fill=%22%23e0e0e0%22 width=%2250%22 height=%2250%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2216%22>🎬</text></svg>\'" />',
            );
          }
        }

        if (mediaList.length > maxVisible) {
          final remaining = mediaList.length - maxVisible;
          parts.add(
            '<div class="media-more" onclick="openThumbnailGrid($qIndex, $li)">+$remaining</div>',
          );
        }

        return '<div class="media-thumbnails">${parts.join('')}</div>';
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

    // Thumbnail grid modal
    buffer.writeln('<div id="thumbnailGridModal" class="thumbnail-grid-modal">');
    buffer.writeln('  <span class="close" onclick="closeThumbnailGrid()">&times;</span>');
    buffer.writeln('  <div id="thumbnailGrid" class="thumbnail-grid">');
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
    buffer.writeln(
      '  let lastZoom = 1, lastTranslateX = 0, lastTranslateY = 0;',
    );
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
    buffer.writeln(
      '    el.style.transform = "translate(" + translateX + "px, " + translateY + "px) scale(" + currentZoom + ")";',
    );
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

    buffer.writeln('  let currentGridQIndex = 0;');
    buffer.writeln('  let currentGridLi = 0;');

    buffer.writeln('  function openThumbnailGrid(qIndex, li) {');
    buffer.writeln('    currentGridQIndex = qIndex;');
    buffer.writeln('    currentGridLi = li;');
    buffer.writeln('    const grid = document.getElementById("thumbnailGrid");');
    buffer.writeln('    grid.innerHTML = "";');
    buffer.writeln('    const media = mediaData[qIndex][li];');
    buffer.writeln('    for (let mi = 0; mi < media.length; mi++) {');
    buffer.writeln('      const item = media[mi];');
    buffer.writeln('      const isImage = item.type.startsWith("image");');
    buffer.writeln('      const img = document.createElement("img");');
    buffer.writeln('      img.className = "thumbnail-grid-item";');
    buffer.writeln('      img.src = item.localPath;');
    buffer.writeln('      img.alt = item.name;');
    buffer.writeln('      img.onclick = () => {');
    buffer.writeln('        closeThumbnailGrid();');
    buffer.writeln('        openModal(qIndex, li, mi);');
    buffer.writeln('      };');
    buffer.writeln('      if (!isImage) {');
    buffer.writeln('        img.onerror = () => {');
    buffer.writeln('          img.src = "data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22100%22 height=%22100%22 viewBox=%220 0 100 100%22><rect fill=%22%23e0e0e0%22 width=%22100%22 height=%22100%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2232%22>🎬</text></svg>";');
    buffer.writeln('        };');
    buffer.writeln('      }');
    buffer.writeln('      grid.appendChild(img);');
    buffer.writeln('    }');
    buffer.writeln('    document.getElementById("thumbnailGridModal").style.display = "block";');
    buffer.writeln('  }');

    buffer.writeln('  function closeThumbnailGrid() {');
    buffer.writeln('    document.getElementById("thumbnailGridModal").style.display = "none";');
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
    buffer.writeln(
      '    if (currentElement && document.getElementById("mediaModal").style.display === "block") {',
    );
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
    buffer.writeln('<title>$reportName - Excel таблица</title>');
    buffer.writeln(
      '<style>table{border-collapse:collapse;font-size:13px;}th,td{padding:6px 10px;vertical-align:top;border-bottom:1px solid #d0d0d0;}th{background:#f3f3f3;font-weight:600;text-align:center;color:#2c2c2c;}</style>',
    );
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln(
      '<tr><th colspan="5">$reportName | Язык: $langDisplay | $dateTime</th></tr>',
    );
    buffer.writeln(
      '<tr><td colspan="5" style="border-bottom:2px solid #6c757d;"></td></tr>',
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
      final List<List<Map<String, dynamic>>> answersByLang = List.generate(
        languages.length,
        (_) => [],
      );

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        answersByLang[li] = answers;

        for (final a in answers) {
          final media = a['media'] as List? ?? [];
          for (final m in media) {
            allMediaNames.add(m['name'] ?? '');
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
              answersByLang[li][ai]['attention'] == true) {
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
            parts.add(
              '<span style="font-size:10px;color:#888888;">${questionNames[li]}</span>',
            );
          }
        }
        return parts.join('<br>');
      }

      String answerCellContent(int ai) {
        final parts = <String>[];
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length) {
            final text = answersByLang[li][ai]['text'] ?? '';
            if (li == 0) {
              parts.add('<div>$text</div>');
            } else {
              parts.add(
                '<div style="font-size:10px;color:#888888;">$text</div>',
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
        buffer.writeln('<td style="text-align:center;vertical-align:middle;width:30px;"></td>');
        buffer.writeln('<td style="background:white;width:300px;">${answerCellContent(0)}</td>');
        buffer.writeln('<td style="background:#fafafa;width:200px;">$photoCellContent</td>');
        buffer.writeln('</tr>');
      } else {
        for (int ai = 0; ai < maxAnswers; ai++) {
          buffer.writeln('<tr>');
          buffer.writeln(
            '<td style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
          );
          buffer.writeln(
            '<td style="background:#fafafa;font-weight:500;width:160px;">${questionCellContent()}</td>',
          );

          if (answerHasAttention[ai]) {
            buffer.writeln(
              '<td style="text-align:center;vertical-align:middle;width:30px;background:#fff3cd;"><span style="font-weight:bold;color:#ef4444;">!</span></td>',
            );
          } else {
            buffer.writeln('<td style="text-align:center;vertical-align:middle;width:30px;"></td>');
          }

          final answerBgColor = answerHasAttention[ai] ? '#fff3cd' : 'white';
          buffer.writeln(
            '<td style="background:$answerBgColor;width:300px;">${answerCellContent(ai)}</td>',
          );

          buffer.writeln('<td style="background:#fafafa;width:200px;">$photoCellContent</td>');
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
    final sheet = excel['Sheet1'];

    final allLanguages = _currentReport!.availableLanguages;
    final languages = sortLanguages(allLanguages);

    final rowNumColor = ExcelColor.fromHexString('#00B0F0');
    final questionBgColor = ExcelColor.fromHexString('#fafafa');
    final attentionBgColor = ExcelColor.fromHexString('#fff3cd');
    final borderColor = ExcelColor.fromHexString('#6c757d');

    int row = 0;

    // 1-я строка шапки (заголовки: Аэрогриль, Фабрика, Модель)
    final headerStyle1Bold = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontColorHex: ExcelColor.fromHexString('#6c757d'),
      bold: true,
      fontSize: 12,
      fontFamily: 'Courier New',
      bottomBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black),
    );
    final headerStyle1Normal = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontColorHex: ExcelColor.fromHexString('#6c757d'),
      bold: false,
      fontSize: 12,
      fontFamily: 'Courier New',
      bottomBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(_currentReport!.productType);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = headerStyle1Bold;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue('Фабрика');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = headerStyle1Normal;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue('Модель');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).cellStyle = headerStyle1Normal;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontFamily: 'Courier New',
      bottomBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black),
    );
    row++;

    // 2-я строка шапки (значения: дата, factory, model)
    final headerStyle2 = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontColorHex: ExcelColor.fromHexString('#6c757d'),
      fontSize: 10,
      fontFamily: 'Courier New',
    );
    final excelDate = _currentReport!.dateTimestamp != null 
        ? DateTime.fromMillisecondsSinceEpoch(_currentReport!.dateTimestamp!).toLocal().toString().substring(0, 10).split('-').reversed.join('.')
        : DateTime.now().toLocal().toString().substring(0, 10).split('-').reversed.join('.');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(excelDate);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = headerStyle2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(_currentReport!.factory);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = headerStyle2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(_currentReport!.model);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).cellStyle = headerStyle2;
    row++;

    // 3-я строка шапки (ФОТО - объединенная ячейка)
    final totalColumns = 5; // A-E
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: totalColumns - 1, rowIndex: row),
    );
    final photoHeaderStyle = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontColorHex: ExcelColor.fromHexString('#6c757d'),
      bold: true,
      fontSize: 10,
      fontFamily: 'Courier New',
      horizontalAlign: HorizontalAlign.Center,
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('ФОТО');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = photoHeaderStyle;
    row++;

    // 4-я строка - пустая строка
    for (int col = 0; col < totalColumns; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3)).cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.white,
        fontFamily: 'Courier New',
      );
    }
    row++;

    // Таблица с данными
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

      final List<List<String>> mediaByAnswer = [];
      final List<List<Map<String, dynamic>>> answersByLang = List.generate(
        languages.length,
        (_) => [],
      );

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        answersByLang[li] = answers;

        for (int ai = 0; ai < answers.length; ai++) {
          final a = answers[ai];
          if (mediaByAnswer.length <= ai) {
            mediaByAnswer.add([]);
          }
          final media = a['media'] as List? ?? [];
          for (final m in media) {
            final name = m['name'] as String? ?? '';
            final attention = m['attention'] as bool? ?? false;
            if (name.isNotEmpty) {
              final prefix = attention ? 'x' : '';
              final ext = name.split('.').last.toLowerCase();
              final typePrefix = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext) ? 'f' : 'v';
              final num = name.split('.').first;
              mediaByAnswer[ai].add('$prefix$typePrefix$num');
            }
          }
        }
      }

      final maxAnswers = answersByLang
          .map((l) => l.length)
          .reduce((a, b) => a > b ? a : b);

      final List<String> photoCellContents = [];
      for (final mediaList in mediaByAnswer) {
        final grouped = _groupMediaNames(mediaList);
        photoCellContents.add(grouped.join(', '));
      }
      while (photoCellContents.length < maxAnswers) {
        photoCellContents.add('');
      }

      final answerHasAttention = <bool>[];
      for (int ai = 0; ai < maxAnswers; ai++) {
        bool hasAtt = false;
        for (int li = 0; li < languages.length; li++) {
          if (ai < answersByLang[li].length &&
              answersByLang[li][ai]['attention'] == true) {
            hasAtt = true;
          }
        }
        answerHasAttention.add(hasAtt);
      }

      final totalRows = maxAnswers * languages.length;

      if (maxAnswers == 0) {
        for (int li = 0; li < languages.length; li++) {
          final isLast = li == languages.length - 1;

          if (li == 0) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + languages.length - 1),
            );
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = IntCellValue(i + 1);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = CellStyle(
              backgroundColorHex: questionBgColor,
              fontColorHex: rowNumColor,
              bold: true,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
            );
          }

          final qColor = li == 0 ? ExcelColor.black : ExcelColor.fromHexString(getLanguageColor(li));
          final qFontSize = li == 0 ? 12 : 10;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(questionNames[li]);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = CellStyle(
            backgroundColorHex: questionBgColor,
            fontColorHex: qColor,
            fontSize: qFontSize,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
          );

          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue('');
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = CellStyle(
            backgroundColorHex: questionBgColor,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
          );

          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue('');
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = CellStyle(
            backgroundColorHex: ExcelColor.white,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
          );

          if (li == 0) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
              CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row + languages.length - 1),
            );
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue('');
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).cellStyle = CellStyle(
              backgroundColorHex: questionBgColor,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
            );
          }

          row++;
        }
      } else {
        for (int ai = 0; ai < maxAnswers; ai++) {
          for (int li = 0; li < languages.length; li++) {
            final isLast = ai == maxAnswers - 1 && li == languages.length - 1;

            if (li == 0 && ai == 0) {
              sheet.merge(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + totalRows - 1),
              );
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = IntCellValue(i + 1);
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = CellStyle(
                backgroundColorHex: questionBgColor,
                fontColorHex: rowNumColor,
                bold: true,
                fontFamily: 'Courier New',
                verticalAlign: VerticalAlign.Top,
                bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
              );
            }

            if (ai == 0) {
              final qColor = li == 0 ? ExcelColor.black : ExcelColor.fromHexString(getLanguageColor(li));
              final qFontSize = li == 0 ? 12 : 10;
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(questionNames[li]);
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = CellStyle(
                backgroundColorHex: questionBgColor,
                fontColorHex: qColor,
                fontSize: qFontSize,
                fontFamily: 'Courier New',
                verticalAlign: VerticalAlign.Top,
                bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
              );
            } else {
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue('');
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = CellStyle(
                backgroundColorHex: questionBgColor,
                fontFamily: 'Courier New',
                verticalAlign: VerticalAlign.Top,
                bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
              );
            }

            final hasAttentionMark = answerHasAttention[ai];
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = hasAttentionMark ? TextCellValue('!') : TextCellValue('');
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = CellStyle(
              backgroundColorHex: hasAttentionMark ? attentionBgColor : ExcelColor.white,
              fontColorHex: hasAttentionMark ? ExcelColor.fromHexString('#ef4444') : ExcelColor.black,
              bold: hasAttentionMark,
              fontFamily: 'Courier New',
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
            );

            final text = ai < answersByLang[li].length
                ? (answersByLang[li][ai]['text'] ?? '') as String
                : '';
            final hasAttention = answerHasAttention[ai];
            final answerBgColor = hasAttention ? attentionBgColor : ExcelColor.white;
            final aColor = li == 0 ? ExcelColor.black : ExcelColor.fromHexString(getLanguageColor(li));
            final aFontSize = li == 0 ? 12 : 10;
            
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(text);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = CellStyle(
              backgroundColorHex: answerBgColor,
              fontColorHex: aColor,
              fontSize: aFontSize,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
            );

            final photoBgColor = hasAttention ? attentionBgColor : questionBgColor;
            if (li == 0) {
              sheet.merge(
                CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
                CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row + languages.length - 1),
              );
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(photoCellContents[ai]);
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).cellStyle = CellStyle(
                backgroundColorHex: photoBgColor,
                fontColorHex: ExcelColor.fromHexString('#6c757d'),
                bold: true,
                fontSize: 10,
                fontFamily: 'Courier New',
                verticalAlign: VerticalAlign.Top,
              );
            }

            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).cellStyle = CellStyle(
              backgroundColorHex: photoBgColor,
              fontColorHex: ExcelColor.fromHexString('#6c757d'),
              bold: true,
              fontSize: 10,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast ? Border(borderStyle: BorderStyle.Thin, borderColorHex: borderColor) : null,
            );

            row++;
          }
        }
      }
    }

    sheet.setColumnWidth(0, 10);

    final bytes = excel.encode();
    return Uint8List.fromList(bytes!);
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
          final example =
              (startCol + 1 < row.length && row[startCol + 1]?.value != null)
              ? row[startCol + 1]!.value.toString().trim()
              : '';
          final desc =
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
        translations: {},
        markers: {},
        mediaCounter: {'photos': 1, 'X': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      for (int i = 0; i < questions.length; i++) {
        report.translations[i.toString()] = {};
        report.markers[i.toString()] = [AnswerMarkers()];
        for (final lang in languages) {
          report.translations[i.toString()]![lang] = [TranslationAnswer()];
        }
      }

      return report;
    } catch (e) {
      if (kDebugMode) print('Error parsing template: $e');
      return null;
    }
  }

  Future<String?> exportZip({String? customSavePath}) async {
    if (_currentReport == null || _currentReportPath == null) return null;
    try {
      await saveReport();

      // Сохраняем Excel
      final excelBytes = _generateExcel();
      final excelFile = File('$_currentReportPath/report.xlsx');
      await excelFile.writeAsBytes(excelBytes);
      if (kDebugMode) {
        print('Excel saved to: ${excelFile.path}, bytes: ${excelBytes.length}');
      }

      // Сохраняем HTML
      final htmlContent = _generateHtml();
      final htmlFile = File('$_currentReportPath/report.html');
      await htmlFile.writeAsString(htmlContent);
      if (kDebugMode) {
        print('HTML saved to: ${htmlFile.path}');
      }

      final folderPath = _currentReportPath!;
      final safeName = _currentReport!.reportName
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(' ', '_');

      String zipPath;
      if (customSavePath != null && customSavePath.isNotEmpty) {
        zipPath = '$customSavePath/$safeName.zip';
      } else {
        final reportsDir = await _getReportsDir();
        zipPath = '$reportsDir/$safeName.zip';
      }

      // Создаем директорию для ZIP файла если не существует
      final zipDir = Directory(path.dirname(zipPath));
      if (!await zipDir.exists()) {
        await zipDir.create(recursive: true);
      }

      final zipFile = File(zipPath);
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);

      final Set<String> neededFiles = {};
      
      neededFiles.add('report.json');
      neededFiles.add('report.html');
      neededFiles.add('report.xlsx');

      if (_currentReport != null) {
        if (_currentReport!.headerImagePath != null) {
          neededFiles.add(_currentReport!.headerImagePath!);
        }
        for (final markerEntry in _currentReport!.markers.entries) {
          for (final answerMarker in markerEntry.value) {
            for (final media in answerMarker.media) {
              if (media.localPath != null) {
                neededFiles.add(media.localPath!);
              }
            }
          }
        }
      }

      if (kDebugMode) {
        print('Files to add to zip: $neededFiles');
      }

      for (final relativePath in neededFiles) {
        final filePath = '$folderPath/$relativePath';
        final file = File(filePath);
        if (await file.exists()) {
          if (kDebugMode) print('Adding file to zip: $filePath');
          encoder.addFile(file, relativePath);
        } else {
          if (kDebugMode) print('File not found: $filePath');
        }
      }

      encoder.close();

      if (kDebugMode) {
        final zipArchive = ZipDecoder().decodeBytes(
          await zipFile.readAsBytes(),
        );
        print('ZIP content: ${zipArchive.files.map((f) => f.name).toList()}');
      }

      return zipPath;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error exporting zip: $e');
        print('Stack trace: $stackTrace');
      }
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
      int maxCount = 0;
      int minCount = 0;
      final allAnswers = <String, List<Map<String, dynamic>>>{};

      for (final lang in languages) {
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        allAnswers[lang] = answers;
        if (answers.length > maxCount) maxCount = answers.length;
      }
      minCount = maxCount;
      for (final lang in languages) {
        if (allAnswers[lang]!.length < minCount) {
          minCount = allAnswers[lang]!.length;
        }
      }

      final hasDifferentCount = maxCount != minCount || maxCount == 0;

      bool hasNonEmptyExtra = false;
      if (hasDifferentCount) {
        for (final lang in languages) {
          for (int j = minCount; j < allAnswers[lang]!.length; j++) {
            if ((allAnswers[lang]![j]['text'] as String? ?? '').isNotEmpty) {
              hasNonEmptyExtra = true;
              break;
            }
          }
          if (hasNonEmptyExtra) break;
        }
      }

      bool needsSync = false;

      if (hasDifferentCount) {
        needsSync = hasNonEmptyExtra;
      } else {
        final firstLang = languages.first;
        final firstLangAnswers = allAnswers[firstLang]!;
        
        for (int answerIdx = 0; answerIdx < firstLangAnswers.length; answerIdx++) {
          bool hasEmptyInAnswer = false;
          bool hasNonEmptyInAnswer = false;
          
          for (final lang in languages) {
            final answers = allAnswers[lang]!;
            if (answerIdx < answers.length) {
              final text = answers[answerIdx]['text'] as String? ?? '';
              if (text.isEmpty) {
                hasEmptyInAnswer = true;
              } else {
                hasNonEmptyInAnswer = true;
              }
            }
          }
          
          if (hasEmptyInAnswer && hasNonEmptyInAnswer) {
            needsSync = true;
            break;
          }
        }
      }

      if (needsSync) {
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
          final text = answers[a]['text'] ?? '';
          answerVariants[a].add(text);
        }
      }

      final answersWithId = <Map<String, dynamic>>[];
      for (int answerIdx = 0; answerIdx < answerVariants.length; answerIdx++) {
        final variant = answerVariants[answerIdx];
        final hasEmpty = variant.any((text) => text.isEmpty);
        final hasNonEmpty = variant.any((text) => text.isNotEmpty);
        if (hasEmpty && hasNonEmpty) {
          answersWithId.add({
            'id': answerIdx,
            'variants': variant,
          });
        }
      }

      if (answersWithId.isNotEmpty) {
        (data['questions'] as List).add({
          'id': q.id,
          'answers': answersWithId,
        });
      }
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
        if (!q.containsKey('answers')) return null;

        final answers = q['answers'] as List;
        for (final answer in answers) {
          if (answer is! Map) return null;
          if (!answer.containsKey('id')) return null;
          if (!answer.containsKey('variants')) return null;
          
          final variants = answer['variants'] as List;
          if (variants.length != languages.length) return null;
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
      if (_currentReport!.translations.containsKey(qid)) {
        _currentReport!.translations[qid]![langCode] = [TranslationAnswer()];
      }
    }
    notifyListeners();
  }

  void applySyncAnswers(String jsonStr) {
    if (_currentReport == null) return;
    final data = validateSyncJson(jsonStr);
    if (data == null) return;

    final languages = (data['languages'] as List).cast<String>();
    final questions = data['questions'] as List;

    for (final qData in questions) {
      final questionId = qData['id'] as int;
      final answers = qData['answers'] as List;

      final qIndex = _currentReport!.questions.indexWhere(
        (q) => q.id == questionId,
      );
      if (qIndex == -1) continue;

      final qid = qIndex.toString();

      // Collect all attention flags across all languages for this question
      final allAttentionFlags = <bool>[];
      final markersList = _currentReport!.markers[qid] ?? [];
      for (int i = 0; i < markersList.length; i++) {
        allAttentionFlags.add(markersList[i].attention);
      }

      // Determine for each answer index: is there ANY language with attention=true?
      final maxAnswers = allAttentionFlags.length;
      final shouldHaveAttention = List.filled(maxAnswers, false);
      for (int i = 0; i < maxAnswers; i++) {
        if (i < allAttentionFlags.length && allAttentionFlags[i]) {
          shouldHaveAttention[i] = true;
        }
      }

      // Save existing media lists
      final savedMedia = <List<MediaItem>>[];
      for (int i = 0; i < markersList.length; i++) {
        savedMedia.add(List.from(markersList[i].media));
      }

      // Update translations for all languages in sync data
      for (final answerData in answers) {
        final answerId = answerData['id'] as int;
        final texts = (answerData['variants'] as List).cast<String>();

        for (int langIndex = 0; langIndex < languages.length; langIndex++) {
          final lang = languages[langIndex];
          if (!_currentReport!.availableLanguages.contains(lang)) continue;

          final text = langIndex < texts.length ? texts[langIndex] : '';

          if (!_currentReport!.translations.containsKey(qid)) {
            _currentReport!.translations[qid] = {};
          }
          if (!_currentReport!.translations[qid]!.containsKey(lang)) {
            _currentReport!.translations[qid]![lang] = [];
          }

          final answersList = _currentReport!.translations[qid]![lang]!;
          if (answerId < answersList.length) {
            if (text.isNotEmpty) {
              answersList[answerId].text = text;
              answersList[answerId].isEmpty = text.isEmpty;
            }
          } else {
            answersList.add(
              TranslationAnswer(text: text, isEmpty: text.isEmpty),
            );
          }
        }
      }

      // Update markers with consistent attention flags and preserved media
      if (!_currentReport!.markers.containsKey(qid)) {
        _currentReport!.markers[qid] = [];
      }

      for (final answerData in answers) {
        final answerId = answerData['id'] as int;
        
        bool attention = answerId < shouldHaveAttention.length
            ? shouldHaveAttention[answerId]
            : false;

        List<MediaItem> media = [];
        if (answerId < savedMedia.length) {
          media = savedMedia[answerId];
        }

        if (answerId < _currentReport!.markers[qid]!.length) {
          _currentReport!.markers[qid]![answerId].attention = attention;
          _currentReport!.markers[qid]![answerId].media = media;
        } else {
          _currentReport!.markers[qid]!.add(
            AnswerMarkers(attention: attention, media: media),
          );
        }
      }
    }

    notifyListeners();
  }
}
