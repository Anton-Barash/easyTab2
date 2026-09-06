import 'package:easy_tab/services/report_merge_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Собирает минимальный canonical-документ для тестов.
Map<String, dynamic> _doc({
  required List<String> qids,
  required Map<String, List<String>> answersByQid,
  String reportName = 'Report',
}) {
  return {
    'schemaVersion': 2,
    'reportName': reportName,
    'availableLanguages': ['RU'],
    'currentLanguage': 'RU',
    'questions': [
      for (final qid in qids) {'id': qids.indexOf(qid), 'qid': qid, 'localizations': {}},
    ],
    'answers': {
      for (final qid in answersByQid.keys)
        qid: [
          for (final rid in answersByQid[qid]!)
            {
              'rid': rid,
              'legacyIndex': answersByQid[qid]!.indexOf(rid),
              'localizations': {
                'RU': {'id': 'cell-$rid', 'text': '', 'isEmpty': true, 'createdAt': 1, 'updatedAt': 1},
              },
            },
        ],
    },
  };
}

Map<String, dynamic> _cell(Map<String, dynamic> doc, String qid, String rid) {
  final rows = (doc['answers'] as Map)['q1'] as List;
  return (rows.firstWhere((r) => (r as Map)['rid'] == rid) as Map)['localizations']
      ['RU'] as Map<String, dynamic>;
}

void main() {
  group('buildReportOps: добавления без конфликтов', () {
    test('два пользователя добавили по ответу — получается два answer.add', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});

      final clientDoc = _doc(qids: ['q1'], answersByQid: {'q1': ['r1', 'r2']});
      final serverDoc = _doc(qids: ['q1'], answersByQid: {'q1': ['r1', 'r3']});

      final clientOps = buildReportOps(base, clientDoc);
      expect(clientOps.where((o) => o['t'] == 'answer.add').map((o) => o['rid']),
          ['r2']);
      expect(clientOps.where((o) => o['t'] == 'answer.add').length, 1);

      final serverOps = buildReportOps(base, serverDoc);
      expect(serverOps.where((o) => o['t'] == 'answer.add').map((o) => o['rid']),
          ['r3']);
      expect(serverOps.where((o) => o['t'] == 'answer.add').length, 1);
    });

    test('оба добавили по новому вопросу с ответом — question.add присутствует', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      final current = _doc(
        qids: ['q1', 'q-new'],
        answersByQid: {
          'q1': ['r1'],
          'q-new': ['rn1'],
        },
      );

      final ops = buildReportOps(base, current);
      final qAdds = ops.where((o) => o['t'] == 'question.add').toList();
      expect(qAdds.length, 1);
      expect(qAdds.first['qid'], 'q-new');
      expect(qAdds.first['afterQid'], 'q1');
      expect(
        ops.where((o) => o['t'] == 'answer.add' && o['qid'] == 'q-new').length,
        1,
      );
    });
  });

  group('buildReportOps: конфликт одной ячейки', () {
    test('один и тот же rid+lang изменён — answer.update c baseUpdatedAt', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      _cell(base, 'q1', 'r1')['text'] = 'общий';
      _cell(base, 'q1', 'r1')['updatedAt'] = 1;

      final current = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      _cell(current, 'q1', 'r1')['text'] = 'мой текст';
      _cell(current, 'q1', 'r1')['updatedAt'] = 2;

      final ops = buildReportOps(base, current);
      final updates =
          ops.where((o) => o['t'] == 'answer.update' && o['rid'] == 'r1').toList();
      expect(updates.length, 1);
      expect(updates.first['lang'], 'RU');
      expect(updates.first['baseUpdatedAt'], 1);
      expect((updates.first['fields'] as Map)['text'], 'мой текст');
    });

    test('разные языки одной строки — это две независимые ячейки (разные ops)', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      (base['availableLanguages'] as List).add('EN');

      final current = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      (current['availableLanguages'] as List).add('EN');

      // RU правит один пользователь, EN — другой: добавляем ячейки языков.
      _cell(base, 'q1', 'r1')['text'] = '';
      final currentRow = ((current['answers'] as Map)['q1'] as List).first as Map;
      final langs = currentRow['localizations'] as Map<String, dynamic>;
      langs['RU'] = {'id': 'ru', 'text': 'по-русски', 'updatedAt': 5};
      langs['EN'] = {'id': 'en', 'text': 'in English', 'updatedAt': 6};

      final baseRow = ((base['answers'] as Map)['q1'] as List).first as Map;
      (baseRow['localizations'] as Map<String, dynamic>)['RU'] =
          {'id': 'ru', 'text': '', 'updatedAt': 1};
      (baseRow['localizations'] as Map<String, dynamic>)['EN'] =
          {'id': 'en', 'text': '', 'updatedAt': 1};

      final ops = buildReportOps(base, current);
      final updates =
          ops.where((o) => o['t'] == 'answer.update' && o['rid'] == 'r1').toList();
      // Каждая языковая ячейка — отдельная op (merge на сервере не конфликтует).
      expect(updates.map((o) => o['lang']).toSet(), {'RU', 'EN'});
    });
  });

  group('buildReportOps: no-op и удаления', () {
    test('без изменений — ops пустой', () {
      final doc = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      expect(buildReportOps(doc, doc), isEmpty);
      expect(reportHasChanges(doc, doc), isFalse);
    });

    test('удаление строки — answer.remove', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1', 'r2']});
      final current = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      final ops = buildReportOps(base, current);
      expect(ops.where((o) => o['t'] == 'answer.remove').map((o) => o['rid']),
          ['r2']);
    });

    test('переименование отчёта — meta op', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      final current = _doc(
        qids: ['q1'],
        answersByQid: {'q1': ['r1']},
        reportName: 'Новое имя',
      );
      final ops = buildReportOps(base, current);
      final meta = ops.firstWhere((o) => o['t'] == 'meta');
      expect((meta['fields'] as Map)['reportName'], 'Новое имя');
    });

    test('добавление медиа к строке — answer.setMedia', () {
      final base = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      final current = _doc(qids: ['q1'], answersByQid: {'q1': ['r1']});
      final row =
          ((current['answers'] as Map)['q1'] as List).first as Map;
      row['markers'] = {
        'attention': false,
        'needsWork': false,
        'rowId': 'r1',
        'media': [
          {
            'serverFileId': 'f-1',
            'name': 'photo.jpg',
            'type': 'image/jpeg',
          },
        ],
      };

      final ops = buildReportOps(base, current);
      final setMedia =
          ops.where((o) => o['t'] == 'answer.setMedia' && o['rid'] == 'r1');
      expect(setMedia.length, 1);
      expect(
        (setMedia.first['media'] as List).first['serverFileId'],
        'f-1',
      );
    });
  });
}
