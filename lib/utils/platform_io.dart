// ============================================================
// Conditional import shim для dart:io на web-платформе.
//
// Использование:
//   import 'package:easy_tab/utils/platform_io.dart'
//       if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
//
// На native (Android/iOS/Windows/macOS/Linux) — реальный dart:io.
// На web — stub-файл platform_io_web.dart с классами-пустышками,
// которые бросают UnsupportedError при вызове (но позволяют коду
// компилироваться, т.к. все реальные вызовы защищены kIsWeb-проверками).
// ============================================================

export 'dart:io'
    show
        File,
        Directory,
        Platform,
        SocketException,
        FileMode,
        FileStat,
        FileSystemEntity,
        FileSystemException,
        IOException,
        InternetAddress,
        IOSink,
        Process,
        ProcessResult,
        RandomAccessFile,
        FileLock;
