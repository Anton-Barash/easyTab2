// ============================================================
// Report Sync Service — синхронизация переводов ответов через JSON.
//
// Вынесено из ReportState (Фаза 2b рефакторинга). Чистые функции:
// принимают Report, не зависят от состояния провайдера.
// Мутирующие функции (applySyncAnswers, clearAnswersInLanguage)
// изменяют переданный Report; вызывающий код обязан уведомить UI.
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/report_models.dart';

/// Индексы вопросов, где ответы не синхронизированы между языками.
List<int> getUnsyncQuestionIndices(Report report) {
  final unsyncIndices = <int>[];
  final languages = report.availableLanguages;

  // #3: без языков сравнивать нечего — languages.first ниже упал бы StateError.
  if (languages.isEmpty) return unsyncIndices;

  for (int i = 0; i < report.questions.length; i++) {
    int maxCount = 0;
    int minCount = 0;
    final allAnswers = <String, List<Map<String, dynamic>>>{};

    for (final lang in languages) {
      final answers = report.getAnswersForQuestion(i, lang);
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

/// Есть ли в текущем языке пустые ответы, заполненные в первом языке.
bool reportNeedsSync(Report report) {
  final languages = report.availableLanguages;
  if (languages.isEmpty) return false;
  if (report.currentLanguage == languages.first) return false;

  for (int i = 0; i < report.questions.length; i++) {
    final firstLangAnswers = report.getAnswersForQuestion(i, languages.first);
    final currentLangAnswers = report.getAnswersForQuestion(
      i,
      report.currentLanguage,
    );

    for (int j = 0; j < firstLangAnswers.length; j++) {
      final firstLangAnswer =
          firstLangAnswers[j]['text']?.toString().trim() ?? '';
      final currentLangAnswer = j < currentLangAnswers.length
          ? currentLangAnswers[j]['text']?.toString().trim() ?? ''
          : '';

      if (firstLangAnswer.isNotEmpty && currentLangAnswer.isEmpty) {
        return true;
      }
    }
  }
  return false;
}

/// JSON с несинхронизированными вопросами для отправки в ИИ-переводчик.
String generateSyncJson(Report report) {
  final unsyncIndices = getUnsyncQuestionIndices(report);
  if (unsyncIndices.isEmpty) return '{}';

  final data = <String, dynamic>{
    'languages': report.availableLanguages,
    'questions': <Map<String, dynamic>>[],
  };

  for (final idx in unsyncIndices) {
    final q = report.questions[idx];
    final answerVariants = <List<String>>[];

    for (final lang in report.availableLanguages) {
      final answers = report.getAnswersForQuestion(idx, lang);
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
      // Включаем ответ если есть хотя бы один непустой текст (для перевода)
      final hasNonEmpty = variant.any((text) => text.isNotEmpty);
      if (hasNonEmpty) {
        answersWithId.add({'id': answerIdx, 'variants': variant});
      }
    }

    if (answersWithId.isNotEmpty) {
      (data['questions'] as List).add({'id': q.id, 'answers': answersWithId});
    }
  }

  return const JsonEncoder.withIndent('  ').convert(data);
}

// M-30: лимиты для validateSyncJson — защита от гигантских/некорректных payload.
const int _maxSyncLanguages = 32;
const int _maxSyncQuestions = 2000;
const int _maxSyncAnswersPerQuestion = 2000;
const int _maxSyncVariantLength = 50000;

/// Проверить структуру sync-JSON. Возвращает данные или null при ошибке.
Map<String, dynamic>? validateSyncJson(String jsonStr) {
  try {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (!data.containsKey('languages')) return null;
    if (!data.containsKey('questions')) return null;

    final languagesRaw = data['languages'];
    if (languagesRaw is! List) return null;
    if (languagesRaw.isEmpty || languagesRaw.length > _maxSyncLanguages) {
      return null;
    }
    // Каждая запись языка — непустая строка.
    for (final lang in languagesRaw) {
      if (lang is! String || lang.isEmpty) return null;
    }
    final languages = languagesRaw.cast<String>();

    final questionsRaw = data['questions'];
    if (questionsRaw is! List) return null;
    if (questionsRaw.length > _maxSyncQuestions) return null;

    for (final q in questionsRaw) {
      if (q is! Map) return null;
      // id должен быть int.
      final id = q['id'];
      if (id is! int) return null;
      if (!q.containsKey('answers')) return null;

      final answers = q['answers'];
      if (answers is! List) return null;
      if (answers.length > _maxSyncAnswersPerQuestion) return null;

      for (final answer in answers) {
        if (answer is! Map) return null;
        final answerId = answer['id'];
        if (answerId is! int) return null;
        if (!answer.containsKey('variants')) return null;

        final variants = answer['variants'];
        if (variants is! List) return null;
        if (variants.length != languages.length) return null;
        // Каждый вариант — строка ограниченной длины.
        for (final v in variants) {
          if (v is! String) return null;
          if (v.length > _maxSyncVariantLength) return null;
        }
      }
    }

    return data;
  } catch (e) {
    return null;
  }
}

/// Очистить все ответы в указанном языке (мутирует report).
void clearAnswersInLanguage(Report report, String langCode) {
  for (int i = 0; i < report.questions.length; i++) {
    final qid = i.toString();
    if (report.translations.containsKey(qid)) {
      report.translations[qid]![langCode] = [TranslationAnswer()];
    }
  }
}

/// Применить переведённые ответы из sync-JSON (мутирует report).
/// Возвращает true, если JSON валиден и применён.
bool applySyncAnswers(Report report, String jsonStr) {
  final data = validateSyncJson(jsonStr);
  if (data == null) {
    if (kDebugMode) {
      debugPrint('applySyncAnswers: validateSyncJson returned null');
    }
    return false;
  }

  // Сохраняем языки из JSON, чтобы сопоставить варианты
  final jsonLanguages = (data['languages'] as List).cast<String>();
  // Используем языки ИЗ ОТЧЕТА для обновления
  final languages = report.availableLanguages;
  final questions = data['questions'] as List;

  if (kDebugMode) {
    debugPrint('applySyncAnswers START: jsonLanguages=$jsonLanguages');
    debugPrint('applySyncAnswers START: reportLanguages=$languages');
    debugPrint('applySyncAnswers START: questions count=${questions.length}');
  }

  for (final qData in questions) {
    final questionId = qData['id'] as int;
    final answers = qData['answers'] as List;

    final qIndex = report.questions.indexWhere((q) => q.id == questionId);
    if (qIndex == -1) continue;

    final qid = qIndex.toString();

    // Collect all attention flags across all languages for this question
    final allAttentionFlags = <bool>[];
    final markersList = report.markers[qid] ?? [];
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

    // Ensure translations map exists for this question
    if (!report.translations.containsKey(qid)) {
      report.translations[qid] = {};
    }

    // Initialize all languages with empty answers if not exists
    for (final lang in report.availableLanguages) {
      if (!report.translations[qid]!.containsKey(lang)) {
        report.translations[qid]![lang] = [];
      }
    }

    // Update translations for all languages in sync data
    for (final answerData in answers) {
      final answerId = answerData['id'] as int;
      final texts = (answerData['variants'] as List).cast<String>();

      if (kDebugMode) {
        debugPrint(
          'applySyncAnswers: qid=$qid, answerId=$answerId, texts=$texts',
        );
      }

      for (final lang in languages) {
        // Найдем индекс языка в JSON языках
        final jsonLangIndex = jsonLanguages.indexOf(lang);
        if (jsonLangIndex == -1) {
          if (kDebugMode) {
            debugPrint(
              'applySyncAnswers: lang=$lang not found in jsonLanguages',
            );
          }
          continue; // Язык не найден в JSON, пропускаем
        }

        final text = jsonLangIndex < texts.length ? texts[jsonLangIndex] : '';
        final answersList = report.translations[qid]![lang]!;

        // Skip empty texts — don't overwrite existing non-empty answers
        if (text.isEmpty) continue;

        if (answerId < answersList.length) {
          answersList[answerId] = TranslationAnswer(
            text: text,
            isEmpty: false,
          );
        } else {
          while (answersList.length < answerId) {
            answersList.add(TranslationAnswer());
          }
          answersList.add(TranslationAnswer(text: text, isEmpty: false));
        }
      }
    }

    // Update markers with consistent attention flags and preserved media
    if (!report.markers.containsKey(qid)) {
      report.markers[qid] = [];
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

      if (answerId < report.markers[qid]!.length) {
        report.markers[qid]![answerId].attention = attention;
        report.markers[qid]![answerId].media = media;
      } else {
        report.markers[qid]!.add(
          AnswerMarkers(attention: attention, media: media),
        );
      }
    }
  }

  return true;
}
