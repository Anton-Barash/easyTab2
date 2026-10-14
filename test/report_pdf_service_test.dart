import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/services/report_pdf_service.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 1x1 PNG — минимальные валидные «байты фото» для резолвера.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Отчёт с 2 языками (RU/EN), 2 вопросами и рядом из 12 фото разных типов
/// (+ 2 видео) — проверяем лимит 8 и смешанный русско-китайский текст.
Report _buildReport() {
  final media = <MediaItem>[
    for (var i = 0; i < 6; i++)
      MediaItem(
        name: 'photo_$i.jpg',
        type: 'image/jpeg',
        localPath: 'photos/photo_$i.jpg',
      ),
    for (var i = 0; i < 6; i++)
      MediaItem(
        name: 'pic_$i.png',
        type: 'image/png',
        localPath: 'photos/pic_$i.png',
      ),
    MediaItem(
      name: 'clip1.mp4',
      type: 'video/mp4',
      localPath: 'videos/clip1.mp4',
    ),
    MediaItem(
      name: 'clip2.mp4',
      type: 'video/mp4',
      localPath: 'videos/clip2.mp4',
    ),
  ];

  return Report(
    reportName: 'Тест 测试 Test',
    availableLanguages: const ['RU', 'EN'],
    currentLanguage: 'RU',
    productType: 'Аэрогриль',
    factory: 'Фабрика №1',
    model: 'X-1',
    client: 'ООО Клиент',
    dateTimestamp: DateTime(2026, 10, 14).millisecondsSinceEpoch,
    questions: [
      Question(
        id: 0,
        localizations: {
          'RU': QuestionLocalization(
            name: 'Вопрос один 问题',
            description: 'Описание',
            example: 'Пример',
          ),
          'EN': QuestionLocalization(name: 'Question one'),
        },
      ),
      Question(
        id: 1,
        localizations: {
          'RU': QuestionLocalization(name: 'Вопрос два'),
          'EN': QuestionLocalization(name: 'Question two'),
        },
      ),
    ],
    translations: {
      '0': {
        'RU': [
          TranslationAnswer(
            text: 'Ответ с китайскими иероглифами 你好世界',
            isEmpty: false,
          ),
        ],
        'EN': [TranslationAnswer(text: 'English answer', isEmpty: false)],
      },
      '1': {
        'RU': [TranslationAnswer(text: '', isEmpty: true)],
        'EN': [TranslationAnswer(text: '', isEmpty: true)],
      },
    },
    markers: {
      '0': [AnswerMarkers(attention: true, needsWork: true)],
      // Ряд без текста, но с медиа: 12 фото + 2 видео.
      '1': [AnswerMarkers(media: media)],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG-байты для теста валидны', () {
    expect(img.decodePng(_pngBytes), isNotNull);
  });

  test('mediaToRender: лимит 8 изображений, остаток и счётчик видео', () {
    final media = <MediaItem>[
      for (var i = 0; i < 12; i++)
        MediaItem(name: 'p_$i.jpg', type: 'image/jpeg', localPath: 'p_$i.jpg'),
      MediaItem(name: 'v1.mp4', type: 'video/mp4'),
      MediaItem(name: 'v2.mp4', type: 'video/mp4'),
      MediaItem(name: 'doc.pdf', type: 'application/pdf'),
    ];

    final plan = ReportPdfService.mediaToRender(media);
    expect(plan.images.length, ReportPdfService.maxPdfImages);
    expect(plan.overflowCount, 4); // 12 изображений - 8
    expect(plan.videoCount, 2);
    expect(plan.images.every((m) => m.type.startsWith('image/')), isTrue);
  });

  test(
    'build: PDF с кириллицей/CJK, лимитом фото и плейсхолдером видео',
    () async {
      final loc = lookupAppLocalizations(const Locale('ru'));
      final report = _buildReport();

      var resolveCalls = 0;
      final bytes = await ReportPdfService.build(
        report,
        loc: loc,
        resolveMedia: (item) async {
          resolveCalls++;
          // Видео не резолвится (рисуется компактным плейсхолдером).
          expect(item.type.startsWith('image/'), isTrue);
          return _pngBytes;
        },
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(1000));
      // Из 12 изображений резолвим не больше лимита.
      expect(resolveCalls, greaterThan(0));
      expect(resolveCalls, lessThanOrEqualTo(ReportPdfService.maxPdfImages));
    },
  );

  test('build: не падает при недоступных медиа (серые плейсхолдеры)', () async {
    final loc = lookupAppLocalizations(const Locale('en'));
    final bytes = await ReportPdfService.build(
      _buildReport(),
      loc: loc,
      resolveMedia: (_) async => null,
    );
    expect(bytes.length, greaterThan(1000));
  });
}
