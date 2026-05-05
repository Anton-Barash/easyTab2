import 'dart:convert';

class MediaItem {
  String name;
  String type;
  bool attention;
  String originalName;
  String? localPath;

  MediaItem({
    required this.name,
    required this.type,
    this.attention = false,
    this.originalName = '',
    this.localPath,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'attention': attention,
        'originalName': originalName,
        'localPath': localPath,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        name: json['name'] ?? '',
        type: json['type'] ?? 'image/jpeg',
        attention: json['attention'] ?? false,
        originalName: json['originalName'] ?? '',
        localPath: json['localPath'],
      );
}

class Answer {
  String text;
  bool attention;
  List<MediaItem> media;
  bool isEmpty;

  Answer({
    this.text = '',
    this.attention = false,
    List<MediaItem>? media,
    this.isEmpty = true,
  }) : media = media ?? [];

  Map<String, dynamic> toJson() => {
        'text': text,
        'attention': attention,
        'media': media.map((m) => m.toJson()).toList(),
        '_empty': isEmpty,
      };

  factory Answer.fromJson(Map<String, dynamic> json) => Answer(
        text: json['text'] ?? '',
        attention: json['attention'] ?? false,
        media: (json['media'] as List<dynamic>?)
                ?.map((m) => MediaItem.fromJson(m))
                .toList() ??
            [],
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
  Map<String, Map<String, List<Answer>>> answers;
  Map<String, int> mediaCounter;
  int timestamp;
  String? folderPath;

  Report({
    this.reportName = '',
    this.availableLanguages = const [],
    this.currentLanguage = 'RU',
    this.questions = const [],
    this.answers = const {},
    this.mediaCounter = const {'photos': 1, 'X': 1},
    int? timestamp,
    this.folderPath,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  List<Answer> getAnswersForQuestion(int questionIndex, String langCode) {
    final qid = questionIndex.toString();
    if (!answers.containsKey(qid)) return [Answer()];
    if (!answers[qid]!.containsKey(langCode)) return [Answer()];
    return answers[qid]![langCode] ?? [Answer()];
  }

  bool hasAnswersInLanguage(int questionIndex, String langCode) {
    final answersList = getAnswersForQuestion(questionIndex, langCode);
    return answersList.any((a) => !a.isEmpty);
  }

  bool hasAnyAnswerInLanguage(int questionIndex, String langCode) {
    return hasAnswersInLanguage(questionIndex, langCode);
  }

  Map<String, dynamic> toJson() => {
        'reportName': reportName,
        'availableLanguages': availableLanguages,
        'currentLanguage': currentLanguage,
        'questions': questions.map((q) => q.toJson()).toList(),
        'answers': answers.map((k, v) => MapEntry(k, v.map((lk, lva) => MapEntry(lk, lva.map((a) => a.toJson()).toList())))),
        'mediaCounter': mediaCounter,
        'timestamp': timestamp,
      };

  factory Report.fromJson(Map<String, dynamic> json, {String? folderPath}) {
    final answersJson = json['answers'] as Map<String, dynamic>?;
    final answers = <String, Map<String, List<Answer>>>{};

    if (answersJson != null) {
      answersJson.forEach((qid, langMap) {
        if (langMap is Map) {
          answers[qid] = {};
          (langMap as Map<String, dynamic>).forEach((langCode, answersList) {
            if (answersList is List) {
              answers[qid]![langCode] = answersList.map((a) => Answer.fromJson(a)).toList();
            }
          });
        } else if (langMap is List) {
          answers[qid] = {'RU': langMap.map((a) => Answer.fromJson(a)).toList()};
        }
      });
    }

    return Report(
      reportName: json['reportName'] ?? '',
      availableLanguages: (json['availableLanguages'] as List<dynamic>?)?.cast<String>() ?? [],
      currentLanguage: json['currentLanguage'] ?? 'RU',
      questions: (json['questions'] as List<dynamic>?)
              ?.map((q) => Question.fromJson(q))
              .toList() ??
          [],
      answers: answers,
      mediaCounter: Map<String, int>.from(json['mediaCounter'] ?? {'photos': 1, 'X': 1}),
      timestamp: json['timestamp'],
      folderPath: folderPath,
    );
  }

  Report copyWith({
    String? reportName,
    List<String>? availableLanguages,
    String? currentLanguage,
    List<Question>? questions,
    Map<String, Map<String, List<Answer>>>? answers,
    Map<String, int>? mediaCounter,
    int? timestamp,
    String? folderPath,
  }) {
    return Report(
      reportName: reportName ?? this.reportName,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      currentLanguage: currentLanguage ?? this.currentLanguage,
      questions: questions ?? this.questions,
      answers: answers ?? this.answers,
      mediaCounter: mediaCounter ?? this.mediaCounter,
      timestamp: timestamp ?? this.timestamp,
      folderPath: folderPath ?? this.folderPath,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
