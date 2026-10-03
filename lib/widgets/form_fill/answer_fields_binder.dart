import 'dart:async';

import 'package:easy_tab/models/report_models.dart';
import 'package:flutter/material.dart';

/// Запись набранного текста в модель отчёта.
///
/// [language] — язык ячейки, в которую нужно записать текст (всегда текущий
/// язык отчёта). Передача языка явно защищает от затирания переводов в других
/// языках при сбросе набранного текста.
typedef AnswerTextCommitter = void Function(
  int questionIndex,
  int answerIndex,
  String text,
  String language,
);

/// Связывает поля ввода ответов с моделью отчёта.
///
/// Отвечает за:
/// * создание/уничтожение `TextEditingController` по рядам вопросов;
/// * дебаунс набора текста: правка уходит в модель после паузы в наборе;
/// * применение изменений модели в поля (синхронизация с сервером, pull);
/// * аварийный сброс набранного, но ещё не записанного в модель текста.
///
/// Выделено из `_FormFillScreenState`, чтобы логику ввода можно было покрыть
/// unit-тестами без сборки всего экрана. Ключевые инварианты:
///
/// 1. Таймер отложенной правки снимается ТОЛЬКО когда ряд исчезает из модели
///    (удаление ответа/вопроса), но не при обычной синхронизации — иначе
///    правка терялась, а текст в поле затирался устаревшей версией.
/// 2. Поле НЕ перезаписывается моделью, пока в нём есть незакоммиченная
///    правка: локальный ввод пользователя приоритетнее пришедшего с сервера.
/// 3. Курсор не прыгает в конец текста при программном обновлении поля.
/// 4. Сброс (`flush`) находит расхождения «поле ↔ модель», а не только
///    активные таймеры, поэтому быстрый набор не теряется при сохранении.
class AnswerFieldsBinder {
  AnswerFieldsBinder({
    this.commitDelay = const Duration(milliseconds: 300),
  });

  /// Пауза в наборе, после которой текст записывается в модель.
  final Duration commitDelay;

  final Map<String, Map<int, TextEditingController>> _controllers = {};
  final Map<String, Map<int, Timer?>> _timers = {};

  /// Язык отчёта на момент последней синхронизации полей (ключ qid → индекс).
  /// Нужен, чтобы понять, что язык переключили уже после создания слушателя.
  final Map<String, Map<int, String>> _langs = {};

  /// Текст поля, соответствующий модели (ключ qid → индекс). Нужен, чтобы
  /// отличать набор текста от простого перемещения курсора: слушатель
  /// контроллера срабатывает и на смену выделения, но такая «правка» не
  /// должна создавать дебаунс и блокировать синхронизацию полей.
  final Map<String, Map<int, String>> _modelTexts = {};

  /// Запись набранного текста в модель.
  AnswerTextCommitter? onCommit;

  /// Признак «ответ переведён в другие языки» (тогда поле только для чтения).
  void Function(String qid, int answerIndex, bool enabled)? onAvailability;

  bool _isUpdating = false;

  /// Контроллер поля qid/answerIndex, если он уже создан.
  TextEditingController? controller(String qid, int answerIndex) =>
      _controllers[qid]?[answerIndex];

  /// Есть ли незакоммиченная правка в конкретном поле.
  bool hasPendingEdit(String qid, int answerIndex) =>
      _timers[qid]?[answerIndex]?.isActive ?? false;

  /// Уничтожить поле конкретного ряда (перед удалением ответа из модели).
  ///
  /// Отменяет отложенный таймер и dispose'ит контроллер, чтобы удаляемый ряд
  /// не пережил своё удаление и не записал текст обратно в модель.
  void disposeAnswer(String qid, int answerIndex) {
    _timers[qid]?[answerIndex]?.cancel();
    _timers[qid]?.remove(answerIndex);
    _langs[qid]?.remove(answerIndex);
    _modelTexts[qid]?.remove(answerIndex);
    _controllers[qid]?[answerIndex]?.dispose();
    _controllers[qid]?.remove(answerIndex);
  }

  bool get hasPendingEdits =>
      _timers.values.any((m) => m.values.any((t) => t?.isActive ?? false));

  /// Тексты ряда вопроса в текущем языке — дешёвая альтернатива
  /// [Report.getAnswersForQuestion].
  ///
  /// [Report.getAnswersForQuestion] аллоцирует `Map` для каждой строки каждого
  /// вопроса, а синхронизация выполняется на каждый `notifyListeners()` (в т.ч.
  /// на тиках прогресса загрузки). На отчётах с сотнями вопросов это
  /// подвешивало ввод. Здесь нужны только текст и число строк, поэтому модель
  /// читается напрямую с сохранением семантики «фантомной» строки ввода.
  static List<String> answerTexts(Report report, int questionIndex) {
    final qid = questionIndex.toString();
    final lang = report.currentLanguage;
    final langAnswers = report.translations[qid]?[lang] ?? const [];
    final langMarkers = report.markers[qid] ?? const [];
    final rowCount = langAnswers.length > langMarkers.length
        ? langAnswers.length
        : langMarkers.length;
    if (rowCount == 0) return const [''];
    return List<String>.generate(
      rowCount,
      (r) => r < langAnswers.length ? langAnswers[r].text : '',
    );
  }

  /// Расходится ли текст хотя бы одного поля с моделью отчёта.
  ///
  /// Проверяет не только активные таймеры, но и само расхождение: таймер мог
  /// быть уже снят, а текст так и не попал в модель.
  bool hasModelDiff(Report report) {
    final lang = report.currentLanguage;
    for (final entry in _controllers.entries) {
      final answers = report.translations[entry.key]?[lang];
      if (answers == null) continue;
      for (final cell in entry.value.entries) {
        final j = cell.key;
        if (j >= answers.length) continue;
        if (cell.value.text != answers[j].text) return true;
      }
    }
    return false;
  }

  /// Синхронизировать набор полей с моделью.
  ///
  /// [hasTranslationsInOtherLanguages] отвечает, есть ли у ряда ответы в других
  /// языках (такое поле блокируется для правки).
  void sync(
    Report report, {
    bool Function(int questionIndex, int answerIndex)?
        hasTranslationsInOtherLanguages,
  }) {
    for (int i = 0; i < report.questions.length; i++) {
      final qid = i.toString();
      final answers = answerTexts(report, i);
      _controllers.putIfAbsent(qid, () => {});
      _timers.putIfAbsent(qid, () => {});

      // Таймер отложенной правки снимается ТОЛЬКО когда ряд исчез из модели.
      // Раньше отмена выполнялась на каждой синхронизации (то есть на любом
      // notifyListeners()), из-за чего правка не попадала в модель, а текст в
      // поле затирался устаревшей версией — пользователь терял набранный текст.
      for (final j in _controllers[qid]!.keys.toList()) {
        if (j >= answers.length) {
          _timers[qid]![j]?.cancel();
          _timers[qid]!.remove(j);
          _langs[qid]?.remove(j);
          _controllers[qid]![j]!.dispose();
          _controllers[qid]!.remove(j);
        }
      }

      for (int j = 0; j < answers.length; j++) {
        final lang = report.currentLanguage;
        if (!_controllers[qid]!.containsKey(j)) {
          final controller = TextEditingController(text: answers[j]);
          _controllers[qid]![j] = controller;
          _modelTexts.putIfAbsent(qid, () => {})[j] = answers[j];
          // Язык фиксируется в момент создания слушателя: если пользователь
          // успел переключить язык, отложенная правка не должна уйти в чужую
          // языковую ячейку.
          final listenerLang = lang;
          _langs.putIfAbsent(qid, () => {})[j] = lang;
          controller.addListener(() {
            if (_isUpdating) return;
            // Перемещение курсора (тап по тексту, выделение) тоже вызывает
            // слушатель. Без этой проверки тап посреди слова на 300 мс
            // блокировал применение изменений модели и помечал экран
            // несохранённым без реальной правки.
            if (controller.text == _modelTexts[qid]?[j]) return;
            _timers[qid]![j]?.cancel();
            _timers[qid]![j] = Timer(commitDelay, () {
              // Язык сменился после создания слушателя — правка устарела,
              // не пишем её в другую языковую ячейку.
              if (_langs[qid]![j] != listenerLang) return;
              final text = _controllers[qid]?[j]?.text ?? '';
              _timers[qid]!.remove(j);
              // Текст уходит в модель — дальше он эталонный.
              _modelTexts[qid]?[j] = text;
              onCommit?.call(i, j, text, listenerLang);
            });
          });
        } else {
          _langs[qid]![j] = lang;
          final controller = _controllers[qid]![j]!;
          final newText = answers[j];
          // Пока правка ещё «в дебаунсе» и не попала в модель, локальный
          // текст пользователя приоритетнее: иначе внешний notifyListeners()
          // затирал бы неотправленный ввод и буквы пропадали.
          if (controller.text != newText && !hasPendingEdit(qid, j)) {
            _isUpdating = true;
            try {
              // Курсор не должен прыгать в конец текста: иначе при правке в
              // середине слова символы «уезжали» в конец и казались
              // пропущенными. Смещение сохраняем, ограничивая новой длиной.
              final oldOffset = controller.selection.baseOffset;
              final keepOffset =
                  oldOffset >= 0 && oldOffset <= newText.length
                      ? oldOffset
                      : newText.length;
              controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: keepOffset),
              );
            } finally {
              _isUpdating = false;
            }
            _modelTexts[qid]![j] = newText;
          }
        }

        final enabled = hasTranslationsInOtherLanguages == null
            ? true
            : !hasTranslationsInOtherLanguages(i, j);
        onAvailability?.call(qid, j, enabled);
      }
    }
  }

  /// Записать в модель весь набранный, но ещё не записанный текст.
  ///
  /// Вызывается перед сохранением и перед получением серверной версии:
  /// pull затирал бы локальные правки, которые не успели уйти в модель.
  void flush(Report report) {
    final lang = report.currentLanguage;
    // Уже записанные ячейки: таймерная и файловая итерации пересекаются,
    // и без дедупликации одна ячейка ушла бы в модель дважды.
    final done = <String>{};

    // Ключи копируем в списки: внутри цикла изменяются сами мапы.
    for (final qid in _timers.keys.toList()) {
      final qIndex = int.tryParse(qid);
      if (qIndex == null) continue;
      for (final j in _timers[qid]!.keys.toList()) {
        _timers[qid]![j]?.cancel();
        _commitCell(report, qIndex, qid, j, lang, done);
      }
    }

    // Догоняем ячейки, чей таймер уже снят (например, синхронизацией полей):
    // раньше такой текст оставался только в поле и при сохранении не уходил
    // в отчёт.
    for (final qid in _controllers.keys.toList()) {
      final qIndex = int.tryParse(qid);
      if (qIndex == null) continue;
      for (final j in _controllers[qid]!.keys.toList()) {
        _commitCell(report, qIndex, qid, j, lang, done);
      }
    }
  }

  /// Записать текст конкретного поля, если он разошёлся с моделью.
  void _commitCell(
    Report report,
    int qIndex,
    String qid,
    int j,
    String lang,
    Set<String> done,
  ) {
    if (!done.add('$qid:$j')) return;
    final controller = _controllers[qid]?[j];
    if (controller == null) return;
    final text = controller.text;
    // Текст попал (или уже был) в модели — он становится эталонным для
    // сравнения в слушателе.
    _modelTexts.putIfAbsent(qid, () => {})[j] = text;
    final answers = report.translations[qid]?[lang];
    if (answers != null && j < answers.length && answers[j].text == text) {
      return;
    }
    onCommit?.call(qIndex, j, text, lang);
    _timers[qid]?.remove(j);
  }

  void dispose() {
    for (final timers in _timers.values) {
      for (final timer in timers.values) {
        timer?.cancel();
      }
    }
    _timers.clear();
    for (final controllers in _controllers.values) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    _controllers.clear();
    _langs.clear();
    _modelTexts.clear();
  }
}
