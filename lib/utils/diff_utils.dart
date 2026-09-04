
import '../models/report_models.dart';

/// Diff operation structure:
/// {
///   'path': 'translations.&lt;qid&gt;.&lt;lang&gt;',
///   'op': 'add' | 'update' | 'remove' | 'move',
///   'id': '&lt;answerId&gt;',
///   'index': &lt;index&gt;, // target index for add/move, original index for remove
///   'value': &lt;TranslationAnswer.toJson()&gt; // for add/update
/// }

List<Map<String, dynamic>> computeReportDiff(Report base, Report updated) {
  final ops = <Map<String, dynamic>>[];

  // Gather all question ids (as strings) present in either report
  final qids = <String>{}..addAll(base.translations.keys)..addAll(updated.translations.keys);

  for (final qid in qids) {
    final baseLangMap = base.translations[qid] ?? {};
    final updatedLangMap = updated.translations[qid] ?? {};

    final langs = <String>{}..addAll(baseLangMap.keys)..addAll(updatedLangMap.keys);

    for (final lang in langs) {
      final baseList = List<TranslationAnswer>.from(baseLangMap[lang] ?? []);
      final updatedList = List<TranslationAnswer>.from(updatedLangMap[lang] ?? []);

      // Build id -> index maps
      final baseIndexById = <String, int>{};
      for (var i = 0; i < baseList.length; i++) {
        baseIndexById[baseList[i].id] = i;
      }

      final updatedIndexById = <String, int>{};
      for (var i = 0; i < updatedList.length; i++) {
        updatedIndexById[updatedList[i].id] = i;
      }

      // Removals: ids present in base but not in updated
      for (final id in baseIndexById.keys) {
        if (!updatedIndexById.containsKey(id)) {
          ops.add({
            'path': 'translations.$qid.$lang',
            'op': 'remove',
            'id': id,
            'index': baseIndexById[id],
          });
        }
      }

      // Additions: ids present in updated but not in base
      for (final id in updatedIndexById.keys) {
        if (!baseIndexById.containsKey(id)) {
          final answer = updatedList[updatedIndexById[id]!];
          ops.add({
            'path': 'translations.$qid.$lang',
            'op': 'add',
            'id': id,
            'index': updatedIndexById[id],
            'value': answer.toJson(),
          });
        }
      }

      // Updates: ids in both but content changed
      for (final id in baseIndexById.keys) {
        if (updatedIndexById.containsKey(id)) {
          final baseAns = baseList[baseIndexById[id]!];
          final updatedAns = updatedList[updatedIndexById[id]!];

          // Compare meaningful fields: text, authorId, fingerprint, updatedAt
          final eq = baseAns.text == updatedAns.text &&
              (baseAns.authorId ?? '') == (updatedAns.authorId ?? '') &&
              (baseAns.fingerprint ?? '') == (updatedAns.fingerprint ?? '') &&
              (baseAns.updatedAt ?? 0) == (updatedAns.updatedAt ?? 0);

          if (!eq) {
            ops.add({
              'path': 'translations.$qid.$lang',
              'op': 'update',
              'id': id,
              'index': updatedIndexById[id],
              'value': updatedAns.toJson(),
            });
          }
        }
      }

      // Moves: same ids but index changed
      for (final id in updatedIndexById.keys) {
        if (baseIndexById.containsKey(id)) {
          final oldIdx = baseIndexById[id]!;
          final newIdx = updatedIndexById[id]!;
          if (oldIdx != newIdx) {
            ops.add({
              'path': 'translations.$qid.$lang',
              'op': 'move',
              'id': id,
              'from': oldIdx,
              'to': newIdx,
            });
          }
        }
      }
    }
  }

  return ops;
}
