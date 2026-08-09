// ============================================================
// Upload helpers — unified conditional export.
//
// Web: upload_helper_web.dart (dart:html + XMLHttpRequest)
// Native: upload_helper_native.dart (dart:io + http package)
// Stub (other): upload_helper_stub.dart (UnsupportedError)
//
// Потребители импортируют только этот файл — условный импорт
// выбирает нужную реализацию автоматически.
// ============================================================

export 'upload_helper_stub.dart'
    if (dart.library.html) 'upload_helper_web.dart'
    if (dart.library.io) 'upload_helper_native.dart';
