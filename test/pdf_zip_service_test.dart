import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:easy_tab/services/pdf_zip_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Проверка in-memory ZIP-упаковки PDF (используется при экспорте нескольких
// отчётов: все PDF кладутся в один архив).
void main() {
  test('buildZipFromBytes: корректно упаковывает несколько файлов', () {
    final a = Uint8List.fromList(List<int>.generate(200, (i) => i % 256));
    final b = Uint8List.fromList(List<int>.generate(50, (i) => (i * 3) % 256));

    final zip = buildZipFromBytes({'one.pdf': a, 'two.pdf': b});
    expect(zip, isA<Uint8List>());
    expect(zip.length, greaterThan(a.length));

    final decoded = ZipDecoder().decodeBytes(zip);
    expect(decoded.files.length, 2);
    final names = decoded.files.map((f) => f.name).toSet();
    expect(names, containsAll(<String>{'one.pdf', 'two.pdf'}));

    final one = decoded.files.firstWhere((f) => f.name == 'one.pdf');
    expect(one.content, equals(a));
    final two = decoded.files.firstWhere((f) => f.name == 'two.pdf');
    expect(two.content, equals(b));
  });

  test('buildZipFromBytes: пустой набор даёт валидный пустой архив', () {
    final zip = buildZipFromBytes({});
    final decoded = ZipDecoder().decodeBytes(zip);
    expect(decoded.files, isEmpty);
  });
}
