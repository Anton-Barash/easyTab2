// ============================================================
// Утилита для открытия HTML в браузере (web-версия)
// ============================================================
// На web: открывает HTML в новой вкладке через Blob URL.
// На mobile/desktop: заглушка (используется другой механизм).
//
// Использует conditional import:
//   import 'open_html.dart' if (dart.library.html) 'open_html_web.dart';
// ============================================================

export 'open_html_stub.dart' if (dart.library.html) 'open_html_web.dart';
