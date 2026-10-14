import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_localizations.dart';
import '../models/report_models.dart';

/// План отрисовки медиа в PDF: какие изображения рисуем и что не поместилось.
///
/// Ограничение на количество фото жёсткое (см. [ReportPdfService.maxPdfImages]),
/// чтобы один ряд ответа не «раздувал» PDF. Остаток отдаётся счётчиком, видео
/// рисуются компактными плейсхолдерами.
class MediaRenderPlan {
  /// Первые [ReportPdfService.maxPdfImages] изображений.
  final List<MediaItem> images;

  /// Сколько изображений не поместилось в лимит (для подписи «+N»).
  final int overflowCount;

  /// Сколько видеофайлов в ряду (рисуются плейсхолдером, не грузятся).
  final int videoCount;

  const MediaRenderPlan({
    required this.images,
    required this.overflowCount,
    required this.videoCount,
  });
}

/// Генератор PDF-версии отчёта. Работает офлайн, только `pdf` + `rootBundle`.
///
/// Шрифты: латиница+кириллица (NotoSans) с CJK-фолбэком (Droid Sans Fallback).
/// Один стиль с `fontFallback` корректно рисует смешанный русско-китайский
/// текст без ручного разбора на прогоны.
class ReportPdfService {
  ReportPdfService._();

  /// Жёсткий лимит изображений на один ряд ответа в PDF.
  static const int maxPdfImages = 8;

  /// Размер одного фото в сетке (pt).
  static const double _thumbSize = 70;

  static pw.Font? _latinFont;
  static pw.Font? _cjkFont;

  /// Ленивая разовая загрузка шрифтов-ассетов.
  static Future<void> _ensureFonts() async {
    if (_latinFont != null && _cjkFont != null) return;
    final latinData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final cjkData = await rootBundle.load('assets/fonts/CJKFallback.ttf');
    _latinFont = pw.Font.ttf(latinData);
    _cjkFont = pw.Font.ttf(cjkData);
  }

  /// Базовый текстовый стиль: латиница с CJK-фолбэком.
  static pw.TextStyle _style({double? fontSize, PdfColor? color}) =>
      pw.TextStyle(
        font: _latinFont,
        fontFallback: [_cjkFont!],
        fontSize: fontSize,
        color: color,
      );

  /// Отбор медиа для отрисовки (тестируемая логика лимита).
  ///
  /// Возвращает первые [maxPdfImages] изображений (`type` начинается с
  /// `image/`), счётчик переполнения и число видео. Тип — регистронезависимо
  /// по префиксу, прочие типы игнорируются.
  static MediaRenderPlan mediaToRender(List<MediaItem> media) {
    final images = <MediaItem>[];
    var totalImages = 0;
    var videoCount = 0;
    for (final m in media) {
      if (m.type.startsWith('image/')) {
        totalImages++;
        if (images.length < maxPdfImages) images.add(m);
      } else if (m.type.startsWith('video/')) {
        videoCount++;
      }
    }
    final overflow = totalImages > maxPdfImages
        ? totalImages - maxPdfImages
        : 0;
    return MediaRenderPlan(
      images: images,
      overflowCount: overflow,
      videoCount: videoCount,
    );
  }

  /// Собрать PDF-документ отчёта.
  ///
  /// [loc] — локализованные подписи (заголовки столбцов, «Вопрос» и т.п.).
  /// [resolveMedia] — асинхронный резолвер байтов медиа (локальный файл,
  /// web-байты или HTTP); при `null` рисуется серый плейсхолдер.
  /// [folderPath] — оставлен для контекста вызывающей стороны (папка отчёта),
  /// сам сервис путь не использует (за резолв отвечает [resolveMedia]).
  static Future<Uint8List> build(
    Report report, {
    required AppLocalizations loc,
    required Future<Uint8List?> Function(MediaItem item) resolveMedia,
    String? folderPath,
  }) async {
    await _ensureFonts();

    // Сначала собираем данные (включая асинхронный резолв байтов), потом
    // строим виджеты — в build-колбэке MultiPage нельзя выполнять async.
    final sections = <_QuestionData>[];
    for (var i = 0; i < report.questions.length; i++) {
      final section = await _collectQuestion(report, i, loc, resolveMedia);
      if (section != null) sections.add(section);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '${report.reportName}  ${ctx.pageNumber}/${ctx.pagesCount}',
            style: _style(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          _buildHeader(report),
          pw.SizedBox(height: 12),
          for (final section in sections) ...[
            pw.Text(
              section.title,
              style: _style(fontSize: 12, color: PdfColors.blue800),
            ),
            if (section.description != null)
              pw.Text(
                section.description!,
                style: _style(fontSize: 9, color: PdfColors.grey600),
              ),
            if (section.example != null)
              pw.Text(
                section.example!,
                style: _style(fontSize: 9, color: PdfColors.grey600),
              ),
            pw.SizedBox(height: 4),
            _buildAnswersTable(section, loc),
            pw.SizedBox(height: 12),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// Шапка: название отчёта, строка сведений и дата.
  static pw.Widget _buildHeader(Report report) {
    final infoParts = <String>[
      if (report.client.trim().isNotEmpty) report.client.trim(),
      if (report.productType.trim().isNotEmpty) report.productType.trim(),
      if (report.factory.trim().isNotEmpty) report.factory.trim(),
      if (report.model.trim().isNotEmpty) report.model.trim(),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          report.reportName,
          style: _style(fontSize: 18, color: PdfColors.black),
        ),
        if (infoParts.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            infoParts.join(' | '),
            style: _style(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        if (report.dateTimestamp != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            _formatDate(report.dateTimestamp!),
            style: _style(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ],
    );
  }

  /// Собрать данные одного вопроса (заголовок + ряды ответов).
  /// Возвращает `null`, если у вопроса нет ни одного выводимого ряда.
  static Future<_QuestionData?> _collectQuestion(
    Report report,
    int questionIndex,
    AppLocalizations loc,
    Future<Uint8List?> Function(MediaItem item) resolveMedia,
  ) async {
    final question = report.questions[questionIndex];
    final localization = question.getLocalization(report.currentLanguage);
    final name =
        (localization?.name ?? question.getDisplayName(report.currentLanguage))
            ?.trim();
    final title =
        '${questionIndex + 1}. ${(name != null && name.isNotEmpty) ? name : loc.question}';
    final description = localization?.description?.trim();
    final example = localization?.example?.trim();

    final langs = report.availableLanguages.isEmpty
        ? <String>[report.currentLanguage]
        : report.availableLanguages;
    final answersByLang = <String, List<Map<String, dynamic>>>{
      for (final l in langs) l: report.getAnswersForQuestion(questionIndex, l),
    };
    final currentLang = answersByLang.containsKey(report.currentLanguage)
        ? report.currentLanguage
        : (langs.isNotEmpty ? langs.first : report.currentLanguage);
    final currentAnswers = answersByLang[currentLang] ?? const [];

    var rowCount = 0;
    for (final list in answersByLang.values) {
      if (list.length > rowCount) rowCount = list.length;
    }

    final rows = <_RowData>[];
    for (var r = 0; r < rowCount; r++) {
      final currentRow = r < currentAnswers.length ? currentAnswers[r] : null;
      // Фантомный ряд (в UI — пустая строка ввода) не содержит данных.
      if (currentRow != null && currentRow['fake'] == true) continue;

      final text = (currentRow?['text'] as String? ?? '').trim();
      final attention = currentRow?['attention'] == true;
      final needsWork = currentRow?['needsWork'] == true;
      final mediaMaps =
          (currentRow?['media'] as List?)?.cast<Map>() ?? const [];

      // Ответы других языков по тому же индексу ряда.
      final otherTexts = <MapEntry<String, String>>[];
      for (final lang in langs) {
        if (lang == currentLang) continue;
        final list = answersByLang[lang] ?? const [];
        if (r >= list.length) continue;
        final otherText = (list[r]['text'] as String? ?? '').trim();
        if (otherText.isNotEmpty && list[r]['isEmpty'] != true) {
          otherTexts.add(MapEntry(lang.toUpperCase(), otherText));
        }
      }

      final mediaItems = mediaMaps
          .map((m) => _mediaFromMap(Map<String, dynamic>.from(m)))
          .toList();
      final plan = mediaToRender(mediaItems);

      // Ряд без ответа и без медиа не выводим.
      if (text.isEmpty &&
          plan.images.isEmpty &&
          plan.videoCount == 0 &&
          plan.overflowCount == 0 &&
          otherTexts.isEmpty) {
        continue;
      }

      final imageBytes = <Uint8List?>[];
      for (final item in plan.images) {
        Uint8List? bytes;
        try {
          bytes = await resolveMedia(item);
        } catch (e) {
          if (kDebugMode) debugPrint('ReportPdfService resolveMedia error: $e');
          bytes = null;
        }
        imageBytes.add(bytes);
      }

      rows.add(
        _RowData(
          text: text,
          otherLangTexts: otherTexts,
          attention: attention,
          needsWork: needsWork,
          imageBytes: imageBytes,
          videoCount: plan.videoCount,
          overflowCount: plan.overflowCount,
        ),
      );
    }

    if (rows.isEmpty) return null;
    return _QuestionData(
      title: title,
      description: (description?.isNotEmpty ?? false) ? description : null,
      example: (example?.isNotEmpty ?? false) ? example : null,
      rows: rows,
    );
  }

  /// Восстановить [MediaItem] из Map, полученного через `toAnswerMap()`.
  /// `MediaItem.fromJson` не переносит runtime web-поля — добавляем их вручную.
  static MediaItem _mediaFromMap(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    final webBytes = json['webBytes'];
    if (webBytes is Uint8List) item.webBytes = webBytes;
    item.webUrl = json['webUrl'] as String?;
    item.thumbnailUrl = json['thumbnailUrl'] as String?;
    return item;
  }

  static pw.Widget _buildAnswersTable(
    _QuestionData section,
    AppLocalizations loc,
  ) {
    final headerStyle = _style(fontSize: 9, color: PdfColors.grey800);
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(26),
        1: pw.FixedColumnWidth(228),
        2: pw.FixedColumnWidth(46),
        3: pw.FixedColumnWidth(239),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell(pw.Text('№', style: headerStyle), center: true),
            _cell(pw.Text(loc.answer, style: headerStyle)),
            _cell(
              pw.Text(loc.pdfColumnMarks, style: headerStyle),
              center: true,
            ),
            _cell(pw.Text(loc.photo, style: headerStyle)),
          ],
        ),
        for (var r = 0; r < section.rows.length; r++)
          pw.TableRow(
            children: [
              _cell(
                pw.Text('${r + 1}', style: _style(fontSize: 9)),
                center: true,
              ),
              _cell(_answerCell(section.rows[r])),
              _cell(_marksCell(section.rows[r]), center: true),
              _cell(_photoCell(section.rows[r])),
            ],
          ),
      ],
    );
  }

  static pw.Widget _answerCell(_RowData row) {
    final children = <pw.Widget>[
      if (row.text.isNotEmpty) pw.Text(row.text, style: _style(fontSize: 9)),
    ];
    for (final entry in row.otherLangTexts) {
      children.add(
        pw.Text(
          '${entry.key}: ${entry.value}',
          style: _style(fontSize: 8, color: PdfColors.grey600),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Столбец меток. Текстовые символы-заглушки (не иконки) — глифы гарантированно
  /// есть в шрифте: «!» — attention, «*» — needsWork.
  static pw.Widget _marksCell(_RowData row) {
    final marks = <pw.Widget>[
      if (row.attention)
        pw.Text('!', style: _style(fontSize: 12, color: PdfColors.red700)),
      if (row.needsWork)
        pw.Text('*', style: _style(fontSize: 12, color: PdfColors.orange700)),
    ];
    return pw.Column(children: marks);
  }

  static pw.Widget _photoCell(_RowData row) {
    final items = <pw.Widget>[];
    for (final bytes in row.imageBytes) {
      items.add(
        bytes != null
            ? pw.Image(
                pw.MemoryImage(bytes),
                width: _thumbSize,
                height: _thumbSize,
                fit: pw.BoxFit.cover,
              )
            : _placeholder(),
      );
    }
    // Видео не грузим — компактный плейсхолдер с подписью.
    for (var v = 0; v < row.videoCount; v++) {
      items.add(_videoPlaceholder());
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          pw.Wrap(spacing: 4, runSpacing: 4, children: items),
        if (row.overflowCount > 0)
          pw.Text(
            '+${row.overflowCount}',
            style: _style(fontSize: 9, color: PdfColors.grey700),
          ),
      ],
    );
  }

  static pw.Widget _placeholder() => pw.Container(
    width: _thumbSize,
    height: _thumbSize,
    decoration: pw.BoxDecoration(
      color: PdfColors.grey300,
      border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
    ),
  );

  static pw.Widget _videoPlaceholder() => pw.Container(
    width: _thumbSize,
    height: _thumbSize,
    decoration: pw.BoxDecoration(
      color: PdfColors.grey300,
      border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
    ),
    child: pw.Center(
      child: pw.Text(
        'VIDEO',
        style: _style(fontSize: 8, color: PdfColors.grey800),
      ),
    ),
  );

  static pw.Widget _cell(pw.Widget child, {bool center = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(3),
        alignment: center ? pw.Alignment.center : pw.Alignment.topLeft,
        child: child,
      );

  /// Формат даты дд.мм.гггг.
  static String _formatDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}

class _RowData {
  final String text;
  final List<MapEntry<String, String>> otherLangTexts;
  final bool attention;
  final bool needsWork;
  final List<Uint8List?> imageBytes;
  final int videoCount;
  final int overflowCount;

  const _RowData({
    required this.text,
    required this.otherLangTexts,
    required this.attention,
    required this.needsWork,
    required this.imageBytes,
    required this.videoCount,
    required this.overflowCount,
  });
}

class _QuestionData {
  final String title;
  final String? description;
  final String? example;
  final List<_RowData> rows;

  const _QuestionData({
    required this.title,
    required this.description,
    required this.example,
    required this.rows,
  });
}
