// Тесты для Report Sync Service (Фаза 6a рефакторинга).
//
// Покрывают чистые функции синхронизации переводов:
// getUnsyncQuestionIndices, reportNeedsSync, generateSyncJson,
// validateSyncJson, applySyncAnswers, clearAnswersInLanguage.

import 'dart:convert';

import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/services/report_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Создать тестовый отчёт с двумя языками (RU, EN) и одним вопросом.
Report _makeReport({
  List<String> languages = const ['RU', 'EN'],
  String currentLanguage = 'RU',
  Map<String, Map<String, List<TranslationAnswer>>>? translations,
}) {
  return Report(
    reportName: 'Test',
    availableLanguages: languages,
    currentLanguage: currentLanguage,
    questions: [Question(id: 1)],
    translations:
        translations ??
        {
          '0': {
            'RU': [TranslationAnswer(text: 'Да', isEmpty: false)],
            'EN': [TranslationAnswer(text: 'Yes', isEmpty: false)],
          },
        },
    markers: {
      '0': [AnswerMarkers()],
    },
  );
}

void main() {
  group('getUnsyncQuestionIndices', () {
    test('возвращает пустой список, когда все языки синхронизированы', () {
      final report = _makeReport();
      expect(getUnsyncQuestionIndices(report), isEmpty);
    });

    test('находит вопрос, где один язык пустой, а другой заполнен', () {
      final report = _makeReport(
        translations: {
          '0': {
            'RU': [TranslationAnswer(text: 'Да', isEmpty: false)],
            'EN': [TranslationAnswer()], // пустой перевод
          },
        },
      );
      expect(getUnsyncQuestionIndices(report), [0]);
    });

    test('игнорирует вопросы, где все языки пустые', () {
      final report = _makeReport(
        translations: {
          '0': {
            'RU': [TranslationAnswer()],
            'EN': [TranslationAnswer()],
          },
        },
      );
      expect(getUnsyncQuestionIndices(report), isEmpty);
    });
  });

  group('reportNeedsSync', () {
    test('false, когда текущий язык — первый в списке', () {
      final report = _makeReport(currentLanguage: 'RU');
      expect(reportNeedsSync(report), isFalse);
    });

    test('true, когда в текущем языке есть пробелы относительно первого', () {
      final report = _makeReport(
        currentLanguage: 'EN',
        translations: {
          '0': {
            'RU': [TranslationAnswer(text: 'Да', isEmpty: false)],
            'EN': [TranslationAnswer()],
          },
        },
      );
      expect(reportNeedsSync(report), isTrue);
    });

    test('false, когда текущий язык полностью заполнен', () {
      final report = _makeReport(currentLanguage: 'EN');
      expect(reportNeedsSync(report), isFalse);
    });
  });

  group('generateSyncJson', () {
    test('возвращает {} когда нечего синхронизировать', () {
      final report = _makeReport();
      expect(generateSyncJson(report), '{}');
    });

    test('генерирует JSON с вопросами, требующими перевода', () {
      final report = _makeReport(
        translations: {
          '0': {
            'RU': [TranslationAnswer(text: 'Да', isEmpty: false)],
            'EN': [TranslationAnswer()],
          },
        },
      );
      final json = generateSyncJson(report);
      final data = jsonDecode(json) as Map<String, dynamic>;

      expect(data['languages'], ['RU', 'EN']);
      final questions = data['questions'] as List;
      expect(questions, hasLength(1));
      expect(questions[0]['id'], 1);
      final answers = questions[0]['answers'] as List;
      expect(answers[0]['variants'], ['Да', '']);
    });
  });

  group('validateSyncJson', () {
    test('принимает валидную структуру', () {
      final valid = jsonEncode({
        'languages': ['RU', 'EN'],
        'questions': [
          {
            'id': 1,
            'answers': [
              {
                'id': 0,
                'variants': ['Да', 'Yes'],
              },
            ],
          },
        ],
      });
      expect(validateSyncJson(valid), isNotNull);
    });

    test('отклоняет JSON без обязательных ключей', () {
      expect(validateSyncJson('{"questions": []}'), isNull);
      expect(validateSyncJson('{"languages": []}'), isNull);
      expect(validateSyncJson('not json'), isNull);
    });

    test('отклоняет variants, не совпадающие по числу языков', () {
      final bad = jsonEncode({
        'languages': ['RU', 'EN'],
        'questions': [
          {
            'id': 1,
            'answers': [
              {
                'id': 0,
                'variants': ['Да'], // только 1 из 2 языков
              },
            ],
          },
        ],
      });
      expect(validateSyncJson(bad), isNull);
    });

    test('отклоняет некорректные типы id', () {
      final bad = jsonEncode({
        'languages': ['RU'],
        'questions': [
          {
            'id': 'one', // строка вместо int
            'answers': [],
          },
        ],
      });
      expect(validateSyncJson(bad), isNull);
    });
  });

  group('applySyncAnswers', () {
    test('возвращает false для невалидного JSON', () {
      final report = _makeReport();
      expect(applySyncAnswers(report, 'invalid'), isFalse);
    });

    test('применяет переводы к пустым ответам', () {
      final report = _makeReport(
        translations: {
          '0': {
            'RU': [TranslationAnswer(text: 'Да', isEmpty: false)],
            'EN': [TranslationAnswer()],
          },
        },
      );
      final syncJson = jsonEncode({
        'languages': ['RU', 'EN'],
        'questions': [
          {
            'id': 1,
            'answers': [
              {
                'id': 0,
                'variants': ['Да', 'Yes'],
              },
            ],
          },
        ],
      });

      expect(applySyncAnswers(report, syncJson), isTrue);
      expect(report.translations['0']!['EN']![0].text, 'Yes');
      expect(report.translations['0']!['EN']![0].isEmpty, isFalse);
    });

    test('не перезаписывает существующие ответы пустыми вариантами', () {
      final report = _makeReport();
      final syncJson = jsonEncode({
        'languages': ['RU', 'EN'],
        'questions': [
          {
            'id': 1,
            'answers': [
              {
                'id': 0,
                'variants': ['', 'Yes'], // RU пустой — не должен затереть 'Да'
              },
            ],
          },
        ],
      });

      expect(applySyncAnswers(report, syncJson), isTrue);
      expect(report.translations['0']!['RU']![0].text, 'Да');
      expect(report.translations['0']!['EN']![0].text, 'Yes');
    });

    test('сохраняет медиа и флаги attention при применении', () {
      final report = _makeReport();
      report.markers['0']![0].attention = true;
      report.markers['0']![0].media = [
        MediaItem(type: 'image', name: 'photo.jpg'),
      ];

      final syncJson = jsonEncode({
        'languages': ['RU', 'EN'],
        'questions': [
          {
            'id': 1,
            'answers': [
              {
                'id': 0,
                'variants': ['Да', 'Yes'],
              },
            ],
          },
        ],
      });

      expect(applySyncAnswers(report, syncJson), isTrue);
      expect(report.markers['0']![0].attention, isTrue);
      expect(report.markers['0']![0].media, hasLength(1));
      expect(report.markers['0']![0].media[0].name, 'photo.jpg');
    });
  });

  group('clearAnswersInLanguage', () {
    test('очищает ответы только в указанном языке', () {
      final report = _makeReport();
      clearAnswersInLanguage(report, 'EN');

      expect(report.translations['0']!['EN']![0].text, '');
      expect(report.translations['0']!['EN']![0].isEmpty, isTrue);
      // RU не тронут
      expect(report.translations['0']!['RU']![0].text, 'Да');
    });
  });
}
