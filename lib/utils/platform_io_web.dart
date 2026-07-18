// ============================================================
// Web-stub для dart:io — позволяет коду компилироваться на web.
//
// Все методы бросают UnsupportedError при вызове. Реальная логика
// на web либо не вызывает эти методы (защищена kIsWeb), либо
// использует альтернативные реализации (bytes вместо File).
//
// ИСПОЛЬЗОВАТЬ ТОЛЬКО ЧЕРЕЗ CONDITIONAL IMPORT:
//   import 'package:easy_tab/utils/platform_io.dart'
//       if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
// ============================================================

import 'dart:async';
import 'dart:convert';

Never _unsupported(String symbol) {
  throw UnsupportedError('dart:io.$symbol не доступно на web-платформе');
}

class IOException implements Exception {
  const IOException();
  @override
  String toString() => 'IOException';
}

/// Stub для SocketException — нужен только для `on SocketException` catch.
/// На web http-пакет бросает другие исключения, поэтому catch никогда не сработает,
/// но тип должен существовать для компиляции.
class SocketException implements IOException {
  final dynamic message;
  final InternetAddress? address;
  final int? port;
  const SocketException(this.message, {this.address, this.port});
  @override
  String toString() => 'SocketException: $message';
}

class InternetAddress {
  final String address;
  final String? host;
  const InternetAddress(this.address, {this.host});
  static const InternetAddress loopbackIPv4 = InternetAddress('127.0.0.1');
  static const InternetAddress loopbackIPv6 = InternetAddress('::1');
  static const InternetAddress anyIPv4 = InternetAddress('0.0.0.0');
  static const InternetAddress anyIPv6 = InternetAddress('::');
}

class Platform {
  static const String pathSeparator = '/';
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isFuchsia = false;
  static const String operatingSystem = 'web';
  static const String? executable = null;
  static const String? resolvedExecutable = null;
  static const Uri? script = null;
  static const List<String> executableArguments = [];
  static const Map<String, String> environment = {};
  static const String? packageConfig = null;
  static const String? version = null;
  static const int numberOfProcessors = 1;
  static const String localeName = 'en_US';
}

class FileMode {
  const FileMode(this._mode);
  final int _mode;
  static const FileMode read = FileMode(0);
  static const FileMode write = FileMode(1);
  static const FileMode append = FileMode(2);
  static const FileMode writeOnly = FileMode(3);
  static const FileMode writeOnlyAppend = FileMode(4);
}

class FileLock {
  const FileLock(this._type);
  final int _type;
  static const FileLock shared = FileLock(1);
  static const FileLock exclusive = FileLock(2);
  static const FileLock blockingShared = FileLock(3);
  static const FileLock blockingExclusive = FileLock(4);
}

class RandomAccessFile {
  Future<void> close() async => _unsupported('RandomAccessFile.close');
  void closeSync() => _unsupported('RandomAccessFile.closeSync');
  Future<int> readByte() async => _unsupported('RandomAccessFile.readByte');
  int readByteSync() => _unsupported('RandomAccessFile.readByteSync');
  Future<int> writeByte(int value) async =>
      _unsupported('RandomAccessFile.writeByte');
  int writeByteSync(int value) => _unsupported('RandomAccessFile.writeByteSync');
  Future<int> position() async => _unsupported('RandomAccessFile.position');
  int positionSync() => _unsupported('RandomAccessFile.positionSync');
  Future<int> length() async => _unsupported('RandomAccessFile.length');
  int lengthSync() => _unsupported('RandomAccessFile.lengthSync');
}

class FileStat {
  final DateTime changed;
  final DateTime modified;
  final DateTime accessed;
  final int mode;
  final int size;
  // НЕ const — DateTime.utc в этом SDK не const-callable в анализаторе.
  // Используем фабрику с предопределёнными значениями.
  FileStat._internal(this.changed, this.modified, this.accessed, this.mode, this.size);
  static FileStat statSync(String path) => _empty;
  static Future<FileStat> stat(String path) async => _empty;
  static final FileStat _empty = FileStat._internal(
      _Epoch.zero, _Epoch.zero, _Epoch.zero, 0, 0);
  bool get isFile => false;
  bool get isDirectory => false;
  bool get isLink => false;
  static FileStat get notFound => _empty;
}

class _Epoch {
  static final DateTime zero = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Базовый класс для файловых сущностей. На web все операции бросают
/// UnsupportedError — реальные вызовы защищены kIsWeb.
class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);
  Future<bool> exists() async => false;
  bool existsSync() => false;
  // NOTE: статические isFile/isDirectory/isLink и instance-геттеры
  // намеренно не объявляются в базовом классе, чтобы не было конфликта
  // имён. Подклассы (File/Directory) определяют свои instance-геттеры.
}

class FileSystemException implements IOException {
  final String message;
  final String path;
  final OSError? osError;
  const FileSystemException([this.message = '', this.path = '', this.osError]);
  @override
  String toString() => 'FileSystemException: $message';
}

class OSError {
  final String message;
  final int errorCode;
  const OSError([this.message = '', this.errorCode = 0]);
}

/// Минимальный IOSink — НЕ реализует StreamSink/StringSink (всё равно на web
/// не вызывается). Методы-заглушки возвращают dynamic или бросают UnsupportedError.
class IOSink {
  Encoding get encoding => utf8;
  set encoding(Encoding value) => _unsupported('IOSink.encoding');
  void write(Object? obj) => _unsupported('IOSink.write');
  void writeln([Object? obj = '']) => _unsupported('IOSink.writeln');
  void writeCharCode(int charCode) => _unsupported('IOSink.writeCharCode');
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _unsupported('IOSink.writeAll');
  void add(List<int> data) => _unsupported('IOSink.add');
  void addError(Object error, [StackTrace? stackTrace]) =>
      _unsupported('IOSink.addError');
  Future<void> addStream(Stream<List<int>> stream) async =>
      _unsupported('IOSink.addStream');
  Future<void> flush() async => _unsupported('IOSink.flush');
  Future<void> close() async => _unsupported('IOSink.close');
  bool get isClosed => true;
}

class File implements FileSystemEntity {
  @override
  final String path;
  File(this.path);

  @override
  Future<bool> exists() async => false;
  @override
  bool existsSync() => false;

  Future<File> create({bool recursive = false, bool exclusive = false}) async =>
      _unsupported('File.create');
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _unsupported('File.createSync');

  Future<File> rename(String newPath) async => _unsupported('File.rename');
  File renameSync(String newPath) => _unsupported('File.renameSync');

  Future<File> copy(String newPath) async => _unsupported('File.copy');
  File copySync(String newPath) => _unsupported('File.copySync');

  Future<int> length() async => _unsupported('File.length');
  int lengthSync() => _unsupported('File.lengthSync');

  Future<DateTime> lastModified() async => _unsupported('File.lastModified');
  DateTime lastModifiedSync() => _unsupported('File.lastModifiedSync');
  Future<void> setLastModified(DateTime time) async =>
      _unsupported('File.setLastModified');
  void setLastModifiedSync(DateTime time) =>
      _unsupported('File.setLastModifiedSync');

  Future<List<int>> readAsBytes() async => _unsupported('File.readAsBytes');
  List<int> readAsBytesSync() => _unsupported('File.readAsBytesSync');
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      _unsupported('File.readAsString');
  String readAsStringSync({Encoding encoding = utf8}) =>
      _unsupported('File.readAsStringSync');
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      _unsupported('File.readAsLines');
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _unsupported('File.readAsLinesSync');

  Future<File> writeAsBytes(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) async =>
      _unsupported('File.writeAsBytes');
  void writeAsBytesSync(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) =>
      _unsupported('File.writeAsBytesSync');

  Future<File> writeAsString(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) async =>
      _unsupported('File.writeAsString');
  void writeAsStringSync(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      _unsupported('File.writeAsStringSync');

  Stream<List<int>> openRead([int? start, int? end]) => const Stream.empty();
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) =>
      _unsupported('File.openWrite');

  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _unsupported('File.openSync');
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _unsupported('File.open');

  FileStat statSync() => FileStat.notFound;
  Future<FileStat> stat() async => statSync();

  Future<File> delete({bool recursive = false}) async =>
      _unsupported('File.delete');
  void deleteSync({bool recursive = false}) => _unsupported('File.deleteSync');

  bool get isFile => true;
  bool get isDirectory => false;
  bool get isLink => false;
}

class Directory implements FileSystemEntity {
  @override
  final String path;
  Directory(this.path);

  static Directory get systemTemp => Directory('/tmp');

  @override
  Future<bool> exists() async => false;
  @override
  bool existsSync() => false;

  Future<Directory> create({bool recursive = false}) async =>
      _unsupported('Directory.create');
  void createSync({bool recursive = false}) =>
      _unsupported('Directory.createSync');

  Future<Directory> rename(String newPath) async =>
      _unsupported('Directory.rename');
  Directory renameSync(String newPath) => _unsupported('Directory.renameSync');

  Future<Directory> delete({bool recursive = false}) async =>
      _unsupported('Directory.delete');
  void deleteSync({bool recursive = false}) =>
      _unsupported('Directory.deleteSync');

  Stream<FileSystemEntity> list(
          {bool recursive = false, bool followLinks = true}) =>
      _unsupported('Directory.list');

  List<FileSystemEntity> listSync(
          {bool recursive = false, bool followLinks = true}) =>
      _unsupported('Directory.listSync');

  FileStat statSync() => FileStat.notFound;
  Future<FileStat> stat() async => statSync();

  bool get isFile => false;
  bool get isDirectory => true;
  bool get isLink => false;
}

class ProcessResult {
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
  const ProcessResult._internal(this.pid, this.exitCode, this.stdout, this.stderr);
}

class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    RunMode? runMode,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
    bool includeParentEnvironment = true,
    Map<String, String>? environment,
    bool runInShell = false,
    Directory? workingDirectory,
  }) async =>
      _unsupported('Process.run');

  static ProcessResult runSync(
    String executable,
    List<String> arguments, {
    RunMode runMode = RunMode.normal,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
    bool includeParentEnvironment = true,
    Map<String, String>? environment,
    bool runInShell = false,
    Directory? workingDirectory,
  }) =>
      _unsupported('Process.runSync');
}

class RunMode {
  const RunMode(this._mode);
  final String _mode;
  static const RunMode normal = RunMode('normal');
  static const RunMode inProcess = RunMode('inProcess');
}
