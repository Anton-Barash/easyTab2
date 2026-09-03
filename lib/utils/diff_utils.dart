// Minimal diff utilities used by sync manager.

Map<String, dynamic> computeDiff(Map<String, dynamic> local, Map<String, dynamic>? base) {
  // Very small naive implementation: if base is null -> return full reportData
  if (base == null) {
    return {'reportData': local};
  }

  // For now, detect changes by simple deep comparison of top-level keys like translations, markers, questions.
  // A production implementation should compute per-answer diffs.
  final Map<String, dynamic> changes = {};

  for (final key in local.keys) {
    final l = local[key];
    final b = base[key];
    if (b == null) {
      changes[key] = l;
      continue;
    }
    if (!_deepEquals(l, b)) {
      changes[key] = l;
    }
  }

  return changes;
}

bool _deepEquals(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
