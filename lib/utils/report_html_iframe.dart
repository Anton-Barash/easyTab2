// ============================================================
// Conditional import: web-версия использует dart:html,
// на mobile/desktop — stub.
// ============================================================

export 'report_html_iframe_stub.dart'
    if (dart.library.html) 'report_html_iframe_web.dart';
