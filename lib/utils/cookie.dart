// ============================================================
// Cookie utilities - conditional import.
// Web: cookie_web.dart (использует dart:html)
// Non-web: cookie_stub.dart (no-op)
// ============================================================

export 'cookie_stub.dart'
    if (dart.library.html) 'cookie_web.dart';
