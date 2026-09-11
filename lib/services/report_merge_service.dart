// ============================================================
// Diff-движок для merge-by-ID (Фаза 2).
//
// Сравнивает base-документ и current-документ в canonical v2 виде
// (см. docs/SERVER_SYNC_SPEC.md §2, §3.1) и порождает список ops:
//   question.add / question.remove
//   answer.add / answer.update / answer.remove
//   meta
//
// Ops адресуются по стабильным id (qid / rid), text-updates несут
// baseUpdatedAt (per-cell optimistic lock). Чистый Dart без Flutter —
// используется и в приложении, и в unit-тестах.
// ============================================================

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List<dynamic> _asList(dynamic v) => v is List ? v : const [];

int? _asInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '');

/// updatedAt ячейки для optimistic-lock (fallback: createdAt, затем 0).
int _cellUpdatedAt(Map<String, dynamic> cell) =>
    _asInt(cell['updatedAt']) ?? _asInt(cell['createdAt']) ?? 0;

String _cellText(Map<String, dynamic> cell) => cell['text']?.toString() ?? '';

/// Список media-объектов строки (из canonical markers.media).
List<dynamic> _rowMedia(Map<String, dynamic> row) {
  final markers = _asMap(row['markers']);
  return _asList(markers['media']);
}

/// Стабильная сигнатура media строки: serverFileId ?? localPath ?? name.
/// Сравнение по сигнатуре игнорирует runtime-флаги (isUploading и т.п.).
String _mediaSignature(Map<String, dynamic> row) {
  final media = _rowMedia(row);
  return media
      .map((raw) {
        final m = _asMap(raw);
        return (m['serverFileId']?.toString() ??
                m['localPath']?.toString() ??
                m['name']?.toString() ??
                '');
      })
      .join('|');
}

/// Список вопросов в порядке документа: [{qid, id, legacyId, localizations}].
List<Map<String, dynamic>> _orderedQuestions(Map<String, dynamic> doc) {
  final result = <Map<String, dynamic>>[];
  for (final raw in _asList(doc['questions'])) {
    final q = _asMap(raw);
    final qid = q['qid']?.toString() ?? '';
    if (qid.isEmpty) continue;
    result.add({
      'qid': qid,
      'id': q['id'],
      'legacyId': q['legacyId'],
      'localizations': q['localizations'],
    });
  }
  return result;
}

/// Упорядоченный список rid вопроса (из answers[qid]).
List<String> _orderedRids(Map<String, dynamic> doc, String qid) {
  final rows = _asList(_asMap(doc['answers'])[qid]);
  final result = <String>[];
  for (final raw in rows) {
    final rid = _asMap(raw)['rid']?.toString() ?? '';
    if (rid.isNotEmpty) result.add(rid);
  }
  return result;
}

Map<String, dynamic> _rowById(Map<String, dynamic> doc, String qid, String rid) {
  for (final raw in _asList(_asMap(doc['answers'])[qid])) {
    final row = _asMap(raw);
    if ((row['rid']?.toString() ?? '') == rid) return row;
  }
  return <String, dynamic>{};
}

/// Построить список ops между двумя canonical-документами.
///
/// Семантика (см. спец. §4): добавления/удаления всегда сливаются,
/// обновление одной и той же ячейки адресуется по (qid, rid, lang) и несёт
/// baseUpdatedAt — сервер по нему решает: применить или вернуть 409.
List<Map<String, dynamic>> buildReportOps(
  Map<String, dynamic> baseDoc,
  Map<String, dynamic> currentDoc,
) {
  final ops = <Map<String, dynamic>>[];
  final now = DateTime.now().millisecondsSinceEpoch;

  // ---------- Метаданные отчёта ----------
  const metaFields = <String>[
    'reportName',
    'productType',
    'factory',
    'model',
    'headerImagePath',
  ];
  final meta = <String, dynamic>{};
  for (final f in metaFields) {
    final b = baseDoc[f];
    final c = currentDoc[f];
    if (b != c) meta[f] = c;
  }
  if (meta.isNotEmpty) {
    ops.add({'t': 'meta', 'fields': meta});
  }

  // ---------- Вопросы ----------
  final baseQuestions = _orderedQuestions(baseDoc);
  final currentQuestions = _orderedQuestions(currentDoc);
  final baseQids = baseQuestions.map((q) => q['qid']).toSet();
  final currentQids = currentQuestions.map((q) => q['qid']).toSet();

  for (final q in baseQuestions) {
    final qid = q['qid'] as String;
    if (!currentQids.contains(qid)) {
      ops.add({'t': 'question.remove', 'qid': qid});
    }
  }

  for (var i = 0; i < currentQuestions.length; i++) {
    final q = currentQuestions[i];
    final qid = q['qid'] as String;
    if (baseQids.contains(qid)) continue;
    final afterQid = i > 0 ? currentQuestions[i - 1]['qid'] : null;
    ops.add({
      't': 'question.add',
      'qid': qid,
      'afterQid': afterQid,
      // id/legacyId помогают серверу при дедупе параллельной миграции
      // (два клиента мигрировали один legacy-документ).
      'id': q['id'],
      'legacyId': q['legacyId'],
      'question': {
        'id': q['id'],
        'legacyId': q['legacyId'],
        'localizations': q['localizations'],
      },
    });
  }

  // ---------- Ответы ----------
  final allQids = <String>{...baseQids, ...currentQids};
  for (final qid in allQids) {
    final baseRids = _orderedRids(baseDoc, qid);
    final currentRids = _orderedRids(currentDoc, qid);
    final baseRidSet = baseRids.toSet();
    final currentRidSet = currentRids.toSet();

    // Удалённые строки.
    for (final rid in baseRids) {
      if (!currentRidSet.contains(rid)) {
        ops.add({'t': 'answer.remove', 'qid': qid, 'rid': rid});
      }
    }

    // Добавленные строки (в порядке current) — после соседнего rid.
    for (var i = 0; i < currentRids.length; i++) {
      final rid = currentRids[i];
      if (baseRidSet.contains(rid)) continue;
      final afterRid = i > 0 ? currentRids[i - 1] : null;
      ops.add({
        't': 'answer.add',
        'qid': qid,
        'rid': rid,
        'afterRid': afterRid,
        'row': _rowById(currentDoc, qid, rid),
      });
    }

    // Изменения текста ячеек и медиа существующих строк.
    for (final rid in baseRidSet.intersection(currentRidSet)) {
      final baseRow = _rowById(baseDoc, qid, rid);
      final currentRow = _rowById(currentDoc, qid, rid);
      final baseCells = _asMap(baseRow['localizations']);
      final currentCells = _asMap(currentRow['localizations']);

      final langs = <String>{
        ...baseCells.keys,
        ...currentCells.keys,
      };
      for (final lang in langs) {
        final bCell = _asMap(baseCells[lang]);
        final cCell = _asMap(currentCells[lang]);
        if (_cellText(bCell) == _cellText(cCell)) continue;
        ops.add({
          't': 'answer.update',
          'qid': qid,
          'rid': rid,
          'lang': lang,
          // baseUpdatedAt — per-cell optimistic lock (время правки в базе).
          'baseUpdatedAt': _cellUpdatedAt(bCell),
          // baseText — текст, на основе которого сделана правка. Сервер по нему
          // распознаёт, что ячейку успел изменить другой автор (не зависит от
          // расхождения часов между устройствами).
          'baseText': _cellText(bCell),
          'fields': {
            'text': _cellText(cCell),
            'isEmpty': _cellText(cCell).isEmpty,
            'updatedAt': _cellUpdatedAt(cCell) == 0
                ? now
                : _cellUpdatedAt(cCell),
          },
        });
      }

      // Медиа строки изменились (добавлены/удалены/заменены файлы).
      if (_mediaSignature(baseRow) != _mediaSignature(currentRow)) {
        ops.add({
          't': 'answer.setMedia',
          'qid': qid,
          'rid': rid,
          'media': _rowMedia(currentRow),
        });
      }
    }
  }

  return ops;
}

/// Есть ли реальные изменения между документами.
bool reportHasChanges(
  Map<String, dynamic> baseDoc,
  Map<String, dynamic> currentDoc,
) =>
    buildReportOps(baseDoc, currentDoc).isNotEmpty;
