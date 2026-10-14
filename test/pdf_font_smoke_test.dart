import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Временный smoke-тест: проверяет, что встроенные шрифты (NotoSans для
// кириллицы и NotoSansSC для CJK) корректно принимаются пакетом pdf, включая
// вариативный TTF. Файл удаляется после проверки.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pdf рендерит кириллицу и CJK встроенными шрифтами', () async {
    final latinData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final cjkData = await rootBundle.load('assets/fonts/CJKFallback.ttf');
    final latin = pw.Font.ttf(latinData);
    final cjk = pw.Font.ttf(cjkData);

    final doc = pw.Document();
    final style = pw.TextStyle(font: latin, fontFallback: [cjk]);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Привет мир 你好，世界！hello 123', style: style),
            pw.Text('纯中文文本', style: style),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
  });
}
