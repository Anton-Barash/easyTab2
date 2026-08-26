/// Генерация полного HTML-отчёта (report.html) для локального ZIP-архива.
///
/// Работает офлайн, без сервера: медиа подключаются относительными путями
/// (photos/..., X/...), поэтому HTML корректно открывается из распакованного
/// архива на любом устройстве.
library;

import 'dart:convert';

import '../models/report_models.dart';
import 'report_excel_service.dart' show escapeHtml, sortLanguages;

/// Экранирует текст и сохраняет переносы строк как `<br>`.
///
/// Сначала экранирует HTML-спецсимволы (защита от XSS),
/// потом заменяет `\n` на `<br>` для отображения переносов.
String escapeHtmlWithBr(String input) {
  return escapeHtml(input).replaceAll('\n', '<br>');
}

/// Сгенерировать полный HTML-отчёт: таблица вопросов/ответов на всех языках,
/// миниатюры медиа, лайтбокс и галерея на ванильном JS.
String generateReportHtml(Report report) {
  final reportName = escapeHtml(report.reportName);
  final dateTime = DateTime.fromMillisecondsSinceEpoch(
    report.timestamp,
  ).toLocal().toString().substring(0, 16);
  final allLanguages = report.availableLanguages;
  final languages = sortLanguages(allLanguages);
  final buffer = StringBuffer();

  final List<String> allImagePaths = [];
  final List<List<List<List<Map<String, dynamic>>>>> allMediaByQandAandLang =
      [];

  for (int i = 0; i < report.questions.length; i++) {
    final List<List<List<Map<String, dynamic>>>> questionMedia = [];

    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final answers = report.getAnswersForQuestion(i, lang);
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
          if (media['type'].startsWith('image') &&
              !allImagePaths.contains(relativePath)) {
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
  buffer.writeln('      padding: 2.5px 3.5px;');
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
  buffer.writeln(
    '    .lightbox { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.9); display: none; flex-direction: column; align-items: center; justify-content: center; z-index: 9999; }',
  );
  buffer.writeln('    .lightbox.active { display: flex; }');
  buffer.writeln(
    '    .lightbox-controls { position: absolute; top: 20px; left: 50%; transform: translateX(-50%); display: flex; gap: 10px; z-index: 10002; }',
  );
  buffer.writeln(
    '    .lightbox-controls button { background: rgba(255,255,255,0.2); border: none; color: white; padding: 10px 15px; border-radius: 4px; cursor: pointer; font-size: 16px; transition: background 0.2s; }',
  );
  buffer.writeln(
    '    .lightbox-controls button:hover { background: rgba(255,255,255,0.3); }',
  );
  buffer.writeln(
    '    .lightbox-nav { position: absolute; top: 50%; transform: translateY(-50%); background: rgba(255,255,255,0.2); border: none; color: white; padding: 15px 20px; border-radius: 4px; cursor: pointer; font-size: 20px; transition: background 0.2s; z-index: 10001; }',
  );
  buffer.writeln(
    '    .lightbox-nav:hover { background: rgba(255,255,255,0.3); }',
  );
  buffer.writeln('    .lightbox-nav.prev { left: calc(50% - 500px); }');
  buffer.writeln('    .lightbox-nav.next { right: calc(50% - 500px); }');
  buffer.writeln(
    '    .lightbox-close { position: absolute; top: 20px; right: 20px; background: none; border: none; color: white; font-size: 32px; cursor: pointer; z-index: 10002; }',
  );
  buffer.writeln(
    '    .lightbox-info { position: absolute; top: 0px; left: 0px; background: rgba(0,0,0,0.7); color: white; padding: 15px 20px; border-radius: 8px; max-width: 280px; overflow-y: auto; text-align: left; z-index: 10001; }',
  );
  buffer.writeln('    .attention-answer { color: #f69a15; }');
  buffer.writeln(
    '    .lightbox-question { font-weight: bold; font-size: 16px; margin-bottom: 5px; }',
  );
  buffer.writeln('    .lightbox-answer { font-size: 14px; }');
  buffer.writeln(
    '    .lightbox-image-container { position: relative; width: 100%; overflow: hidden; cursor: grab; display: flex; align-items: center; justify-content: center; z-index: 10000; }',
  );
  buffer.writeln(
    '    .lightbox-image-container.dragging { cursor: grabbing; }',
  );
  buffer.writeln(
    '    .lightbox img { max-width: 100%; max-height: 100%; object-fit: contain; transform-origin: center center; }',
  );
  buffer.writeln(
    '    .lightbox-thumbnails-bar { position: absolute; bottom: 0px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.7); padding: 10px 15px; border-radius: 8px; max-width: 80%; overflow: hidden; z-index: 10001; }',
  );
  buffer.writeln('    @media (max-width: 1000px) {');
  buffer.writeln('      .lightbox-nav.prev { left: 20px; }');
  buffer.writeln('      .lightbox-nav.next { right: 20px; }');
  buffer.writeln('      .lightbox-image-container { width: 90%; }');
  buffer.writeln('    }');
  buffer.writeln('    @media (max-width: 768px) {');
  buffer.writeln(
    '      .lightbox-info { left: 20px; right: 20px; top: 60px; bottom: auto; max-width: none; max-height: 100px; }',
  );
  buffer.writeln(
    '      .lightbox-image-container { position: relative; width: calc(100% - 40px); height: calc(100vh - 290px); }',
  );
  buffer.writeln('      .lightbox-nav.prev { left: 20px; }');
  buffer.writeln('      .lightbox-nav.next { right: 20px; }');
  buffer.writeln('      .lightbox-thumbnails-bar { bottom: 120px; }');
  buffer.writeln('    }');
  buffer.writeln(
    '    .thumbnails-container { display: flex; gap: 8px; overflow-x: auto; scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.5) rgba(0,0,0,0.3); }',
  );
  buffer.writeln(
    '    .thumbnails-container::-webkit-scrollbar { height: 6px; }',
  );
  buffer.writeln(
    '    .thumbnails-container::-webkit-scrollbar-track { background: rgba(255,255,255,0.1); border-radius: 3px; }',
  );
  buffer.writeln(
    '    .thumbnails-container::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.5); border-radius: 3px; }',
  );
  buffer.writeln(
    '    .lightbox-thumbnail { width: 60px; height: 60px; object-fit: cover; border-radius: 4px; cursor: pointer; opacity: 0.6; transition: opacity 0.2s, border 0.2s; border: 2px solid transparent; }',
  );
  buffer.writeln('    .lightbox-thumbnail:hover { opacity: 1; }');
  buffer.writeln(
    '    .lightbox-thumbnail.active { opacity: 1; border-color: #00B0F0; }',
  );
  buffer.writeln(
    '    .lightbox-grid-btn { position: absolute; top: 20px; right: 70px; background: rgba(255,255,255,0.2); border: none; color: white; font-size: 24px; cursor: pointer; z-index: 10002; padding: 5px 12px; border-radius: 4px; transition: background 0.2s; }',
  );
  buffer.writeln(
    '    .lightbox-grid-btn:hover { background: rgba(255,255,255,0.3); }',
  );
  buffer.writeln('    /* Gallery overlay styles */');
  buffer.writeln(
    '    .gallery-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.95); display: none; flex-direction: column; z-index: 9998; }',
  );
  buffer.writeln('    .gallery-overlay.active { display: flex; }');
  buffer.writeln(
    '    .gallery-close { position: absolute; top: 20px; right: 20px; background: none; border: none; color: white; font-size: 32px; cursor: pointer; z-index: 10002; }',
  );
  buffer.writeln(
    '    .gallery-container { flex: 1; overflow-y: auto; padding: 80px 20px 20px; }',
  );
  buffer.writeln(
    '    .gallery-grid { grid-template-columns: repeat(4, 1fr); gap: 15px; max-width: 1400px; margin: 0 auto; }',
  );
  buffer.writeln(
    '    .gallery-item { aspect-ratio: 1; overflow: hidden; border-radius: 8px; cursor: pointer; transition: transform 0.2s; }',
  );
  buffer.writeln('    .gallery-item:hover { transform: scale(1.02); }');
  buffer.writeln(
    '    .gallery-item img { width: 100%; height: 100%; object-fit: cover; }',
  );
  buffer.writeln(
    '    .gallery-item video { width: 100%; height: 100%; object-fit: cover; }',
  );
  buffer.writeln('    .gallery-item.video-item { position: relative; }');
  buffer.writeln(
    '    .gallery-item.video-item::after { content: "▶"; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-size: 32px; color: white; text-shadow: 0 0 8px rgba(0,0,0,0.8); pointer-events: none; }',
  );
  buffer.writeln(
    '    @media (max-width: 1200px) { .gallery-grid { grid-template-columns: repeat(3, 1fr); } }',
  );
  buffer.writeln(
    '    @media (max-width: 900px) { .gallery-grid { grid-template-columns: repeat(2, 1fr); } }',
  );
  buffer.writeln(
    '    @media (max-width: 600px) { .gallery-grid { grid-template-columns: 1fr; } }',
  );
  buffer.writeln('    /* Gallery section header styles */');
  buffer.writeln(
    '    .gallery-section { margin-bottom: 30px; display: grid; grid-template-columns: inherit; }',
  );
  buffer.writeln('    .gallery-section-header {');
  buffer.writeln('      grid-column: 1 / -1;');
  buffer.writeln('      color: white;');
  buffer.writeln('      padding: 15px 20px;');
  buffer.writeln('      border-radius: 8px;');
  buffer.writeln('      margin-bottom: 15px;');
  buffer.writeln('      font-size: 16px;');
  buffer.writeln('      font-weight: 600;');
  buffer.writeln('    }');
  buffer.writeln(
    '    .gallery-section-header .question { font-size: 14px; opacity: 0.9; margin-bottom: 5px; }',
  );
  buffer.writeln(
    '    .gallery-section-header .answer { font-size: 18px; font-weight: 700; }',
  );
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

  final currentDate = DateTime.now()
      .toLocal()
      .toString()
      .substring(0, 10)
      .split('-')
      .reversed
      .join('.');

  buffer.writeln('<div class="excel-wrapper">');
  buffer.writeln('  <table>');
  buffer.writeln('    <!-- 1 строка + жирная линия снизу ПО ВСЕЙ ШИРИНЕ -->');
  buffer.writeln('    <tr class="header-row">');
  buffer.writeln('      <td class="border-bold"></td>');
  buffer.writeln(
    '      <td class="title border-bold">${escapeHtml(report.productType)}</td>',
  );
  buffer.writeln('      <td class="border-bold"></td>');
  buffer.writeln('      <td class="border-bold">Фабрика</td>');
  buffer.writeln('      <td class="border-bold">Модель</td>');
  buffer.writeln('    </tr>');
  buffer.writeln('    <!-- 2 строка + НЕТ линии снизу -->');
  final displayDate = report.dateTimestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(
          report.dateTimestamp!,
        ).toLocal().toString().substring(0, 10).split('-').reversed.join('.')
      : currentDate;
  buffer.writeln('    <tr class="header-row">');
  buffer.writeln('      <td class="no-border"></td>');
  buffer.writeln('      <td class="no-border">$displayDate</td>');
  buffer.writeln('      <td class="no-border"></td>');
  buffer.writeln(
    '      <td class="no-border">${escapeHtml(report.factory)}</td>',
  );
  buffer.writeln(
    '      <td class="no-border">${escapeHtml(report.model)}</td>',
  );
  buffer.writeln('    </tr>');
  buffer.writeln('    <!-- 3 строка: ОБЪЕДИНЕНА + ФОТО -->');
  buffer.writeln('    <tr class="header-row">');
  buffer.writeln(
    '      <td colspan="5" style="text-align:left; font-weight:bold; padding:8px; color:#6c757d; border-bottom:none;">ФОТО</td>',
  );
  buffer.writeln('    </tr>');
  buffer.writeln('    <!-- Исходная шапка -->');
  buffer.writeln('    <tr>');
  buffer.writeln('      <th colspan="5">$reportName | $dateTime</th>');
  buffer.writeln('    </tr>');

  for (int i = 0; i < report.questions.length; i++) {
    final q = report.questions[i];
    final questionNames = <String>[];
    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final loc = q.getLocalization(lang);
      // XSS-защита: экранируем имя вопроса
      questionNames.add(
        escapeHtml(loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}'),
      );
    }

    final List<List<Map<String, dynamic>>> answersByLang = List.generate(
      languages.length,
      (_) => [],
    );

    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final answers = report.getAnswersForQuestion(i, lang);
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
        final text = answersByLang[li][ai]['text'] ?? '';
        // XSS-защита: экранируем HTML + сохраняем переносы как <br>
        return escapeHtmlWithBr(text);
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
      // P0-5: для data-атрибутов используем чистый escapeHtml (без <br>),
      // т.к. answerCellContent содержит <br> для видимого контента,
      // а внутри data-answer HTML-теги недопустимы.
      final escapedAnswerText = ai < answersByLang[li].length
          ? escapeHtml(answersByLang[li][ai]['text'] ?? '')
          : '';

      const int maxVisible = 8;
      final visibleCount = mediaList.length > maxVisible
          ? maxVisible
          : mediaList.length;

      for (int mi = 0; mi < visibleCount; mi++) {
        final media = mediaList[mi];
        final isImage = media['type'].startsWith('image');
        // P0-5: escapeHtml для media-аттрибутов — защита от XSS.
        // Имена файлов могут содержать кавычки и спецсимволы.
        final escapedLocalPath = escapeHtml(
          media['localPath'] as String? ?? '',
        );
        final escapedName = escapeHtml(media['name'] as String? ?? '');

        if (isImage) {
          parts.add(
            '<div class="media-item" data-src="$escapedLocalPath" data-type="image" data-question="$questionName" data-answer="$escapedAnswerText" data-lang="$li" onclick="openLightbox(\'$escapedLocalPath\', \'image\')">'
            '<img class="media-thumbnail" src="$escapedLocalPath" alt="$escapedName" />'
            '</div>',
          );
        } else {
          parts.add(
            '<div class="media-item" data-src="$escapedLocalPath" data-type="video" data-question="$questionName" data-answer="$escapedAnswerText" data-lang="$li" onclick="openLightbox(\'$escapedLocalPath\', \'video\')">'
            '<img class="media-thumbnail" src="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2250%22 height=%2250%22 viewBox=%220 0 50 50%22><rect fill=%22%23e0e0e0%22 width=%2250%22 height=%2250%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2216%22>🎬</text></svg>" alt="$escapedName" />'
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
        final escapedLocalPath = escapeHtml(
          media['localPath'] as String? ?? '',
        );
        final escapedName = escapeHtml(media['name'] as String? ?? '');
        if (isImage) {
          parts.add(
            '<div class="media-item media-hidden" data-src="$escapedLocalPath" data-type="image" data-question="$questionName" data-answer="$escapedAnswerText" data-lang="$li" onclick="openLightbox(\'$escapedLocalPath\', \'image\')">'
            '<img class="media-thumbnail" src="$escapedLocalPath" alt="$escapedName" />'
            '</div>',
          );
        } else {
          parts.add(
            '<div class="media-item media-hidden" data-src="$escapedLocalPath" data-type="video" data-question="$questionName" data-answer="$escapedAnswerText" data-lang="$li" onclick="openLightbox(\'$escapedLocalPath\', \'video\')">'
            '<img class="media-thumbnail" src="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2250%22 height=%2250%22 viewBox=%220 0 50 50%22><rect fill=%22%23e0e0e0%22 width=%2250%22 height=%2250%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2216%22>🎬</text></svg>" alt="$escapedName" />'
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
          '      <td style="background:#fafafa;font-weight:500;width:200px;">${qContentParts.join('')}</td>',
        );
      } else {
        buffer.writeln(
          '      <td style="background:#fafafa;width:200px;"></td>',
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
        '      <td style="background:${answerHasAttention[ai] ? '#fff3cd' : 'white'};width:375px;">${aContentParts.join('')}</td>',
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
  buffer.writeln(
    '    <button class="lightbox-close" onclick="closeLightbox()">×</button>',
  );
  buffer.writeln(
    '    <button class="lightbox-grid-btn" onclick="openGallery()" title="Просмотр всех медиа">⊞</button>',
  );
  buffer.writeln('    <div class="lightbox-info">');
  buffer.writeln(
    '      <div class="lightbox-question" id="lightbox-question"></div>',
  );
  buffer.writeln(
    '      <div class="lightbox-answer" id="lightbox-answer"></div>',
  );
  buffer.writeln('    </div>');
  buffer.writeln('    <div class="lightbox-controls">');
  buffer.writeln('      <button onclick="zoomIn()">+</button>');
  buffer.writeln('      <button onclick="zoomOut()">-</button>');
  buffer.writeln('      <button onclick="resetZoom()">100%</button>');
  buffer.writeln('    </div>');
  buffer.writeln(
    '    <button class="lightbox-nav prev" onclick="prevMedia()">←</button>',
  );
  buffer.writeln(
    '    <div class="lightbox-image-container" id="lightbox-container">',
  );
  buffer.writeln(
    '      <img id="lightbox-img" src="" alt="" style="display:none;" />',
  );
  buffer.writeln(
    '      <video id="lightbox-video" controls autoplay playsinline style="display:none;max-width:100%;max-height:100%;object-fit:contain;" onerror="document.getElementById(\'lightbox-video-error\').style.display=\'block\'"></video>',
  );
  // Подсказка при ошибке декодирования (Opera/Firefox не умеют HEVC/H.265,
  // а видео с телефонов часто записаны именно в нём).
  buffer.writeln(
    '      <div id="lightbox-video-error" style="display:none;color:#fff;background:rgba(0,0,0,0.85);padding:16px 20px;border-radius:8px;max-width:80%;text-align:center;font-size:14px;line-height:1.6;">Видео не воспроизводится в этом браузере.<br>Вероятная причина — кодек HEVC (H.265): его не поддерживают Opera и Firefox.<br>Откройте отчёт в Edge/Chrome или сожмите видео в приложении («Сжать видео» конвертирует в H.264).</div>',
  );
  buffer.writeln('    </div>');
  buffer.writeln(
    '    <button class="lightbox-nav next" onclick="nextMedia()">→</button>',
  );
  buffer.writeln(
    '    <div class="lightbox-thumbnails-bar" id="lightbox-thumbnails-bar">',
  );
  buffer.writeln(
    '      <div class="thumbnails-container" id="thumbnails-container"></div>',
  );
  buffer.writeln('    </div>');
  buffer.writeln('  </div>');

  // Gallery overlay
  buffer.writeln('  <div class="gallery-overlay" id="gallery-overlay">');
  buffer.writeln(
    '    <button class="gallery-close" onclick="closeGallery()">×</button>',
  );
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
  buffer.writeln(
    '      document.querySelectorAll(".lang-btn").forEach(btn => btn.classList.remove("active"));',
  );
  buffer.writeln(
    '      document.querySelector(\'.lang-btn[data-lang="\' + li + \'"]\').classList.add("active");',
  );
  buffer.writeln('      for (let l = 0; l < allLanguages.length; l++) {');
  buffer.writeln('        const display = l === li ? "" : "none";');
  buffer.writeln(
    '        document.querySelectorAll(".question-lang-" + l).forEach(el => el.style.display = display);',
  );
  buffer.writeln(
    '        document.querySelectorAll(".answer-lang-" + l).forEach(el => el.style.display = display);',
  );
  buffer.writeln(
    '        document.querySelectorAll(".media-lang-" + l).forEach(el => el.style.display = display);',
  );
  buffer.writeln('      }');
  buffer.writeln('      currentLanguage = li;');
  buffer.writeln('      loadMediaByLanguage();');
  buffer.writeln('    }');

  buffer.writeln('    function loadMediaByLanguage() {');
  buffer.writeln(
    '      const mediaElements = document.querySelectorAll(".media-item");',
  );
  buffer.writeln(
    '      media = Array.from(mediaElements).filter(el => parseInt(el.dataset.lang) === currentLanguage).map(el => ({',
  );
  buffer.writeln('        src: el.dataset.src,');
  buffer.writeln('        type: el.dataset.type,');
  buffer.writeln('        question: el.dataset.question,');
  buffer.writeln('        answer: el.dataset.answer');
  buffer.writeln('      }));');
  buffer.writeln('      buildThumbnailsBar();');
  buffer.writeln('    }');

  buffer.writeln(
    '    document.addEventListener("DOMContentLoaded", function() {',
  );
  buffer.writeln('      loadMediaByLanguage();');
  buffer.writeln('    });');
  buffer.writeln('    function buildThumbnailsBar() {');
  buffer.writeln(
    '      const container = document.getElementById("thumbnails-container");',
  );
  buffer.writeln('      container.innerHTML = "";');
  buffer.writeln('      media.forEach((m, index) => {');
  buffer.writeln('        let thumbnail;');
  buffer.writeln('        if (m.type === "image") {');
  buffer.writeln('          thumbnail = document.createElement("img");');
  buffer.writeln('          thumbnail.src = m.src;');
  buffer.writeln('        } else {');
  // Миниатюра видео — кадр на 0.5с из самого файла (media fragment).
  // Если кодек не поддерживается (Opera + HEVC) — SVG-placeholder.
  buffer.writeln('          thumbnail = document.createElement("video");');
  buffer.writeln('          thumbnail.muted = true;');
  buffer.writeln('          thumbnail.preload = "metadata";');
  buffer.writeln('          thumbnail.playsInline = true;');
  buffer.writeln('          thumbnail.src = m.src + "#t=0.5";');
  buffer.writeln('          thumbnail.onerror = function() {');
  buffer.writeln('            const img = document.createElement("img");');
  buffer.writeln('            img.className = "lightbox-thumbnail";');
  buffer.writeln(
    '            img.src = "data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2260%22 height=%2260%22 viewBox=%220 0 60 60%22><rect fill=%22%23e0e0e0%22 width=%2260%22 height=%2260%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2220%22>🎬</text></svg>";',
  );
  buffer.writeln('            img.onclick = function() { showMedia(index); };');
  buffer.writeln('            thumbnail.replaceWith(img);');
  buffer.writeln('          };');
  buffer.writeln('        }');
  buffer.writeln('        thumbnail.className = "lightbox-thumbnail";');
  buffer.writeln(
    '        thumbnail.onclick = function() { showMedia(index); };',
  );
  buffer.writeln('        container.appendChild(thumbnail);');
  buffer.writeln('      });');
  buffer.writeln('    }');
  buffer.writeln('    function updateActiveThumbnail() {');
  buffer.writeln(
    '      document.querySelectorAll(".lightbox-thumbnail").forEach((thumb, index) => {',
  );
  buffer.writeln(
    '        thumb.classList.toggle("active", index === currentIndex);',
  );
  buffer.writeln('      });');
  buffer.writeln('      scrollToActiveThumbnail();');
  buffer.writeln('    }');
  buffer.writeln('    function scrollToActiveThumbnail() {');
  buffer.writeln(
    '      const container = document.getElementById("thumbnails-container");',
  );
  buffer.writeln(
    '      const activeThumbnail = document.querySelector(".lightbox-thumbnail.active");',
  );
  buffer.writeln('      if (!container || !activeThumbnail) return;');
  buffer.writeln(
    '      const containerRect = container.getBoundingClientRect();',
  );
  buffer.writeln(
    '      const thumbnailRect = activeThumbnail.getBoundingClientRect();',
  );
  buffer.writeln(
    '      const scrollLeft = activeThumbnail.offsetLeft - containerRect.width / 2 + thumbnailRect.width / 2;',
  );
  buffer.writeln(
    '      container.scrollTo({ left: scrollLeft, behavior: "smooth" });',
  );
  buffer.writeln('    }');

  buffer.writeln('    function openLightbox(src, type) {');
  buffer.writeln(
    '      const index = media.findIndex(m => m.src === src && m.type === type);',
  );
  buffer.writeln('      if (index === -1) return;');
  buffer.writeln('      currentIndex = index;');
  buffer.writeln(
    '      const imgEl = document.getElementById("lightbox-img");',
  );
  buffer.writeln(
    '      const videoEl = document.getElementById("lightbox-video");',
  );
  buffer.writeln(
    '      const questionEl = document.getElementById("lightbox-question");',
  );
  buffer.writeln(
    '      const answerEl = document.getElementById("lightbox-answer");',
  );
  buffer.writeln(
    '      const errEl = document.getElementById("lightbox-video-error");',
  );
  buffer.writeln('      errEl.style.display = "none";');
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
  // Явный play() надёжнее атрибута autoplay: некоторые браузеры
  // игнорируют autoplay при программной смене src.
  buffer.writeln('        const playPromise = videoEl.play();');
  buffer.writeln('        if (playPromise !== undefined) {');
  buffer.writeln('          playPromise.catch(function() {});');
  buffer.writeln('        }');
  buffer.writeln('      }');
  buffer.writeln('      if (media[currentIndex]) {');
  buffer.writeln(
    '        questionEl.textContent = media[currentIndex].question || "";',
  );
  buffer.writeln(
    '        answerEl.textContent = media[currentIndex].answer || "";',
  );
  buffer.writeln('      }');
  buffer.writeln(
    '      document.getElementById("lightbox").classList.add("active");',
  );
  buffer.writeln('      resetZoom();');
  buffer.writeln('      updateActiveThumbnail();');
  buffer.writeln('    }');

  buffer.writeln('    function closeLightbox() {');
  buffer.writeln(
    '      document.getElementById("lightbox").classList.remove("active");',
  );
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
  buffer.writeln(
    '        currentIndex = (currentIndex - 1 + media.length) % media.length;',
  );
  buffer.writeln('        showMedia(currentIndex);');
  buffer.writeln('      }');
  buffer.writeln('    }');

  buffer.writeln(
    '    function zoomIn() { scale = Math.min(scale * 1.2, 5); applyTransform(); }',
  );
  buffer.writeln(
    '    function zoomOut() { scale = Math.max(scale / 1.2, 0.5); applyTransform(); }',
  );
  buffer.writeln(
    '    function resetZoom() { scale = 1; panX = 0; panY = 0; applyTransform(); }',
  );

  buffer.writeln('    function applyTransform() {');
  buffer.writeln(
    '      const imgEl = document.getElementById("lightbox-img");',
  );
  buffer.writeln(
    '      const videoEl = document.getElementById("lightbox-video");',
  );
  buffer.writeln(
    '      imgEl.style.transform = "translate(" + panX + "px, " + panY + "px) scale(" + scale + ")";',
  );
  buffer.writeln(
    '      videoEl.style.transform = "translate(" + panX + "px, " + panY + "px) scale(" + scale + ")";',
  );
  buffer.writeln('    }');

  buffer.writeln(
    '    const container = document.getElementById("lightbox-container");',
  );
  buffer.writeln('    container.addEventListener("mousedown", function(e) {');
  buffer.writeln(
    '      isDragging = true; startX = e.clientX - panX; startY = e.clientY - panY; container.classList.add("dragging"); e.preventDefault();',
  );
  buffer.writeln('    });');
  buffer.writeln('    document.addEventListener("mousemove", function(e) {');
  buffer.writeln(
    '      if (isDragging) { panX = e.clientX - startX; panY = e.clientY - startY; applyTransform(); }',
  );
  buffer.writeln('    });');
  buffer.writeln(
    '    document.addEventListener("mouseup", function() { isDragging = false; container.classList.remove("dragging"); });',
  );
  buffer.writeln(
    '    container.addEventListener("wheel", function(e) { e.preventDefault(); if (e.deltaY < 0) zoomIn(); else zoomOut(); });',
  );
  buffer.writeln('    document.addEventListener("keydown", function(e) {');
  buffer.writeln(
    '      if (document.getElementById("lightbox").classList.contains("active")) {',
  );
  buffer.writeln('        if (e.key === "ArrowRight") nextMedia();');
  buffer.writeln('        if (e.key === "ArrowLeft") prevMedia();');
  buffer.writeln('        if (e.key === "Escape") closeLightbox();');
  buffer.writeln('        if (e.key === "+" || e.key === "=") zoomIn();');
  buffer.writeln('        if (e.key === "-") zoomOut();');
  buffer.writeln('        if (e.key === "0") resetZoom();');
  buffer.writeln('      }');
  buffer.writeln('    });');
  buffer.writeln('    window.addEventListener("resize", function() {');
  buffer.writeln(
    '      if (document.getElementById("lightbox").classList.contains("active")) {',
  );
  buffer.writeln('        scrollToActiveThumbnail();');
  buffer.writeln('      }');
  buffer.writeln('    });');

  buffer.writeln('    function openGallery() {');
  buffer.writeln(
    '      const galleryGrid = document.getElementById("gallery-grid");',
  );
  buffer.writeln('      galleryGrid.innerHTML = "";');
  // Показываем все медиа, включая видео (раньше видео в сетку не попадали).
  buffer.writeln('      const allMediaItems = media;');
  buffer.writeln('      ');
  buffer.writeln('      const groupedMedia = {};');
  buffer.writeln('      allMediaItems.forEach((m) => {');
  buffer.writeln(
    '        const key = (m.question || "") + "|||" + (m.answer || "");',
  );
  buffer.writeln('        if (!groupedMedia[key]) {');
  buffer.writeln(
    '          groupedMedia[key] = { question: m.question, answer: m.answer, items: [] };',
  );
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
  buffer.writeln(
    '        questionDiv.textContent = group.question || "Без вопроса";',
  );
  buffer.writeln('        header.appendChild(questionDiv);');
  buffer.writeln('        ');
  buffer.writeln('        const answerDiv = document.createElement("div");');
  buffer.writeln('        answerDiv.className = "answer";');
  buffer.writeln(
    '        answerDiv.textContent = group.answer || "Без ответа";',
  );
  buffer.writeln('        header.appendChild(answerDiv);');
  buffer.writeln('        ');
  buffer.writeln('        section.appendChild(header);');
  buffer.writeln('        ');
  buffer.writeln('        group.items.forEach((m) => {');
  buffer.writeln(
    '          const galleryItem = document.createElement("div");',
  );
  buffer.writeln('          galleryItem.className = "gallery-item";');
  buffer.writeln('          let thumb;');
  buffer.writeln('          if (m.type === "image") {');
  buffer.writeln('            thumb = document.createElement("img");');
  buffer.writeln('            thumb.src = m.src;');
  buffer.writeln('            thumb.alt = m.question || "Photo";');
  buffer.writeln('          } else {');
  // Видео-миниатюра: кадр на 0.5с; при неподдерживаемом кодеке — SVG.
  buffer.writeln('            galleryItem.classList.add("video-item");');
  buffer.writeln('            thumb = document.createElement("video");');
  buffer.writeln('            thumb.muted = true;');
  buffer.writeln('            thumb.preload = "metadata";');
  buffer.writeln('            thumb.playsInline = true;');
  buffer.writeln('            thumb.src = m.src + "#t=0.5";');
  buffer.writeln('            thumb.onerror = function() {');
  buffer.writeln('              const img = document.createElement("img");');
  buffer.writeln(
    '              img.src = "data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2260%22 height=%2260%22 viewBox=%220 0 60 60%22><rect fill=%22%23e0e0e0%22 width=%2260%22 height=%2260%22/><text x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dominant-baseline=%22middle%22 font-size=%2220%22>🎬</text></svg>";',
  );
  buffer.writeln('              img.alt = m.question || "Video";');
  buffer.writeln('              thumb.replaceWith(img);');
  buffer.writeln('            };');
  buffer.writeln('          }');
  buffer.writeln('          thumb.onclick = function() {');
  buffer.writeln('            closeGallery();');
  buffer.writeln('            openLightbox(m.src, m.type);');
  buffer.writeln('          };');
  buffer.writeln('          galleryItem.appendChild(thumb);');
  buffer.writeln('          section.appendChild(galleryItem);');
  buffer.writeln('          ');
  buffer.writeln('          // Check if this is the current media item');
  buffer.writeln(
    '          if (currentIndex >= 0 && currentIndex < media.length && media[currentIndex].src === m.src) {',
  );
  buffer.writeln('            targetElement = galleryItem;');
  buffer.writeln('          }');
  buffer.writeln('        });');
  buffer.writeln('        ');
  buffer.writeln('        galleryGrid.appendChild(section);');
  buffer.writeln('      });');
  buffer.writeln('      ');
  buffer.writeln(
    '      document.getElementById("gallery-overlay").classList.add("active");',
  );
  buffer.writeln('      closeLightbox();');
  buffer.writeln('      ');
  buffer.writeln('      // Scroll to target element if found');
  buffer.writeln('      setTimeout(() => {');
  buffer.writeln('        if (targetElement) {');
  buffer.writeln(
    '          targetElement.scrollIntoView({ behavior: "smooth", block: "center" });',
  );
  buffer.writeln('        }');
  buffer.writeln('      }, 100);');
  buffer.writeln('    }');

  buffer.writeln('    function closeGallery() {');
  buffer.writeln(
    '      document.getElementById("gallery-overlay").classList.remove("active");',
  );
  buffer.writeln('    }');

  buffer.writeln('    document.addEventListener("keydown", function(e) {');
  buffer.writeln(
    '      if (document.getElementById("gallery-overlay").classList.contains("active")) {',
  );
  buffer.writeln('        if (e.key === "Escape") closeGallery();');
  buffer.writeln('      }');
  buffer.writeln('    });');
  buffer.writeln('  </script>');

  buffer.writeln('</body>');
  buffer.writeln('</html>');
  return buffer.toString();
}
