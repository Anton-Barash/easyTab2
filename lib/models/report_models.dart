import 'dart:convert';

class MediaItem {
  String name;
  String type;
  bool attention;
  String originalName;
  String? localPath;
  int? fileSize;
  int? compressedSize;

  MediaItem({
    required this.name,
    required this.type,
    this.attention = false,
    this.originalName = '',
    this.localPath,
    this.fileSize,
    this.compressedSize,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'attention': attention,
        'originalName': originalName,
        'localPath': localPath,
        'fileSize': fileSize,
        'compressedSize': compressedSize,
      };

  String? _toRelativePath(String? path, String? folderPath) {
    if (path == null || folderPath == null) return path;
    if (path.startsWith(folderPath)) {
      return path.substring(folderPath.length + 1);
    }
    return path;
  }

  Map<String, dynamic> toJsonWithRelativePaths(String? folderPath) => {
        'name': name,
        'type': type,
        'attention': attention,
        'originalName': originalName,
        'localPath': _toRelativePath(localPath, folderPath),
        'fileSize': fileSize,
        'compressedSize': compressedSize,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json, {String? folderPath}) {
    String? localPath = json['localPath'] as String?;
    // Если путь абсолютный и есть folderPath, преобразуем в относительный
    if (localPath != null && folderPath != null) {
      if (localPath.startsWith(folderPath)) {
        localPath = localPath.substring(folderPath.length + 1);
      } else if (localPath.startsWith('/') || localPath.contains(':\\')) {
        // Оставляем как есть, если это абсолютный путь из другого места
      }
    }
    return MediaItem(
      name: json['name'] ?? '',
      type: json['type'] ?? 'image/jpeg',
      attention: json['attention'] ?? false,
      originalName: json['originalName'] ?? '',
      localPath: localPath,
      fileSize: json['fileSize'] as int?,
      compressedSize: json['compressedSize'] as int?,
    );
  }
}

class AnswerMarkers {
  bool attention;
  List<MediaItem> media;
  bool needsWork;

  AnswerMarkers({
    this.attention = false,
    List<MediaItem>? media,
    this.needsWork = false,
  }) : media = media ?? [];

  Map<String, dynamic> toJson() => {
        'attention': attention,
        'media': media.map((m) => m.toJson()).toList(),
        'needsWork': needsWork,
      };

  Map<String, dynamic> toJsonWithRelativePaths(String? folderPath) => {
        'attention': attention,
        'media': media.map((m) => m.toJsonWithRelativePaths(folderPath)).toList(),
        'needsWork': needsWork,
      };

  factory AnswerMarkers.fromJson(Map<String, dynamic> json, {String? folderPath}) => AnswerMarkers(
        attention: json['attention'] ?? false,
        media: (json['media'] as List<dynamic>?)
                ?.map((m) => MediaItem.fromJson(m, folderPath: folderPath))
                .toList() ??
            [],
        needsWork: json['needsWork'] ?? false,
      );
}

class TranslationAnswer {
  String text;
  bool isEmpty;

  TranslationAnswer({
    this.text = '',
    this.isEmpty = true,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        '_empty': isEmpty,
      };

  factory TranslationAnswer.fromJson(Map<String, dynamic> json) => TranslationAnswer(
        text: json['text'] ?? '',
        isEmpty: json['_empty'] ?? true,
      );
}

class QuestionLocalization {
  String? name;
  String? description;
  String? example;

  QuestionLocalization({
    this.name,
    this.description,
    this.example,
  });

  bool get isEmpty => (name?.isEmpty ?? true) && (description?.isEmpty ?? true) && (example?.isEmpty ?? true);

  bool get isComplete => (name?.isNotEmpty ?? false) && (description?.isNotEmpty ?? false);

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'example': example,
      };

  factory QuestionLocalization.fromJson(Map<String, dynamic> json) => QuestionLocalization(
        name: json['name'],
        description: json['description'],
        example: json['example'],
      );
}

class Question {
  int id;
  Map<String, QuestionLocalization> localizations; // lang code -> localization

  Question({
    required this.id,
    this.localizations = const {},
  });

  QuestionLocalization? getLocalization(String langCode) => localizations[langCode];

  String? getDisplayName(String langCode) {
    final loc = localizations[langCode];
    if (loc?.name?.isNotEmpty ?? false) return loc?.name;
    for (final entry in localizations.entries) {
      if (entry.value.name?.isNotEmpty ?? false) {
        return entry.value.name;
      }
    }
    return null;
  }

  bool hasTranslation(String langCode) {
    final loc = localizations[langCode];
    return loc?.isComplete ?? false;
  }

  bool hasSomeTranslation() {
    return localizations.values.any((loc) => loc.isComplete);
  }

  List<String> getAvailableLanguages() {
    return localizations.entries.where((e) => !e.value.isEmpty).map((e) => e.key).toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'localizations': localizations.map((k, v) => MapEntry(k, v.toJson())),
      };

  Question copyWith({
    int? id,
    Map<String, QuestionLocalization>? localizations,
  }) {
    return Question(
      id: id ?? this.id,
      localizations: localizations ?? this.localizations,
    );
  }

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] ?? 0,
        localizations: (json['localizations'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, QuestionLocalization.fromJson(v)),
            ) ??
            {},
      );
}

class Report {
  String reportName;
  List<String> availableLanguages;
  String currentLanguage;
  List<Question> questions;
  Map<String, Map<String, List<TranslationAnswer>>> translations;
  Map<String, List<AnswerMarkers>> markers;
  Map<String, int> mediaCounter;
  int timestamp;
  String? folderPath;
  String productType;
  String factory;
  String model;
  int? dateTimestamp;
  String? headerImagePath;

  Report({
    this.reportName = '',
    this.availableLanguages = const [],
    this.currentLanguage = 'RU',
    this.questions = const [],
    this.translations = const {},
    this.markers = const {},
    this.mediaCounter = const {'photos': 1, 'X': 1},
    int? timestamp,
    this.folderPath,
    this.productType = 'Аэрогриль',
    this.factory = '',
    this.model = '',
    this.dateTimestamp,
    this.headerImagePath,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch {
    mediaCounter = Map<String, int>.from(mediaCounter);
  }

  List<Map<String, dynamic>> getAnswersForQuestion(int questionIndex, String langCode) {
    final qid = questionIndex.toString();
    final langAnswers = translations[qid]?[langCode] ?? [];
    final langMarkers = markers[qid] ?? [];
    
    final result = <Map<String, dynamic>>[];
    final maxLength = langAnswers.length > langMarkers.length ? langAnswers.length : langMarkers.length;
    
    for (int i = 0; i < maxLength; i++) {
      final text = i < langAnswers.length ? langAnswers[i].text : '';
      final isEmpty = i >= langAnswers.length || langAnswers[i].isEmpty;
      final attention = i < langMarkers.length ? langMarkers[i].attention : false;
      final needsWork = i < langMarkers.length ? langMarkers[i].needsWork : false;
      
      final mediaList = i < langMarkers.length ? langMarkers[i].media : [];
      final mediaMaps = mediaList.map((m) => {
        'name': m.name,
        'type': m.type,
        'attention': m.attention,
        'originalName': m.originalName,
        'localPath': m.localPath,
        'fileSize': m.fileSize,
        'compressedSize': m.compressedSize,
      }).toList();
      
      result.add({
        'text': text,
        'isEmpty': isEmpty,
        'attention': attention,
        'media': mediaMaps,
        'needsWork': needsWork,
      });
    }
    
    return result;
  }

  TranslationAnswer? getTranslationAnswer(int questionIndex, String langCode, int answerIndex) {
    final qid = questionIndex.toString();
    return translations[qid]?[langCode]?[answerIndex];
  }

  AnswerMarkers? getAnswerMarkers(int questionIndex, int answerIndex) {
    final qid = questionIndex.toString();
    return markers[qid]?[answerIndex];
  }

  bool hasAnswersInLanguage(int questionIndex, String langCode) {
    final qid = questionIndex.toString();
    final langAnswers = translations[qid]?[langCode] ?? [];
    return langAnswers.any((a) => !a.isEmpty);
  }

  bool hasAnyAnswerInLanguage(int questionIndex, String langCode) {
    return hasAnswersInLanguage(questionIndex, langCode);
  }

  bool hasAnswersInOtherLanguages(int questionIndex, int answerIndex) {
    final qid = questionIndex.toString();
    final currentLangAnswers = translations[qid]?[currentLanguage] ?? [];
    if (answerIndex >= currentLangAnswers.length) return false;
    
    for (final lang in availableLanguages) {
      if (lang == currentLanguage) continue;
      final langAnswers = translations[qid]?[lang] ?? [];
      if (answerIndex < langAnswers.length && !langAnswers[answerIndex].isEmpty) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'reportName': reportName,
        'availableLanguages': availableLanguages,
        'currentLanguage': currentLanguage,
        'questions': questions.map((q) => q.toJson()).toList(),
        'translations': translations.map((k, v) => MapEntry(k, v.map((lk, lva) => MapEntry(lk, lva.map((a) => a.toJson()).toList())))),
        'markers': markers.map((k, v) => MapEntry(k, v.map((m) => m.toJsonWithRelativePaths(folderPath)).toList())),
        'mediaCounter': mediaCounter,
        'timestamp': timestamp,
        'productType': productType,
        'factory': factory,
        'model': model,
        'dateTimestamp': dateTimestamp,
        'headerImagePath': headerImagePath,
      };

  factory Report.fromJson(Map<String, dynamic> json, {String? folderPath}) {
    final translationsJson = json['translations'] as Map<String, dynamic>?;
    final markersJson = json['markers'] as Map<String, dynamic>?;
    
    final translations = <String, Map<String, List<TranslationAnswer>>>{};
    final markers = <String, List<AnswerMarkers>>{};

    if (translationsJson != null) {
      translationsJson.forEach((qid, langMap) {
        if (langMap is Map) {
          translations[qid] = {};
          (langMap as Map<String, dynamic>).forEach((langCode, answersList) {
            if (answersList is List) {
              translations[qid]![langCode] = answersList.map((a) => TranslationAnswer.fromJson(a)).toList();
            }
          });
        }
      });
    }

    if (markersJson != null) {
      markersJson.forEach((qid, markersList) {
        if (markersList is List) {
          markers[qid] = markersList.map((m) => AnswerMarkers.fromJson(m, folderPath: folderPath)).toList();
        }
      });
    }

    final availableLanguages = (json['availableLanguages'] as List<dynamic>?)?.cast<String>() ?? [];

    final questionsList = json['questions'] as List?;
    final questionsCount = questionsList?.length ?? 0;
    
    for (int i = 0; i < questionsCount; i++) {
      final qid = i.toString();
      
      if (!translations.containsKey(qid)) {
        translations[qid] = {};
      }
      for (final lang in availableLanguages) {
        if (!translations[qid]!.containsKey(lang)) {
          translations[qid]![lang] = [TranslationAnswer()];
        }
      }
      
      if (!markers.containsKey(qid)) {
        markers[qid] = [AnswerMarkers()];
      }
    }

    return Report(
      reportName: json['reportName'] ?? '',
      availableLanguages: availableLanguages,
      currentLanguage: json['currentLanguage'] ?? 'RU',
      questions: (json['questions'] as List<dynamic>?)
              ?.map((q) => Question.fromJson(q))
              .toList() ??
          [],
      translations: translations,
      markers: markers,
      mediaCounter: Map<String, int>.from(json['mediaCounter'] ?? {'photos': 1, 'X': 1}),
      timestamp: json['timestamp'],
      folderPath: folderPath,
      productType: json['productType'] ?? 'Аэрогриль',
      factory: json['factory'] ?? '',
      model: json['model'] ?? '',
      dateTimestamp: json['dateTimestamp'] as int?,
      headerImagePath: json['headerImagePath'] as String?,
    );
  }

  Report copyWith({
    String? reportName,
    List<String>? availableLanguages,
    String? currentLanguage,
    List<Question>? questions,
    Map<String, Map<String, List<TranslationAnswer>>>? translations,
    Map<String, List<AnswerMarkers>>? markers,
    Map<String, int>? mediaCounter,
    int? timestamp,
    String? folderPath,
    String? productType,
    String? factory,
    String? model,
    int? dateTimestamp,
    String? headerImagePath,
  }) {
    return Report(
      reportName: reportName ?? this.reportName,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      currentLanguage: currentLanguage ?? this.currentLanguage,
      questions: questions ?? this.questions,
      translations: translations ?? this.translations,
      markers: markers ?? this.markers,
      mediaCounter: mediaCounter ?? this.mediaCounter,
      timestamp: timestamp ?? this.timestamp,
      folderPath: folderPath ?? this.folderPath,
      productType: productType ?? this.productType,
      factory: factory ?? this.factory,
      model: model ?? this.model,
      dateTimestamp: dateTimestamp ?? this.dateTimestamp,
      headerImagePath: headerImagePath ?? this.headerImagePath,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
