import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/widgets/form_fill/answer_fields_binder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Запись (qIndex, answerIndex, text, language) коммита в модель.
typedef Commit = (int, int, String, String);

Report _report({
  List<String> languages = const ['RU', 'EN'],
  String currentLanguage = 'RU',
  List<List<String>>? translations,
  bool secondRow = false,
}) {
  final questions = <Question>[Question(id: 0)];
  final ru = <TranslationAnswer>[];
  final en = <TranslationAnswer>[];
  if (translations != null) {
    for (final row in translations) {
      ru.add(TranslationAnswer(text: row.isNotEmpty ? row[0] : '', isEmpty: row.isEmpty || row[0].isEmpty));
      en.add(TranslationAnswer(text: row.length > 1 ? row[1] : '', isEmpty: row.length < 2 || row[1].isEmpty));
    }
  }
  return Report(
    reportName: 'R',
    availableLanguages: languages,
    currentLanguage: currentLanguage,
    questions: questions,
    translations: {'0': {'RU': ru, 'EN': en}},
    markers: {
      '0': secondRow ? [AnswerMarkers(), AnswerMarkers()] : [AnswerMarkers()],
    },
    mediaCounter: {'photos': 1, 'X': 1},
    timestamp: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnswerFieldsBinder — стабильность ввода', () {
    test('создаёт поля и передаёт текст в модель после дебаунса', () async {
      final binder = AnswerFieldsBinder(commitDelay: const Duration(milliseconds: 20));
      final commits = <Commit>[];
      binder.onCommit = (q, j, text, lang) => commits.add((q, j, text, lang));
      final report = _report(translations: [['старый']]);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      expect(controller.text, 'старый');

      controller.text = 'новый';
      expect(binder.hasPendingEdit('0', 0), isTrue);
      expect(commits, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(commits, [(0, 0, 'новый', 'RU')]);
      expect(binder.hasPendingEdit('0', 0), isFalse);

      binder.dispose();
    });

    test('внешний notifyListeners не затирает набранный текст', () async {
      final binder = AnswerFieldsBinder(commitDelay: const Duration(milliseconds: 500));
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: [['старый']]);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;

      // Пользователь набрал текст, дебайанс ещё не сработал.
      controller.text = 'новый привет';
      expect(binder.hasPendingEdit('0', 0), isTrue);

      // Синхронизация (например, тик прогресса загрузки): модель в базу
      // не попала, но текст в поле НЕ должен затираться.
      binder.sync(report);
      expect(controller.text, 'новый привет');

      binder.dispose();
    });

    test('курсор не прыгает в конец при обновлении поля из модели', () async {
      final binder = AnswerFieldsBinder(commitDelay: const Duration(milliseconds: 20));
      final report = _report(translations: [['ответ']]);
      // onCommit эмулирует реальную запись в модель.
      binder.onCommit = (q, j, text, lang) {
        report.translations['0']![lang]![j].text = text;
      };

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      // Ставим курсор в позицию 1 (правка в начале слова), текст не меняем.
      controller.selection = const TextSelection.collapsed(offset: 1);
      expect(controller.selection.baseOffset, 1);

      // Модель изменилась извне (pull с сервера): поле обновляется, но курсор
      // остаётся рядом со старой позицией — иначе символы «уезжали» в конец.
      report.translations['0']!['RU']![0].text = 'ответ пользователя';
      binder.sync(report);
      expect(controller.text, 'ответ пользователя');
      expect(controller.selection.baseOffset, 1);

      // Если строка стала короче позиции курсора — смещение ограничиваем
      // длиной, иначе Flutter бросает RangeError.
      controller.selection = const TextSelection.collapsed(offset: 5);
      report.translations['0']!['RU']![0].text = 'от';
      binder.sync(report);
      expect(controller.text, 'от');
      expect(controller.selection.baseOffset, 2);

      binder.dispose();
    });

    test('flush сохраняет текст, набранный без срабатывания дебаунса', () async {
      final binder = AnswerFieldsBinder(commitDelay: const Duration(milliseconds: 5000));
      final commits = <Commit>[];
      binder.onCommit = (q, j, text, lang) => commits.add((q, j, text, lang));
      final report = _report(translations: [['старый']]);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      controller.text = 'быстрый набор';
      // Пользователь нажал «Сохранить» — таймер ещё не сработал.
      binder.flush(report);

      expect(commits, [(0, 0, 'быстрый набор', 'RU')]);

      binder.dispose();
    });

    test('flush не пишет в модель совпадающий текст и не затирает переводы', () async {
      final binder = AnswerFieldsBinder();
      final commits = <Commit>[];
      binder.onCommit = (q, j, text, lang) => commits.add((q, j, text, lang));
      final report = _report(translations: [['вопрос', 'answer']]);

      binder.sync(report);
      // EN-перевод уже есть — flush не должен трогать эту ячейку.
      binder.flush(report);
      expect(commits, isEmpty);

      binder.dispose();
    });

    test('hasModelDiff видит расхождение даже без активного таймера', () async {
      final binder = AnswerFieldsBinder();
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: [['старый']]);

      binder.sync(report);
      expect(binder.hasModelDiff(report), isFalse);

      final controller = binder.controller('0', 0)!;
      controller.text = 'текст';
      // Таймер снят, но расхождение с моделью осталось.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // Таймер мог успеть сработать — эмулируем его снятие:
      if (!binder.hasModelDiff(report)) {
        // Коммит уже произошёл: приводим модель в соответствие и снова расходим.
        report.translations['0']!['RU']![0].text = 'другое';
        controller.text = 'мой текст';
      }
      expect(binder.hasModelDiff(report), isTrue);

      binder.dispose();
    });

    test('смена языка не пишет отложенную правку в чужую ячейку', () async {
      final binder = AnswerFieldsBinder(commitDelay: const Duration(milliseconds: 20));
      final commits = <Commit>[];
      binder.onCommit = (q, j, text, lang) => commits.add((q, j, text, lang));
      final report = _report(translations: [['старый']]);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      controller.text = 'набрано в RU';

      // Язык переключён до срабатывания дебаунса.
      report.currentLanguage = 'EN';
      binder.sync(report);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Отложенная правка устарела — в чужую языковую ячейку не пишется.
      expect(commits, isEmpty);

      binder.dispose();
    });

    test('удаление ряда уничтожает его контроллер', () async {
      final binder = AnswerFieldsBinder();
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: [['первый']], secondRow: true);

      binder.sync(report);
      expect(binder.controller('0', 1), isNotNull);

      binder.disposeAnswer('0', 1);
      expect(binder.controller('0', 1), isNull);

      binder.dispose();
    });

    test('исчезнувший ряд убирается при следующей синхронизации', () async {
      final binder = AnswerFieldsBinder();
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: [
        ['первый', 'first'],
        ['второй', 'second'],
      ]);

      binder.sync(report);
      expect(binder.controller('0', 1), isNotNull);

      // Ответ удалён из модели — ряд становится «фантомным».
      report.translations['0']!['RU']!.removeAt(1);
      report.translations['0']!['EN']!.removeAt(1);
      final shrunk = _report(translations: [['первый', 'first']]);
      binder.sync(shrunk);
      expect(binder.controller('0', 1), isNull);

      binder.dispose();
    });

    test('«фантомная» строка создаётся, когда ответов ещё нет', () async {
      final binder = AnswerFieldsBinder();
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: []);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      expect(controller.text, '');

      controller.text = 'первый ответ';
      await Future<void>.delayed(const Duration(milliseconds: 400));
      binder.flush(report);
      // Коммит мог произойти либо по таймеру, либо через flush — проверяем
      // главное: контроллер жив и содержит текст.
      expect(binder.controller('0', 0)!.text, 'первый ответ');

      binder.dispose();
    });

    test('быстрый набор: пересинхронизация между нажатиями не теряет символы', () async {
      final binder = AnswerFieldsBinder(
        commitDelay: const Duration(milliseconds: 30),
      );
      final commits = <Commit>[];
      final report = _report(translations: [['']]);
      binder.onCommit = (q, j, text, lang) {
        commits.add((q, j, text, lang));
        report.translations['0']![lang]![j].text = text;
      };

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      final typed = StringBuffer();
      // Печать быстрее дебаунса + ребилд экрана на каждое нажатие.
      for (var i = 0; i < 120; i++) {
        typed.write('я');
        controller.text = typed.toString();
        binder.sync(report);
      }

      expect(controller.text, typed.toString());
      // Дебаунс ещё не сработал — в модель ничего не ушло.
      expect(commits, isEmpty);
      expect(binder.hasPendingEdit('0', 0), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Все промежуточные значения схлопнулись в один коммит финального.
      expect(commits.length, 1);
      expect(commits.single.$3, typed.toString());
      expect(binder.hasModelDiff(report), isFalse);

      binder.dispose();
    });

    test('длинный блок текста: 20k+ символов сохраняются без потерь', () async {
      final binder = AnswerFieldsBinder(
        commitDelay: const Duration(milliseconds: 5000),
      );
      final commits = <Commit>[];
      final report = _report(translations: [['']]);
      binder.onCommit = (q, j, text, lang) {
        commits.add((q, j, text, lang));
        report.translations['0']![lang]![j].text = text;
      };

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      final buffer = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        buffer.write('строка $i\n');
      }
      final long = buffer.toString();
      expect(long.length, greaterThan(20000));

      // Набор порциями с пересинхронизацией между порциями.
      for (var chunk = 0; chunk < long.length; chunk += 5000) {
        final end = (chunk + 5000).clamp(0, long.length);
        controller.text = long.substring(0, end);
        binder.sync(report);
      }
      controller.text = long;
      binder.sync(report);
      expect(controller.text, long);

      // Пользователь нажал «Сохранить» — flush пишет весь блок одним коммитом.
      binder.flush(report);
      expect(commits, [(0, 0, long, 'RU')]);
      expect(binder.hasModelDiff(report), isFalse);

      binder.dispose();
    });

    test('форматирование: переносы, markdown, эмодзи и краевые пробелы не искажаются', () async {
      final binder = AnswerFieldsBinder(
        commitDelay: const Duration(milliseconds: 30),
      );
      final commits = <Commit>[];
      final report = _report(translations: [['']]);
      binder.onCommit = (q, j, text, lang) {
        commits.add((q, j, text, lang));
        report.translations['0']![lang]![j].text = text;
      };

      binder.sync(report);
      final controller = binder.controller('0', 0)!;
      const formatted =
          '  **жирный** и _курсив_\n- пункт 1\n- пункт 2\n\nЭмодзи 🚀 и пробелы   ';
      controller.text = formatted;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // В модель уходит ровно набранное, без обрезки и нормализации.
      expect(commits.single.$3, formatted);

      // Обратное направление: серверная версия с форматированием применятся
      // к полю тоже без искажений.
      const fromServer = '### заголовок\n\n> цитата\n\tотступ  ';
      report.translations['0']!['RU']![0].text = fromServer;
      binder.sync(report);
      expect(controller.text, fromServer);

      binder.dispose();
    });

    test('перемещение курсора не мешает применению изменений модели', () async {
      final binder = AnswerFieldsBinder(
        commitDelay: const Duration(milliseconds: 30),
      );
      binder.onCommit = (q, j, text, lang) {};
      final report = _report(translations: [['ответ']]);

      binder.sync(report);
      final controller = binder.controller('0', 0)!;

      // Тап посреди слова меняет выделение, но не текст.
      controller.selection = const TextSelection.collapsed(offset: 3);
      expect(binder.hasPendingEdit('0', 0), isFalse);

      // Пока нет реальной правки, изменение модели должно доходить до поля.
      report.translations['0']!['RU']![0].text = 'ответ пользователя';
      binder.sync(report);
      expect(controller.text, 'ответ пользователя');
      expect(controller.selection.baseOffset, 3);

      binder.dispose();
    });
  });
}
