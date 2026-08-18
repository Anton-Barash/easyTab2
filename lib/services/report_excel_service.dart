// ============================================================
// Report Excel Service — генерация XLSX и Excel-HTML из данных отчёта.
//
// Вынесено из ReportState (Фаза 2 рефакторинга). Чистые функции:
// принимают Report, не зависят от состояния провайдера.
// ============================================================

import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';

import '../models/report_models.dart';

const int maxLanguages = 5;

const Map<String, int> languagePriority = {'RU': 0, 'EN': 1, 'ZH': 2};

// Цвета дополнительных языков, 0-индексированные относительно первого
// доп. языка (li==1 в циклах). Основной язык (li==0) всегда чёрный и
// обходится вызывающим кодом, поэтому сюда не входит.
const Map<int, String> languageColors = {
  0: '#27ae60', // 1-й доп. язык (обычно EN) — зелёный
  1: '#8e44ad', // 2-й доп. язык (обычно ZH) — фиолетовый
  2: '#2c7da0', // 3-й доп. язык — синий
  3: '#888888', // 4-й доп. язык — серый
};

List<String> sortLanguages(List<String> languages) {
  final sorted = List<String>.from(languages);
  sorted.sort((a, b) {
    final priorityA = languagePriority[a] ?? 999;
    final priorityB = languagePriority[b] ?? 999;
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }
    return a.compareTo(b);
  });
  if (sorted.length > maxLanguages) {
    return sorted.sublist(0, maxLanguages);
  }
  return sorted;
}

/// Цвет дополнительного языка по его индексу среди доп. языков.
/// Вызывающий код передаёт (li - 1): li==1 (первый доп. язык) → индекс 0.
/// Fallback — серый для языков сверх палитры.
String getLanguageColor(int index) {
  return languageColors[index] ?? '#888888';
}

/// Экранирует спецсимволы HTML для защиты от XSS (H-22, M-30).
///
/// Применяется ко всем пользовательским данным (productType, factory,
/// model, тексты ответов) перед вставкой в HTML-отчёт.
///
/// Превращает: `<script>alert(1)</script>` →
/// `&lt;script&gt;alert(1)&lt;/script&gt;`
String escapeHtml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

/// P2-40: Санитизирует ячейку Excel-таблицы от XSS и formula injection.
///
/// 1. Экранирует HTML-спецсимволы (защита от XSS в HTML-представлении Excel).
/// 2. Если ячейка начинается с префикса формулы (=, +, -, @, таб, возврат каретки),
///    добавляет ведущую одинарную кавычку — Excel воспринимает её как текст.
String _sanitizeExcelCell(String input) {
  final escaped = escapeHtml(input);
  // Защита от formula injection: если первый символ — оператор формулы.
  if (escaped.isNotEmpty) {
    final firstChar = escaped[0];
    if (firstChar == '=' ||
        firstChar == '+' ||
        firstChar == '-' ||
        firstChar == '@' ||
        firstChar == '\t' ||
        firstChar == '\r') {
      return "'$escaped";
    }
  }
  return escaped;
}

List<String> _groupMediaNames(List<String> mediaNames) {
  if (mediaNames.isEmpty) return [];

  final Map<String, List<int>> grouped = {};

  for (final name in mediaNames) {
    final attentionPrefix = name.startsWith('x') ? 'x' : '';
    final cleanName = name.startsWith('x') ? name.substring(1) : name;

    final typePrefix = cleanName.substring(0, 1);
    final rest = cleanName.substring(1);
    final parts = rest.split('_');

    if (parts.length >= 3) {
      final questionNum = parts[0];
      final answerNum = parts[1];
      final numStr = parts[2];

      if (int.tryParse(numStr) != null) {
        final key = '$attentionPrefix$typePrefix${questionNum}_$answerNum';
        if (!grouped.containsKey(key)) {
          grouped[key] = [];
        }
        grouped[key]!.add(int.parse(numStr));
      } else {
        if (!grouped.containsKey('other')) {
          grouped['other'] = [];
        }
        grouped['other']!.add(mediaNames.indexOf(name));
      }
    } else {
      if (!grouped.containsKey('other')) {
        grouped['other'] = [];
      }
      grouped['other']!.add(mediaNames.indexOf(name));
    }
  }

  final result = <String>[];
  for (final entry in grouped.entries) {
    if (entry.key == 'other') {
      for (final idx in entry.value) {
        result.add(mediaNames[idx]);
      }
    } else {
      final nums = entry.value..sort();
      final uniqueNums = nums.toSet().toList()..sort();
      if (uniqueNums.length == 1) {
        result.add('${entry.key}_${uniqueNums[0].toString().padLeft(3, '0')}');
      } else {
        result.add(
          '${entry.key}_${uniqueNums.first.toString().padLeft(3, '0')}-${uniqueNums.last.toString().padLeft(3, '0')}',
        );
      }
    }
  }

  return result;
}

/// Сгенерировать упрощённую HTML-таблицу отчёта для вставки в Excel
/// через буфер обмена. Работает офлайн, без сервера.
String generateExcelHtmlContent(Report report) {
  final reportName = escapeHtml(report.reportName);
  final dateTime = DateTime.fromMillisecondsSinceEpoch(
    report.timestamp,
  ).toLocal().toString().substring(0, 16);
  final allLanguages = report.availableLanguages;
  final languages = sortLanguages(allLanguages);
  final langDisplay = languages.join(' / ');
  final buffer = StringBuffer();
  buffer.writeln('<!DOCTYPE html>');
  buffer.writeln('<html lang="ru">');
  buffer.writeln('<head>');
  buffer.writeln('<meta charset="UTF-8">');
  buffer.writeln(
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
  );
  buffer.writeln('<title>$reportName - Excel таблица</title>');
  buffer.writeln(
    '<style>table{border-collapse:collapse;font-size:13px;}th,td{padding:6px 10px;vertical-align:top;border-bottom:1px solid #d0d0d0;}th{background:#f3f3f3;font-weight:600;text-align:center;color:#2c2c2c;}</style>',
  );
  buffer.writeln('</head>');
  buffer.writeln('<body>');
  buffer.writeln('<table>');
  buffer.writeln('<thead>');
  buffer.writeln(
    '<tr><th colspan="5">$reportName | Язык: $langDisplay | $dateTime</th></tr>',
  );
  buffer.writeln(
    '<tr><td colspan="5" style="border-bottom:2px solid #6c757d;"></td></tr>',
  );
  buffer.writeln('</thead>');
  buffer.writeln('<tbody>');

  for (int i = 0; i < report.questions.length; i++) {
    final q = report.questions[i];
    final questionNames = <String>[];
    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final loc = q.getLocalization(lang);
      // P2-40: экранируем имя вопроса от XSS/formula injection.
      questionNames.add(
        _sanitizeExcelCell(
          loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}',
        ),
      );
    }

    final List<String> allMediaNames = [];
    final List<List<Map<String, dynamic>>> answersByLang = List.generate(
      languages.length,
      (_) => [],
    );

    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final answers = report.getAnswersForQuestion(i, lang);
      answersByLang[li] = answers;

      for (final a in answers) {
        final media = a['media'] as List? ?? [];
        for (final m in media) {
          allMediaNames.add(_sanitizeExcelCell(m['name'] ?? ''));
        }
      }
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

    final photoCellContent = allMediaNames.isNotEmpty
        ? allMediaNames.join(', ')
        : '';

    String questionCellContent() {
      final parts = <String>[];
      for (int li = 0; li < languages.length; li++) {
        if (li == 0) {
          parts.add(questionNames[li]);
        } else {
          parts.add(
            '<span style="font-size:10px;color:#888888;">${questionNames[li]}</span>',
          );
        }
      }
      return parts.join('<br>');
    }

    String answerCellContent(int ai) {
      final parts = <String>[];
      for (int li = 0; li < languages.length; li++) {
        if (ai < answersByLang[li].length) {
          final text = _sanitizeExcelCell(answersByLang[li][ai]['text'] ?? '');
          if (li == 0) {
            parts.add('<div>$text</div>');
          } else {
            parts.add('<div style="font-size:10px;color:#888888;">$text</div>');
          }
        }
      }
      return parts.join('');
    }

    if (maxAnswers == 0) {
      buffer.writeln('<tr>');
      buffer.writeln(
        '<td style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
      );
      buffer.writeln(
        '<td style="background:#fafafa;font-weight:500;width:160px;">${questionCellContent()}</td>',
      );
      buffer.writeln(
        '<td style="text-align:center;vertical-align:middle;width:30px;"></td>',
      );
      buffer.writeln(
        '<td style="background:white;width:300px;">${answerCellContent(0)}</td>',
      );
      buffer.writeln(
        '<td style="background:#fafafa;width:200px;">$photoCellContent</td>',
      );
      buffer.writeln('</tr>');
    } else {
      for (int ai = 0; ai < maxAnswers; ai++) {
        buffer.writeln('<tr>');
        buffer.writeln(
          '<td style="background:#fafafa;font-weight:500;width:40px;color:#00B0F0;">${i + 1}</td>',
        );
        buffer.writeln(
          '<td style="background:#fafafa;font-weight:500;width:160px;">${questionCellContent()}</td>',
        );

        if (answerHasAttention[ai]) {
          buffer.writeln(
            '<td style="text-align:center;vertical-align:middle;width:30px;background:#fff3cd;"><span style="font-weight:bold;color:#ef4444;">!</span></td>',
          );
        } else {
          buffer.writeln(
            '<td style="text-align:center;vertical-align:middle;width:30px;"></td>',
          );
        }

        final answerBgColor = answerHasAttention[ai] ? '#fff3cd' : 'white';
        buffer.writeln(
          '<td style="background:$answerBgColor;width:300px;">${answerCellContent(ai)}</td>',
        );

        buffer.writeln(
          '<td style="background:#fafafa;width:200px;">$photoCellContent</td>',
        );
        buffer.writeln('</tr>');
      }
    }
  }

  buffer.writeln('</tbody>');
  buffer.writeln('</table>');
  buffer.writeln('</body>');
  buffer.writeln('</html>');
  return buffer.toString();
}

Uint8List generateExcelBytes(Report report) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];

  final allLanguages = report.availableLanguages;
  final languages = sortLanguages(allLanguages);

  final rowNumColor = ExcelColor.fromHexString('#00B0F0');
  final questionBgColor = ExcelColor.fromHexString('#fafafa');
  final attentionBgColor = ExcelColor.fromHexString('#fff3cd');
  final borderColor = ExcelColor.fromHexString('#6c757d');

  int row = 0;

  // 1-я строка шапки (заголовки: Аэрогриль, Фабрика, Модель)
  final headerStyle1Bold = CellStyle(
    backgroundColorHex: ExcelColor.white,
    fontColorHex: ExcelColor.fromHexString('#6c757d'),
    bold: true,
    fontSize: 12,
    fontFamily: 'Courier New',
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.black,
    ),
  );
  final headerStyle1Normal = CellStyle(
    backgroundColorHex: ExcelColor.white,
    fontColorHex: ExcelColor.fromHexString('#6c757d'),
    bold: false,
    fontSize: 12,
    fontFamily: 'Courier New',
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.black,
    ),
  );
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
      .value = TextCellValue(
    // P2-40: sanitize от formula injection (=, +, -, @, \t, \r) для Excel-ячеек.
    _sanitizeExcelCell(report.productType),
  );
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .cellStyle =
      headerStyle1Bold;
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
      TextCellValue('Фабрика');
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .cellStyle =
      headerStyle1Normal;
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
      TextCellValue('Модель');
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .cellStyle =
      headerStyle1Normal;
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
      .cellStyle = CellStyle(
    backgroundColorHex: ExcelColor.white,
    fontFamily: 'Courier New',
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.black,
    ),
  );
  row++;

  // 2-я строка шапки (значения: дата, factory, model)
  final headerStyle2 = CellStyle(
    backgroundColorHex: ExcelColor.white,
    fontColorHex: ExcelColor.fromHexString('#6c757d'),
    fontSize: 10,
    fontFamily: 'Courier New',
  );
  final excelDate = report.dateTimestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(
          report.dateTimestamp!,
        ).toLocal().toString().substring(0, 10).split('-').reversed.join('.')
      : DateTime.now()
            .toLocal()
            .toString()
            .substring(0, 10)
            .split('-')
            .reversed
            .join('.');
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
      TextCellValue(excelDate);
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .cellStyle =
      headerStyle2;
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
      .value = TextCellValue(
    // P2-40: sanitize от formula injection для Excel-ячеек.
    _sanitizeExcelCell(report.factory),
  );
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .cellStyle =
      headerStyle2;
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
      .value = TextCellValue(
    // P2-40: sanitize от formula injection для Excel-ячеек.
    _sanitizeExcelCell(report.model),
  );
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .cellStyle =
      headerStyle2;
  row++;

  // 3-я строка шапки (ФОТО - объединенная ячейка)
  const totalColumns = 5; // A-E
  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    CellIndex.indexByColumnRow(columnIndex: totalColumns - 1, rowIndex: row),
  );
  final photoHeaderStyle = CellStyle(
    backgroundColorHex: ExcelColor.white,
    fontColorHex: ExcelColor.fromHexString('#6c757d'),
    bold: true,
    fontSize: 10,
    fontFamily: 'Courier New',
    horizontalAlign: HorizontalAlign.Center,
  );
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
      TextCellValue('ФОТО');
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle =
      photoHeaderStyle;
  row++;

  // 4-я строка - пустая строка
  for (int col = 0; col < totalColumns; col++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3))
        .cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.white,
      fontFamily: 'Courier New',
    );
  }
  row++;

  // Таблица с данными
  for (int i = 0; i < report.questions.length; i++) {
    final q = report.questions[i];

    final questionNames = <String>[];
    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final loc = q.getLocalization(lang);
      // P2-40: sanitize от formula injection для Excel-ячеек.
      questionNames.add(
        _sanitizeExcelCell(
          loc?.name ?? q.getDisplayName(lang) ?? 'Вопрос ${i + 1}',
        ),
      );
    }

    final List<List<String>> mediaByAnswer = [];
    final List<List<Map<String, dynamic>>> answersByLang = List.generate(
      languages.length,
      (_) => [],
    );

    for (int li = 0; li < languages.length; li++) {
      final lang = languages[li];
      final answers = report.getAnswersForQuestion(i, lang);
      answersByLang[li] = answers;

      for (int ai = 0; ai < answers.length; ai++) {
        final a = answers[ai];
        if (mediaByAnswer.length <= ai) {
          mediaByAnswer.add([]);
        }
        final media = a['media'] as List? ?? [];
        for (final m in media) {
          final name = m['name'] as String? ?? '';
          final attention = m['attention'] as bool? ?? false;
          if (name.isNotEmpty) {
            final prefix = attention ? 'x' : '';
            final num = name.split('.').first;
            mediaByAnswer[ai].add('$prefix$num');
          }
        }
      }
    }

    final maxAnswers = answersByLang
        .map((l) => l.length)
        .reduce((a, b) => a > b ? a : b);

    final List<String> photoCellContents = [];
    for (final mediaList in mediaByAnswer) {
      final grouped = _groupMediaNames(mediaList);
      photoCellContents.add(grouped.join(', '));
    }
    while (photoCellContents.length < maxAnswers) {
      photoCellContents.add('');
    }

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

    final totalRows = maxAnswers * languages.length;

    if (maxAnswers == 0) {
      for (int li = 0; li < languages.length; li++) {
        final isLast = li == languages.length - 1;

        if (li == 0) {
          sheet.merge(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
            CellIndex.indexByColumnRow(
              columnIndex: 0,
              rowIndex: row + languages.length - 1,
            ),
          );
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .value = IntCellValue(
            i + 1,
          );
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .cellStyle = CellStyle(
            backgroundColorHex: questionBgColor,
            fontColorHex: rowNumColor,
            bold: true,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast
                ? Border(
                    borderStyle: BorderStyle.Thin,
                    borderColorHex: borderColor,
                  )
                : null,
          );
        }

        final qColor = li == 0
            ? ExcelColor.black
            : ExcelColor.fromHexString(getLanguageColor(li - 1));
        final qFontSize = li == 0 ? 12 : 10;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = TextCellValue(
          questionNames[li],
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .cellStyle = CellStyle(
          backgroundColorHex: questionBgColor,
          fontColorHex: qColor,
          fontSize: qFontSize,
          fontFamily: 'Courier New',
          verticalAlign: VerticalAlign.Top,
          bottomBorder: isLast
              ? Border(
                  borderStyle: BorderStyle.Thin,
                  borderColorHex: borderColor,
                )
              : null,
        );

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = TextCellValue(
          '',
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .cellStyle = CellStyle(
          backgroundColorHex: questionBgColor,
          fontFamily: 'Courier New',
          verticalAlign: VerticalAlign.Top,
          bottomBorder: isLast
              ? Border(
                  borderStyle: BorderStyle.Thin,
                  borderColorHex: borderColor,
                )
              : null,
        );

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = TextCellValue(
          '',
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .cellStyle = CellStyle(
          backgroundColorHex: ExcelColor.white,
          fontFamily: 'Courier New',
          verticalAlign: VerticalAlign.Top,
          bottomBorder: isLast
              ? Border(
                  borderStyle: BorderStyle.Thin,
                  borderColorHex: borderColor,
                )
              : null,
        );

        if (li == 0) {
          sheet.merge(
            CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
            CellIndex.indexByColumnRow(
              columnIndex: 4,
              rowIndex: row + languages.length - 1,
            ),
          );
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
              .value = TextCellValue(
            '',
          );
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
              .cellStyle = CellStyle(
            backgroundColorHex: questionBgColor,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast
                ? Border(
                    borderStyle: BorderStyle.Thin,
                    borderColorHex: borderColor,
                  )
                : null,
          );
        }

        row++;
      }
    } else {
      for (int ai = 0; ai < maxAnswers; ai++) {
        for (int li = 0; li < languages.length; li++) {
          final isLast = ai == maxAnswers - 1 && li == languages.length - 1;

          if (li == 0 && ai == 0) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
              CellIndex.indexByColumnRow(
                columnIndex: 0,
                rowIndex: row + totalRows - 1,
              ),
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
                .value = IntCellValue(
              i + 1,
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
                .cellStyle = CellStyle(
              backgroundColorHex: questionBgColor,
              fontColorHex: rowNumColor,
              bold: true,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast
                  ? Border(
                      borderStyle: BorderStyle.Thin,
                      borderColorHex: borderColor,
                    )
                  : null,
            );
          }

          if (ai == 0) {
            final qColor = li == 0
                ? ExcelColor.black
                : ExcelColor.fromHexString(getLanguageColor(li - 1));
            final qFontSize = li == 0 ? 12 : 10;
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
                .value = TextCellValue(
              questionNames[li],
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
                .cellStyle = CellStyle(
              backgroundColorHex: questionBgColor,
              fontColorHex: qColor,
              fontSize: qFontSize,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast
                  ? Border(
                      borderStyle: BorderStyle.Thin,
                      borderColorHex: borderColor,
                    )
                  : null,
            );
          } else {
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
                .value = TextCellValue(
              '',
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
                .cellStyle = CellStyle(
              backgroundColorHex: questionBgColor,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
              bottomBorder: isLast
                  ? Border(
                      borderStyle: BorderStyle.Thin,
                      borderColorHex: borderColor,
                    )
                  : null,
            );
          }

          final hasAttentionMark = answerHasAttention[ai];
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .value = hasAttentionMark
              ? TextCellValue('!')
              : TextCellValue('');
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .cellStyle = CellStyle(
            backgroundColorHex: hasAttentionMark
                ? attentionBgColor
                : ExcelColor.white,
            fontColorHex: hasAttentionMark
                ? ExcelColor.fromHexString('#ef4444')
                : ExcelColor.black,
            bold: hasAttentionMark,
            fontFamily: 'Courier New',
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast
                ? Border(
                    borderStyle: BorderStyle.Thin,
                    borderColorHex: borderColor,
                  )
                : null,
          );

          final text = ai < answersByLang[li].length
              ? _sanitizeExcelCell(
                  (answersByLang[li][ai]['text'] ?? '') as String,
                )
              : '';
          final hasAttention = answerHasAttention[ai];
          final answerBgColor = hasAttention
              ? attentionBgColor
              : ExcelColor.white;
          final aColor = li == 0
              ? ExcelColor.black
              : ExcelColor.fromHexString(getLanguageColor(li - 1));
          final aFontSize = li == 0 ? 12 : 10;

          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
              .value = TextCellValue(
            text,
          );
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
              .cellStyle = CellStyle(
            backgroundColorHex: answerBgColor,
            fontColorHex: aColor,
            fontSize: aFontSize,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast
                ? Border(
                    borderStyle: BorderStyle.Thin,
                    borderColorHex: borderColor,
                  )
                : null,
          );

          final photoBgColor = hasAttention
              ? attentionBgColor
              : questionBgColor;
          if (li == 0) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
              CellIndex.indexByColumnRow(
                columnIndex: 4,
                rowIndex: row + languages.length - 1,
              ),
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
                .value = TextCellValue(
              // P2-40: sanitize от formula injection для Excel-ячеек.
              _sanitizeExcelCell(photoCellContents[ai]),
            );
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
                .cellStyle = CellStyle(
              backgroundColorHex: photoBgColor,
              fontColorHex: ExcelColor.fromHexString('#6c757d'),
              bold: true,
              fontSize: 10,
              fontFamily: 'Courier New',
              verticalAlign: VerticalAlign.Top,
            );
          }

          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
              .cellStyle = CellStyle(
            backgroundColorHex: photoBgColor,
            fontColorHex: ExcelColor.fromHexString('#6c757d'),
            bold: true,
            fontSize: 10,
            fontFamily: 'Courier New',
            verticalAlign: VerticalAlign.Top,
            bottomBorder: isLast
                ? Border(
                    borderStyle: BorderStyle.Thin,
                    borderColorHex: borderColor,
                  )
                : null,
          );

          row++;
        }
      }
    }
  }

  sheet.setColumnWidth(0, 10);

  final bytes = excel.encode();
  return Uint8List.fromList(bytes!);
}
