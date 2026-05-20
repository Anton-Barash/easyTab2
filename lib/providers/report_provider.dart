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

bool _isPng(Uint8List bytes) {
  if (bytes.length < 8) return false;
  return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
}

bool _isWebp(Uint8List bytes) {
  if (bytes.length < 12) return false;
  return bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
}

Uint8List _compressImage(Uint8List bytes, int maxSize) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) {
      if (kDebugMode) print('Error: Could not decode image');
      return bytes;
    }
    
    int width = image.width;
    int height = image.height;
    
    if (width <= maxSize && height <= maxSize) {
      return bytes;
    }
    
    double scale = maxSize / (width > height ? width : height);
    width = (width * scale).toInt();
    height = (height * scale).toInt();
    
    if (width < 1) width = 1;
    if (height < 1) height = 1;
    
    final resized = img.copyResize(image, width: width, height: height);
    
    Uint8List result;
    if (_isPng(bytes)) {
      result = img.encodePng(resized);
    } else if (_isWebp(bytes)) {
      result = img.encodeJpg(resized, quality: 90);
    } else {
      result = img.encodeJpg(resized, quality: 90);
    }
    
    if (result.isEmpty) {
      if (kDebugMode) print('Error: Compressed image is empty');
      return bytes;
    }
    
    return result;
  } catch (e) {
    if (kDebugMode) print('Error compressing image: $e');
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
    final attentionPrefix = name.startsWith('x') ? 'x' : '';
    final cleanName = name.startsWith('x') ? name.substring(1) : name;
    
    final typePrefix = cleanName.substring(0, 1);
    final rest = cleanName.substring(1);
    final parts = rest.split('_');
    
    if (parts.length >= 3) {
      final questionNum = parts[0];
      final answerNum = parts[1];
      final numStr = parts[2];
      
      if (int.tryParse(numStr) != null) {
        final key = '$attentionPrefix$typePrefix${questionNum}_$answerNum';
        if (!grouped.containsKey(key)) {
          grouped[key] = [];
        }
        grouped[key]!.add(int.parse(numStr));
      } else {
        if (!grouped.containsKey('other')) {
          grouped['other'] = [];
        }
        grouped['other']!.add(mediaNames.indexOf(name));
      }
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
      final uniqueNums = nums.toSet().toList()..sort();
      if (uniqueNums.length == 1) {
        result.add('${entry.key}_${uniqueNums[0].toString().padLeft(3, '0')}');
      } else {
        result.add('${entry.key}_${uniqueNums.first.toString().padLeft(3, '0')}-${uniqueNums.last.toString().padLeft(3, '0')}');
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'header_$timestamp.$ext';
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
      final compressed = _compressImage(bytes, 2000);
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

    final counterKey = '${questionIndex}_${answerIndex}_${isAttention ? 'X' : 'photos'}';
    if (!_currentReport!.mediaCounter.containsKey(counterKey)) {
      _currentReport!.mediaCounter[counterKey] = 1;
    }
    final counter = _currentReport!.mediaCounter[counterKey]!;
    final ext = file.path.split('.').last;
    final mimeType = _getMimeType(file.path);
    final typePrefix = mimeType.startsWith('video/') ? 'v' : 'f';
    final fileName = '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${counter.toString().padLeft(3, '0')}.$ext';

    final folderName = isAttention ? 'X' : 'photos';
    final destFolder = Directory('$_currentReportPath/$folderName');
    if (!await destFolder.exists()) {
      await destFolder.create(recursive: true);
    }

    final destPath = File('${destFolder.path}/$fileName');
    
    if (mimeType.startsWith('image/')) {
      final bytes = await file.readAsBytes();
      final compressed = _compressImage(bytes, 2000);
      await destPath.writeAsBytes(compressed);
    } else {
      await file.copy(destPath.path);
    }

    final relativePath = '$folderName/$fileName';

    final mediaItem = MediaItem(
      name: fileName,
      type: mimeType,
      attention: isAttention,
      originalName: file.path.split(Platform.pathSeparator).last,
      localPath: relativePath,
      fileSize: await file.length(),
    );

    _currentReport!.markers[qid]![answerIndex].media.add(mediaItem);

    _currentReport!.mediaCounter[counterKey] = counter + 1;

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

    final remainingMedia = _currentReport!.markers[qid]![answerIndex].media;
    for (int i = 0; i < remainingMedia.length; i++) {
      final item = remainingMedia[i];
      final ext = item.name.split('.').last;
      final typePrefix = item.name.startsWith('v') ? 'v' : 'f';
      final newName = '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${(i + 1).toString().padLeft(3, '0')}.$ext';

      if (item.name != newName) {
        final oldName = item.name;
        if (_currentReportPath != null && item.localPath != null) {
          final oldPath = '$_currentReportPath/${item.localPath}';
          final newPath = '$_currentReportPath/${item.localPath!.replaceFirst(oldName, newName)}';
          final oldFile = File(oldPath);
          if (await oldFile.exists()) {
            await oldFile.rename(newPath);
          }
          item.localPath = item.localPath!.replaceFirst(oldName, newName);
        }
        item.name = newName;
      }
    }

    final counterKey = '${questionIndex}_${answerIndex}_${media.attention ? 'X' : 'photos'}';
    _currentReport!.mediaCounter[counterKey] = remainingMedia.length + 1;

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

    final List<String> allImagePaths = [];
    final List<List<List<List<Map<String, dynamic>>>>> allMediaByQandAandLang = [];

    for (int i = 0; i < _currentReport!.questions.length; i++) {
      final List<List<List<Map<String, dynamic>>>> questionMedia = [];

      for (int li = 0; li < languages.length; li++) {
        final lang = languages[li];
        final answers = _currentReport!.getAnswersForQuestion(i, lang);
        final List<List<Map<String, dynamic>>> langMedia = [];

        for (final a in answers) {
          final List<Map<String, dynamic>> answerMedia = [];
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
            answerMedia.add(mediaData);
            if (media['type'].startsWith('image') && !allImagePaths.contains(relativePath)) {
              allImagePaths.add(relativePath);
            }
          }
          langMedia.add(answerMedia);
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
    buffer.writeln('    }');
    buffer.writeln('    .language-switcher {');
    buffer.writeln('      position: sticky;');
    buffer.writeln('      top: 0;');
    buffer.writeln('      background: #e9e9e9;');
    buffer.writeln('      display: flex;');
    buffer.writeln('      gap: 10px;');
    buffer.writeln('      flex-wrap: wrap;');
    buffer.writeln('    }');
    buffer.writeln('    .lang-btn {');
    buffer.writeln('      padding: 4px 8px;');
    buffer.writeln('      border: 1px solid #a0a0a0;');
    buffer.writeln('      background: white;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('      font-size: 7px;');
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
    buffer.writeln('      display: block;');
    buffer.writeln('      width: fit-content;');
    buffer.writeln('      box-shadow: 2px 2px 8px rgba(0,0,0,0.1);');
    buffer.writeln('      margin: 20px auto;');
    buffer.writeln('    }');
    buffer.writeln('    table {');
    buffer.writeln('      border-collapse: collapse;');
    buffer.writeln('      font-size: 16px;');
    buffer.writeln('      table-layout: auto;');
    buffer.writeln('    }');
    buffer.writeln('    th, td {');
    buffer.writeln('      padding: 7.5px 12.5px;');
    buffer.writeln('      vertical-align: top;');
    buffer.writeln('      border-bottom: 1px solid #d0d0d0;');
    buffer.writeln('    }');
    buffer.writeln('    th {');
    buffer.writeln('      background: #f3f3f3;');
    buffer.writeln('      font-weight: 600;');
    buffer.writeln('      text-align: left;');
    buffer.writeln('      color: #2c2c2c;');
    buffer.writeln('    }');
    buffer.writeln('    .media-thumbnails {');
    buffer.writeln('      display: flex;');
    buffer.writeln('      flex-wrap: wrap;');
    buffer.writeln('      gap: 4px;');
    buffer.writeln('    }');
    buffer.writeln('    .media-item {');
    buffer.writeln('      width: 50px;');
    buffer.writeln('      height: 50px;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('    }');
    buffer.writeln('    .media-item-more {');
    buffer.writeln('      background: #c0c0c0;');
    buffer.writeln('      border: 1px solid #a0a0a0;');
    buffer.writeln('      display: flex;');
    buffer.writeln('      align-items: center;');
    buffer.writeln('      justify-content: center;');
    buffer.writeln('    }');
    buffer.writeln('    .media-item-more:hover {');
    buffer.writeln('      background: #b0b0b0;');
    buffer.writeln('    }');
    buffer.writeln('    .media-more {');
    buffer.writeln('      font-size: 20px;');
    buffer.writeln('      font-weight: bold;');
    buffer.writeln('      color: #333;');
    buffer.writeln('    }');
    buffer.writeln('    .media-thumbnail {');
    buffer.writeln('      width: 50px;');
    buffer.writeln('      height: 50px;');
    buffer.writeln('      object-fit: cover;');
    buffer.writeln('      border-radius: 4px;');
    buffer.writeln('      border: 1px solid #d0d0d0;');
    buffer.writeln('      cursor: pointer;');
    buffer.writeln('    }');
    buffer.writeln('    .media-hidden {');
    buffer.writeln('      display: none;');
    buffer.writeln('    }');
    buffer.writeln('    /* Lightbox styles */');
    buffer.writeln('    .lightbox { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.9); display: none; flex-direction: column; align-items: center; justify-content: center; z-index: 9999; }');
    buffer.writeln('    .lightbox.active { display: flex; }');
    buffer.writeln('    .lightbox-controls { position: absolute; top: 20px; left: 50%; transform: translateX(-50%); display: flex; gap: 10px; z-index: 10002; }');
    buffer.writeln('    .lightbox-controls button { background: rgba(255,255,255,0.2); border: none; color: white; padding: 10px 15px; border-radius: 4px; cursor: pointer; font-size: 16px; transition: background 0.2s; }');
    buffer.writeln('    .lightbox-controls button:hover { background: rgba(255,255,255,0.3); }');
    buffer.writeln('    .lightbox-nav { position: absolute; top: 50%; transform: translateY(-50%); background: rgba(255,255,255,0.2); border: none; color: white; padding: 15px 20px; border-radius: 4px; cursor: pointer; font-size: 20px; transition: background 0.2s; z-index: 10001; }');
    buffer.writeln('    .lightbox-nav:hover { background: rgba(255,255,255,0.3); }');
    buffer.writeln('    .lightbox-nav.prev { left: calc(50% - 500px); }');
    buffer.writeln('    .lightbox-nav.next { right: calc(50% - 500px); }');
    buffer.writeln('    .lightbox-close { position: absolute; top: 20px; right: 20px; background: none; border: none; color: white; font-size: 32px; cursor: pointer; z-index: 10002; }');
    buffer.writeln('    .lightbox-info { position: absolute; top: 0px; left: 0px; background: rgba(0,0,0,0.7); color: white; padding: 15px 20px; border-radius: 8px; max-width: 280px; overflow-y: auto; text-align: left; z-index: 10001; }');
    buffer.writeln('    .attention-answer { color: #f69a15; }');
    buffer.writeln('    .lightbox-question { font-weight: bold; font-size: 16px; margin-bottom: 5px; }');
    buffer.writeln('    .lightbox-answer { font-size: 14px; }');
    buffer.writeln('    .lightbox-image-container { position: relative; width: 100%; overflow: hidden; cursor: grab; display: flex; align-items: center; justify-content: center; z-index: 10000; }');
    buffer.writeln('    .lightbox-image-container.dragging { cursor: grabbing; }');
    buffer.writeln('    .lightbox img { max-width: 100%; max-height: 100%; object-fit: contain; transform-origin: center center; }');
    buffer.writeln('    .lightbox-thumbnails-bar { position: absolute; bottom: 0px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.7); padding: 10px 15px; border-radius: 8px; max-width: 80%; overflow: hidden; z-index: 10001; }');
    buffer.writeln('    @media (max-width: 1000px) {');
    buffer.writeln('      .lightbox-nav.prev { left: 20px; }');
    buffer.writeln('      .lightbox-nav.next { right: 20px; }');
    buffer.writeln('      .lightbox-image-container { width: 90%; }');
    buffer.writeln('    }');
    buffer.writeln('    @media (max-width: 768px) {');
    buffer.writeln('      .lightbox-info { left: 20px; right: 20px; top: 60px; bottom: auto; max-width: none; max-height: 100px; }');
    buffer.writeln('      .lightbox-image-container { position: relative; width: calc(100% - 40px); height: calc(100vh - 290px); }');
    buffer.writeln('      .lightbox-nav.prev { left: 20px; }');
    buffer.writeln('      .lightbox-nav.next { right: 20px; }');
    buffer.writeln('      .lightbox-thumbnails-bar { bottom: 120px; }');
    buffer.writeln('    }');
    buffer.writeln('    .thumbnails-container { display: flex; gap: 8px; overflow-x: auto; scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.5) rgba(0,0,0,0.3); }');
    buffer.writeln('    .thumbnails-container::-webkit-scrollbar { height: 6px; }');
    buffer.writeln('    .thumbnails-container::-webkit-scrollbar-track { background: rgba(255,255,255,0.1); border-radius: 3px; }');
    buffer.writeln('    .thumbnails-container::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.5); border-radius: 3px; }');
    buffer.writeln('    .lightbox-thumbnail { width: 60px; height: 60px; object-fit: cover; border-radius: 4px; cursor: pointer; opacity: 0.6; transition: opacity 0.2s, border 0.2s; border: 2px solid transparent; }');
    buffer.writeln('    .lightbox-thumbnail:hover { opacity: 1; }');
    buffer.writeln('    .lightbox-thumbnail.active { opacity: 1; border-color: #00B0F0; }');
    buffer.writeln('    .lightbox-grid-btn { position: absolute; top: 20px; right: 70px; background: rgba(255,255,255,0.2); border: none; color: white; font-size: 24px; cursor: pointer; z-index: 10002; padding: 5px 12px; border-radius: 4px; transition: background 0.2s; }');
    buffer.writeln('    .lightbox-grid-btn:hover { background: rgba(255,255,255,0.3); }');
    buffer.writeln('    /* Gallery overlay styles */');
    buffer.writeln('    .gallery-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.95); display: none; flex-direction: column; z-index: 9998; }');
    buffer.writeln('    .gallery-overlay.active { display: flex; }');
    buffer.writeln('    .gallery-close { position: absolute; top: 20px; right: 20px; background: none; border: none; color: white; font-size: 32px; cursor: pointer; z-index: 10002; }');
    buffer.writeln('    .gallery-container { flex: 1; overflow-y: auto; padding: 80px 20px 20px; }');
    buffer.writeln('    .gallery-grid { grid-template-columns: repeat(4, 1fr); gap: 15px; max-width: 1400px; margin: 0 auto; }');
    buffer.writeln('    .gallery-item { aspect-ratio: 1; overflow: hidden; border-radius: 8px; cursor: pointer; transition: transform 0.2s; }');
    buffer.writeln('    .gallery-item:hover { transform: scale(1.02); }');
    buffer.writeln('    .gallery-item img { width: 100%; height: 100%; object-fit: cover; }');
    buffer.writeln('    @media (max-width: 1200px) { .gallery-grid { grid-template-columns: repeat(3, 1fr); } }');
    buffer.writeln('    @media (max-width: 900px) { .gallery-grid { grid-template-columns: repeat(2, 1fr); } }');
    buffer.writeln('    @media (max-width: 600px) { .gallery-grid { grid-template-columns: 1fr; } }');
    buffer.writeln('    /* Gallery section header styles */');
    buffer.writeln('    .gallery-section { margin-bottom: 30px; display: grid; grid-template-columns: inherit; }');
    buffer.writeln('    .gallery-section-header {');
    buffer.writeln('      grid-column: 1 / -1;');
    buffer.writeln('      color: white;');
    buffer.writeln('      padding: 15px 20px;');
    buffer.writeln('      border-radius: 8px;');
    buffer.writeln('      margin-bottom: 15px;');
    buffer.writeln('      font-size: 16px;');
    buffer.writeln('      font-weight: 600;');
    buffer.writeln('    }');
    buffer.writeln('    .gallery-section-header .question { font-size: 14px; opacity: 0.9; margin-bottom: 5px; }');
    buffer.writeln('    .gallery-section-header .answer { font-size: 18px; font-weight: 700; }');
    buffer.writeln('    /* Header styles */');
    buffer.writeln('    .header-row {');
    buffer.writeln('      background: #ffffff !important;');
    buffer.writeln('      color: #6c757d;');
    buffer.writeln('      text-align: left;');
    buffer.writeln('    }');
    buffer.writeln('    .title {');
    buffer.writeln('      font-weight: bold;');
    buffer.writeln('      font-size: 22px;');
    buffer.writeln('    }');
    buffer.writeln('    .border-bold {');
    buffer.writeln('      border-bottom: 2px solid #6c757d !important;');
    buffer.writeln('      font-size: 22px;');
    buffer.writeln('    }');
    buffer.writeln('    .no-border {');
    buffer.writeln('      border-bottom: none !important;');
    buffer.writeln('      font-size: 18px;');
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
    buffer.writeln('    <!-- 3 строка: ОБЪЕДИНЕНА + ФОТО -->');
    buffer.writeln('    <tr class="header-row">');
    buffer.writeln('      <td colspan="5" style="text-align:left; font-weight:bold; padding:8px; color:#6c757d; border-bottom:none;">ФОТО</td>');
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
        if (ai >= allMediaByQandAandLang[qIndex][li].length) {
          return '<div class="media-thumbnails"></div>';
        }

        final List<Map<String, dynamic>> mediaList =
            allMediaByQandAandLang[qIndex][li][ai];
        final parts = <String>[];
        final questionName = questionNames[li];
        final answerText = answerCellContent(ai, li);

        const int maxVisible = 8;
        final visibleCount = mediaList.length > maxVisible ? maxVisible : mediaList.length;

        for (int mi = 0; mi < visibleCount; mi++) {
          final media = mediaList[mi];
          final isImage = media['type'].startsWith('image');
          
          if (isImage) {
            parts.add(
              '<div class="media-item" data-src="${media['localPath']}" data-type="image" data-question="$questionName" data-answer="$answerText" data-lang="$li" onclick="openLightbox(\'${media['localPath']}\', \'image\')">'
              '<img class="media-thumbnail" src="${media['localPath']}" alt="${media['name']}" />'
              '</div>',
            );
          } else {
            parts.add(
              '<div class="media-item" data-src="${media['localPath']}" data-type="video" data-question="$questionName" data-answer="$answerText" data-lang="$li" onclick="openLightbox(\'${media['localPath']}\', \'video\')">'
              '<img class="media-thumbnail" src="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2250%22 height=%2250%22 viewBox=%220 0 50 50%22><rect fill=%22%23e0e0e0%22 width=%2250%22 height=%2250%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2216%22>🎬</text></svg>" alt="${media['name']}" />'
              '</div>',
            );
          }
        }

        if (mediaList.length > maxVisible) {
          final hiddenCount = mediaList.length - maxVisible;
          parts.add(
            '<div class="media-item media-item-more" onclick="openGallery()">'
            '<div class="media-more">+$hiddenCount</div>'
            '</div>',
          );
        }

        for (int mi = visibleCount; mi < mediaList.length; mi++) {
          final media = mediaList[mi];
          final isImage = media['type'].startsWith('image');
          if (isImage) {
            parts.add(
              '<div class="media-item media-hidden" data-src="${media['localPath']}" data-type="image" data-question="$questionName" data-answer="$answerText" data-lang="$li" onclick="openLightbox(\'${media['localPath']}\', \'image\')">'
              '<img class="media-thumbnail" src="${media['localPath']}" alt="${media['name']}" />'
              '</div>',
            );
          } else {
            parts.add(
              '<div class="media-item media-hidden" data-src="${media['localPath']}" data-type="video" data-question="$questionName" data-answer="$answerText" data-lang="$li" onclick="openLightbox(\'${media['localPath']}\', \'video\')">'
              '<img class="media-thumbnail" src="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2250%22 height=%2250%22 viewBox=%220 0 50 50%22><rect fill=%22%23e0e0e0%22 width=%2250%22 height=%2250%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2216%22>🎬</text></svg>" alt="${media['name']}" />'
              '</div>',
            );
          }
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

        buffer.writeln('    </tr>');
      }
    }
    buffer.writeln('  </table>');
    buffer.writeln('</div>');

    // Lightbox
    buffer.writeln('  <div class="lightbox" id="lightbox">');
    buffer.writeln('    <button class="lightbox-close" onclick="closeLightbox()">×</button>');
    buffer.writeln('    <button class="lightbox-grid-btn" onclick="openGallery()" title="Просмотр всех фото">⊞</button>');
    buffer.writeln('    <div class="lightbox-info">');
    buffer.writeln('      <div class="lightbox-question" id="lightbox-question"></div>');
    buffer.writeln('      <div class="lightbox-answer" id="lightbox-answer"></div>');
    buffer.writeln('    </div>');
    buffer.writeln('    <div class="lightbox-controls">');
    buffer.writeln('      <button onclick="zoomIn()">+</button>');
    buffer.writeln('      <button onclick="zoomOut()">-</button>');
    buffer.writeln('      <button onclick="resetZoom()">100%</button>');
    buffer.writeln('    </div>');
    buffer.writeln('    <button class="lightbox-nav prev" onclick="prevMedia()">←</button>');
    buffer.writeln('    <div class="lightbox-image-container" id="lightbox-container">');
    buffer.writeln('      <img id="lightbox-img" src="" alt="" style="display:none;" />');
    buffer.writeln('      <video id="lightbox-video" controls style="display:none;max-width:100%;max-height:100%;" />');
    buffer.writeln('    </div>');
    buffer.writeln('    <button class="lightbox-nav next" onclick="nextMedia()">→</button>');
    buffer.writeln('    <div class="lightbox-thumbnails-bar" id="lightbox-thumbnails-bar">');
    buffer.writeln('      <div class="thumbnails-container" id="thumbnails-container"></div>');
    buffer.writeln('    </div>');
    buffer.writeln('  </div>');

    // Gallery overlay
    buffer.writeln('  <div class="gallery-overlay" id="gallery-overlay">');
    buffer.writeln('    <button class="gallery-close" onclick="closeGallery()">×</button>');
    buffer.writeln('    <div class="gallery-container" id="gallery-container">');
    buffer.writeln('      <div class="gallery-grid" id="gallery-grid"></div>');
    buffer.writeln('    </div>');
    buffer.writeln('  </div>');

    // JavaScript
    buffer.writeln('<script>');
    buffer.writeln('    let currentIndex = 0;');
    buffer.writeln('    let media = [];');
    buffer.writeln('    let scale = 1;');
    buffer.writeln('    let panX = 0;');
    buffer.writeln('    let panY = 0;');
    buffer.writeln('    let isDragging = false;');
    buffer.writeln('    let startX = 0;');
    buffer.writeln('    let startY = 0;');
    buffer.writeln('    const allLanguages = ${jsonEncode(languages)};');
    buffer.writeln('    let currentLanguage = 0;');

    buffer.writeln('    function switchLanguage(li) {');
    buffer.writeln('      document.querySelectorAll(".lang-btn").forEach(btn => btn.classList.remove("active"));');
    buffer.writeln('      document.querySelector(\'.lang-btn[data-lang="\' + li + \'"]\').classList.add("active");');
    buffer.writeln('      for (let l = 0; l < allLanguages.length; l++) {');
    buffer.writeln('        const display = l === li ? "" : "none";');
    buffer.writeln('        document.querySelectorAll(".question-lang-" + l).forEach(el => el.style.display = display);');
    buffer.writeln('        document.querySelectorAll(".answer-lang-" + l).forEach(el => el.style.display = display);');
    buffer.writeln('        document.querySelectorAll(".media-lang-" + l).forEach(el => el.style.display = display);');
    buffer.writeln('      }');
    buffer.writeln('      currentLanguage = li;');
    buffer.writeln('      loadMediaByLanguage();');
    buffer.writeln('    }');

    buffer.writeln('    function loadMediaByLanguage() {');
    buffer.writeln('      const mediaElements = document.querySelectorAll(".media-item");');
    buffer.writeln('      media = Array.from(mediaElements).filter(el => parseInt(el.dataset.lang) === currentLanguage).map(el => ({');
    buffer.writeln('        src: el.dataset.src,');
    buffer.writeln('        type: el.dataset.type,');
    buffer.writeln('        question: el.dataset.question,');
    buffer.writeln('        answer: el.dataset.answer');
    buffer.writeln('      }));');
    buffer.writeln('      buildThumbnailsBar();');
    buffer.writeln('    }');

    buffer.writeln('    document.addEventListener("DOMContentLoaded", function() {');
    buffer.writeln('      loadMediaByLanguage();');
    buffer.writeln('    });');
    buffer.writeln('    function buildThumbnailsBar() {');
    buffer.writeln('      const container = document.getElementById("thumbnails-container");');
    buffer.writeln('      container.innerHTML = "";');
    buffer.writeln('      media.forEach((m, index) => {');
    buffer.writeln('        const thumbnail = document.createElement("img");');
    buffer.writeln('        thumbnail.className = "lightbox-thumbnail";');
    buffer.writeln('        if (m.type === "image") {');
    buffer.writeln('          thumbnail.src = m.src;');
    buffer.writeln('        } else {');
    buffer.writeln('          thumbnail.src = "data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2260%22 height=%2260%22 viewBox=%220 0 60 60%22><rect fill=%22%23e0e0e0%22 width=%2260%22 height=%2260%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2220%22>🎬</text></svg>";');
    buffer.writeln('        }');
    buffer.writeln('        thumbnail.onclick = function() { showMedia(index); };');
    buffer.writeln('        container.appendChild(thumbnail);');
    buffer.writeln('      });');
    buffer.writeln('    }');
    buffer.writeln('    function updateActiveThumbnail() {');
    buffer.writeln('      document.querySelectorAll(".lightbox-thumbnail").forEach((thumb, index) => {');
    buffer.writeln('        thumb.classList.toggle("active", index === currentIndex);');
    buffer.writeln('      });');
    buffer.writeln('      scrollToActiveThumbnail();');
    buffer.writeln('    }');
    buffer.writeln('    function scrollToActiveThumbnail() {');
    buffer.writeln('      const container = document.getElementById("thumbnails-container");');
    buffer.writeln('      const activeThumbnail = document.querySelector(".lightbox-thumbnail.active");');
    buffer.writeln('      if (!container || !activeThumbnail) return;');
    buffer.writeln('      const containerRect = container.getBoundingClientRect();');
    buffer.writeln('      const thumbnailRect = activeThumbnail.getBoundingClientRect();');
    buffer.writeln('      const scrollLeft = activeThumbnail.offsetLeft - containerRect.width / 2 + thumbnailRect.width / 2;');
    buffer.writeln('      container.scrollTo({ left: scrollLeft, behavior: "smooth" });');
    buffer.writeln('    }');

    buffer.writeln('    function openLightbox(src, type) {');
    buffer.writeln('      const index = media.findIndex(m => m.src === src && m.type === type);');
    buffer.writeln('      if (index === -1) return;');
    buffer.writeln('      currentIndex = index;');
    buffer.writeln('      const imgEl = document.getElementById("lightbox-img");');
    buffer.writeln('      const videoEl = document.getElementById("lightbox-video");');
    buffer.writeln('      const questionEl = document.getElementById("lightbox-question");');
    buffer.writeln('      const answerEl = document.getElementById("lightbox-answer");');
    buffer.writeln('      if (type === "image") {');
    buffer.writeln('        imgEl.style.display = "block";');
    buffer.writeln('        videoEl.style.display = "none";');
    buffer.writeln('        videoEl.pause();');
    buffer.writeln('        imgEl.src = src;');
    buffer.writeln('      } else {');
    buffer.writeln('        imgEl.style.display = "none";');
    buffer.writeln('        videoEl.style.display = "block";');
    buffer.writeln('        videoEl.src = src;');
    buffer.writeln('        videoEl.load();');
    buffer.writeln('      }');
    buffer.writeln('      if (media[currentIndex]) {');
    buffer.writeln('        questionEl.textContent = media[currentIndex].question || "";');
    buffer.writeln('        answerEl.textContent = media[currentIndex].answer || "";');
    buffer.writeln('      }');
    buffer.writeln('      document.getElementById("lightbox").classList.add("active");');
    buffer.writeln('      resetZoom();');
    buffer.writeln('      updateActiveThumbnail();');
    buffer.writeln('    }');

    buffer.writeln('    function closeLightbox() {');
    buffer.writeln('      document.getElementById("lightbox").classList.remove("active");');
    buffer.writeln('      document.getElementById("lightbox-video").pause();');
    buffer.writeln('    }');

    buffer.writeln('    function showMedia(index) {');
    buffer.writeln('      if (index >= 0 && index < media.length) {');
    buffer.writeln('        openLightbox(media[index].src, media[index].type);');
    buffer.writeln('      }');
    buffer.writeln('    }');

    buffer.writeln('    function nextMedia() {');
    buffer.writeln('      if (media.length > 1) {');
    buffer.writeln('        currentIndex = (currentIndex + 1) % media.length;');
    buffer.writeln('        showMedia(currentIndex);');
    buffer.writeln('      }');
    buffer.writeln('    }');

    buffer.writeln('    function prevMedia() {');
    buffer.writeln('      if (media.length > 1) {');
    buffer.writeln('        currentIndex = (currentIndex - 1 + media.length) % media.length;');
    buffer.writeln('        showMedia(currentIndex);');
    buffer.writeln('      }');
    buffer.writeln('    }');

    buffer.writeln('    function zoomIn() { scale = Math.min(scale * 1.2, 5); applyTransform(); }');
    buffer.writeln('    function zoomOut() { scale = Math.max(scale / 1.2, 0.5); applyTransform(); }');
    buffer.writeln('    function resetZoom() { scale = 1; panX = 0; panY = 0; applyTransform(); }');

    buffer.writeln('    function applyTransform() {');
    buffer.writeln('      const imgEl = document.getElementById("lightbox-img");');
    buffer.writeln('      const videoEl = document.getElementById("lightbox-video");');
    buffer.writeln('      imgEl.style.transform = "translate(" + panX + "px, " + panY + "px) scale(" + scale + ")";');
    buffer.writeln('      videoEl.style.transform = "translate(" + panX + "px, " + panY + "px) scale(" + scale + ")";');
    buffer.writeln('    }');

    buffer.writeln('    const container = document.getElementById("lightbox-container");');
    buffer.writeln('    container.addEventListener("mousedown", function(e) {');
    buffer.writeln('      isDragging = true; startX = e.clientX - panX; startY = e.clientY - panY; container.classList.add("dragging"); e.preventDefault();');
    buffer.writeln('    });');
    buffer.writeln('    document.addEventListener("mousemove", function(e) {');
    buffer.writeln('      if (isDragging) { panX = e.clientX - startX; panY = e.clientY - startY; applyTransform(); }');
    buffer.writeln('    });');
    buffer.writeln('    document.addEventListener("mouseup", function() { isDragging = false; container.classList.remove("dragging"); });');
    buffer.writeln('    container.addEventListener("wheel", function(e) { e.preventDefault(); if (e.deltaY < 0) zoomIn(); else zoomOut(); });');
    buffer.writeln('    document.addEventListener("keydown", function(e) {');
    buffer.writeln('      if (document.getElementById("lightbox").classList.contains("active")) {');
    buffer.writeln('        if (e.key === "ArrowRight") nextMedia();');
    buffer.writeln('        if (e.key === "ArrowLeft") prevMedia();');
    buffer.writeln('        if (e.key === "Escape") closeLightbox();');
    buffer.writeln('        if (e.key === "+" || e.key === "=") zoomIn();');
    buffer.writeln('        if (e.key === "-") zoomOut();');
    buffer.writeln('        if (e.key === "0") resetZoom();');
    buffer.writeln('      }');
    buffer.writeln('    });');
    buffer.writeln('    window.addEventListener("resize", function() {');
    buffer.writeln('      if (document.getElementById("lightbox").classList.contains("active")) {');
    buffer.writeln('        scrollToActiveThumbnail();');
    buffer.writeln('      }');
    buffer.writeln('    });');

    buffer.writeln('    function openGallery() {');
    buffer.writeln('      const galleryGrid = document.getElementById("gallery-grid");');
    buffer.writeln('      galleryGrid.innerHTML = "";');
    buffer.writeln('      const imageMedia = media.filter(m => m.type === "image");');
    buffer.writeln('      ');
    buffer.writeln('      const groupedMedia = {};');
    buffer.writeln('      imageMedia.forEach((m) => {');
    buffer.writeln('        const key = (m.question || "") + "|||" + (m.answer || "");');
    buffer.writeln('        if (!groupedMedia[key]) {');
    buffer.writeln('          groupedMedia[key] = { question: m.question, answer: m.answer, items: [] };');
    buffer.writeln('        }');
    buffer.writeln('        groupedMedia[key].items.push(m);');
    buffer.writeln('      });');
    buffer.writeln('      ');
    buffer.writeln('      let targetElement = null;');
    buffer.writeln('      Object.values(groupedMedia).forEach((group) => {');
    buffer.writeln('        const section = document.createElement("div");');
    buffer.writeln('        section.className = "gallery-section";');
    buffer.writeln('        ');
    buffer.writeln('        const header = document.createElement("div");');
    buffer.writeln('        header.className = "gallery-section-header";');
    buffer.writeln('        ');
    buffer.writeln('        const questionDiv = document.createElement("div");');
    buffer.writeln('        questionDiv.className = "question";');
    buffer.writeln('        questionDiv.textContent = group.question || "Без вопроса";');
    buffer.writeln('        header.appendChild(questionDiv);');
    buffer.writeln('        ');
    buffer.writeln('        const answerDiv = document.createElement("div");');
    buffer.writeln('        answerDiv.className = "answer";');
    buffer.writeln('        answerDiv.textContent = group.answer || "Без ответа";');
    buffer.writeln('        header.appendChild(answerDiv);');
    buffer.writeln('        ');
    buffer.writeln('        section.appendChild(header);');
    buffer.writeln('        ');
    buffer.writeln('        group.items.forEach((m) => {');
    buffer.writeln('          const galleryItem = document.createElement("div");');
    buffer.writeln('          galleryItem.className = "gallery-item";');
    buffer.writeln('          const img = document.createElement("img");');
    buffer.writeln('          img.src = m.src;');
    buffer.writeln('          img.alt = m.question || "Photo";');
    buffer.writeln('          img.onclick = function() {');
    buffer.writeln('            closeGallery();');
    buffer.writeln('            openLightbox(m.src, m.type);');
    buffer.writeln('          };');
    buffer.writeln('          galleryItem.appendChild(img);');
    buffer.writeln('          section.appendChild(galleryItem);');
    buffer.writeln('          ');
    buffer.writeln('          // Check if this is the current media item');
    buffer.writeln('          if (currentIndex >= 0 && currentIndex < media.length && media[currentIndex].src === m.src) {');
    buffer.writeln('            targetElement = galleryItem;');
    buffer.writeln('          }');
    buffer.writeln('        });');
    buffer.writeln('        ');
    buffer.writeln('        galleryGrid.appendChild(section);');
    buffer.writeln('      });');
    buffer.writeln('      ');
    buffer.writeln('      document.getElementById("gallery-overlay").classList.add("active");');
    buffer.writeln('      closeLightbox();');
    buffer.writeln('      ');
    buffer.writeln('      // Scroll to target element if found');
    buffer.writeln('      setTimeout(() => {');
    buffer.writeln('        if (targetElement) {');
    buffer.writeln('          targetElement.scrollIntoView({ behavior: "smooth", block: "center" });');
    buffer.writeln('        }');
    buffer.writeln('      }, 100);');
    buffer.writeln('    }');

    buffer.writeln('    function closeGallery() {');
    buffer.writeln('      document.getElementById("gallery-overlay").classList.remove("active");');
    buffer.writeln('    }');

    buffer.writeln('    document.addEventListener("keydown", function(e) {');
    buffer.writeln('      if (document.getElementById("gallery-overlay").classList.contains("active")) {');
    buffer.writeln('        if (e.key === "Escape") closeGallery();');
    buffer.writeln('      }');
    buffer.writeln('    });');
    buffer.writeln('  </script>');

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
              final num = name.split('.').first;
              mediaByAnswer[ai].add('$prefix$num');
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
          await Future.delayed(const Duration(milliseconds: 20));
        } else {
          if (kDebugMode) print('File not found: $filePath');
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));
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
