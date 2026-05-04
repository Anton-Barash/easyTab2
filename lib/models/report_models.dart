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

class Question {
  int id;
  String text;
  String type;

  Question({
    required this.id,
    this.text = '',
    this.type = 'text',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'type': type,
      };

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] ?? 0,
        text: json['text'] ?? '',
        type: json['type'] ?? 'text',
      );
}

class Report {
  String reportName;
  List<Question> questions;
  Map<String, List<Answer>> answers;
  Map<String, int> mediaCounter;
  int timestamp;
  String? folderPath;

  Report({
    this.reportName = '',
    this.questions = const [],
    this.answers = const {},
    this.mediaCounter = const {'photos': 1, 'X': 1},
    int? timestamp,
    this.folderPath,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'reportName': reportName,
        'questions': questions.map((q) => q.toJson()).toList(),
        'answers': answers.map((k, v) => MapEntry(k, v.map((a) => a.toJson()).toList())),
        'mediaCounter': mediaCounter,
        'timestamp': timestamp,
      };

  factory Report.fromJson(Map<String, dynamic> json, {String? folderPath}) => Report(
        reportName: json['reportName'] ?? '',
        questions: (json['questions'] as List<dynamic>?)
                ?.map((q) => Question.fromJson(q))
                .toList() ??
            [],
        answers: (json['answers'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(
                  k, (v as List<dynamic>).map((a) => Answer.fromJson(a)).toList()),
            ) ??
            {},
        mediaCounter: Map<String, int>.from(json['mediaCounter'] ?? {'photos': 1, 'X': 1}),
        timestamp: json['timestamp'],
        folderPath: folderPath,
      );

  @override
  String toString() => jsonEncode(toJson());
}
