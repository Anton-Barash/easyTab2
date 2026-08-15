import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/services/report_html_service.dart';
import 'package:flutter_test/flutter_test.dart';

Report _buildReport() {
  return Report(
    reportName: 'Завод <Test> (Аэрогриль) X-1',
    availableLanguages: ['RU', 'EN'],
    currentLanguage: 'RU',
    questions: [
      Question(
        id: 0,
        localizations: {
          'RU': QuestionLocalization(name: 'Внешний вид'),
          'EN': QuestionLocalization(name: 'Appearance'),
        },
      ),
    ],
    translations: {
      '0': {
        'RU': [TranslationAnswer(text: 'Царапина на корпусе', isEmpty: false)],
        'EN': [TranslationAnswer(text: 'Scratch on body', isEmpty: false)],
      },
    },
    markers: {
      '0': [
        AnswerMarkers(
          media: [
            MediaItem(
              name: 'f1_1_001.jpg',
              type: 'image/jpeg',
              localPath: 'photos/f1_1_001.jpg',
            ),
            MediaItem(
              name: 'v1_1_002.mp4',
              type: 'video/mp4',
              localPath: 'photos/v1_1_002.mp4',
            ),
          ],
        ),
      ],
    },
    timestamp: 1700000000000,
    factory: 'Фабрика А',
    model: 'X-1',
  );
}

void main() {
  group('generateReportHtml', () {
    test('contains escaped report name, questions and answers', () {
      final html = generateReportHtml(_buildReport());

      // Имя отчёта экранировано (XSS-защита).
      expect(html.contains('Завод &lt;Test&gt;'), isTrue);
      expect(html.contains('<Test>'), isFalse);
      // Вопросы и ответы на обоих языках присутствуют.
      expect(html.contains('Внешний вид'), isTrue);
      expect(html.contains('Appearance'), isTrue);
      expect(html.contains('Царапина на корпусе'), isTrue);
      expect(html.contains('Scratch on body'), isTrue);
      // Шапка отчёта.
      expect(html.contains('Фабрика А'), isTrue);
      expect(html.contains('X-1'), isTrue);
    });

    test('references media by relative archive paths', () {
      final html = generateReportHtml(_buildReport());

      // Медиа подключаются относительными путями, как в ZIP-архиве.
      expect(html.contains('photos/f1_1_001.jpg'), isTrue);
      expect(html.contains('photos/v1_1_002.mp4'), isTrue);
    });

    test('attention media goes to X folder', () {
      final report = _buildReport();
      report.markers['0']!.add(
        AnswerMarkers(
          attention: true,
          media: [
            MediaItem(
              name: 'f1_2_001.jpg',
              type: 'image/jpeg',
              attention: true,
              localPath: 'X/f1_2_001.jpg',
            ),
          ],
        ),
      );

      final html = generateReportHtml(report);
      expect(html.contains('X/f1_2_001.jpg'), isTrue);
    });

    test('escapes XSS in answer text but keeps line breaks', () {
      final report = _buildReport();
      report.translations['0']!['RU']![0].text =
          '<script>alert(1)</script>\nВторая строка';

      final html = generateReportHtml(report);
      expect(html.contains('<script>alert(1)</script>'), isFalse);
      expect(html.contains('&lt;script&gt;'), isTrue);
      expect(html.contains('Вторая строка'), isTrue);
    });

    test('gallery includes videos with first-frame thumbnails', () {
      final html = generateReportHtml(_buildReport());

      // Сетка больше не фильтрует только изображения.
      expect(html.contains('filter(m => m.type === "image")'), isFalse);
      // Видео-миниатюры берут кадр через media fragment.
      expect(html.contains('#t=0.5'), isTrue);
      // Видео-элемент лайтбокса корректно закрыт (не void-элемент).
      expect(html.contains('</video>'), isTrue);
      // Подсказка при неподдерживаемом кодеке (Opera + HEVC).
      expect(html.contains('lightbox-video-error'), isTrue);
    });
  });
}
