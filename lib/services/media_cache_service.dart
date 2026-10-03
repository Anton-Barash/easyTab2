// ============================================================
// MediaCacheService — дисковый кэш сетевых медиа на native.
//
// Миниатюры (и просмотренные полные фото), добавленные другими
// пользователями, скачиваются с KS3/прокси и сохраняются в папке
// <appDocs>/media_cache/<reportKey>/. Так они доступны офлайн и
// не качаются повторно. Неактуальные файлы (медиа удалено из
// отчёта) удаляются при синхронизации кэша (pruneKeep).
//
// Имена файлов детерминированы (FNV-1a от относительного пути медиа),
// поэтому виджет может проверить наличие синхронно, без обращения
// к сети.
//
// Файлы: на web dart:io недоступен — используем conditional import и
// пакет http (кросс-платформенный). Все реальные вызовы защищены kIsWeb.
// ============================================================

import 'dart:convert';

import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  static const _rootDirName = 'media_cache';

  /// Готовая корневая папка кэша (null — ещё не инициализирована
  /// либо платформа без файловой системы).
  static Directory? _baseDir;

  /// Инициализация (ленивая, идемпотентная). Вызывается из провайдера
  /// перед загрузкой отчёта, чтобы виджеты могли синхронно проверять
  /// пути [cachedThumbPath]/[cachedFullPath].
  static Future<void> ensureInitialized() async {
    if (kIsWeb || _baseDir != null) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}${Platform.pathSeparator}$_rootDirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _baseDir = dir;
    } catch (e) {
      if (kDebugMode) debugPrint('MediaCacheService.init error: $e');
    }
  }

  /// Папка кэша конкретного отчёта. reportKey — любой уникальный
  /// идентификатор (serverReportId или share-токен).
  static Directory? _reportDir(String reportKey) {
    final base = _baseDir;
    if (base == null || reportKey.isEmpty) return null;
    return Directory(
      '${base.path}${Platform.pathSeparator}${_safeName(reportKey)}',
    );
  }

  /// Имя папки отчёта: только безопасные символы (share-токен hex,
  /// числовой id — ок; на всякий случай чистим остальное).
  static String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Детерминированное имя файла кэша для относительного пути медиа
  /// (FNV-1a 64-bit, hex — стабилен между запусками без внешних пакетов).
  static String _fileName(String relPath, String suffix) {
    var hash = 0xcbf29ce484222325;
    for (final code in utf8.encode(relPath)) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${hash.toRadixString(16)}$suffix';
  }

  /// Путь к закэшированной миниатюре фото или null, если кэш не готов.
  /// Синхронный — используется виджетами.
  static String? cachedThumbPath(String? reportKey, String? relPath) =>
      _cachedPath(reportKey, relPath, '_thumb.jpg');

  /// Путь к закэшированному полному фото или null.
  static String? cachedFullPath(String? reportKey, String? relPath) =>
      _cachedPath(reportKey, relPath, '_full.bin');

  static String? _cachedPath(
    String? reportKey,
    String? relPath,
    String suffix,
  ) {
    if (reportKey == null || reportKey.isEmpty) return null;
    if (relPath == null || relPath.isEmpty) return null;
    final dir = _reportDir(reportKey);
    if (dir == null) return null;
    return '${dir.path}${Platform.pathSeparator}${_fileName(relPath, suffix)}';
  }

  /// Скачать [url] в файл [savePath] (папка создаётся при необходимости).
  /// Возвращает путь при успехе, иначе null. Уже существующий файл не
  /// перекачивается, если [overwrite] == false.
  static Future<String?> downloadToFile(
    String url,
    String savePath, {
    bool overwrite = false,
  }) async {
    if (kIsWeb) return null;
    try {
      final f = File(savePath);
      if (!overwrite && await f.exists()) return savePath;
      await f.parent.create(recursive: true);

      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      final tmp = File('$savePath.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(savePath);
      return savePath;
    } catch (e) {
      if (kDebugMode) debugPrint('MediaCacheService.download error: $e');
      return null;
    }
  }

  /// Удалить из кэша отчёта файлы, не входящие в [keepAbsolutePaths].
  /// Вызывается после обновления кэша — убирает миниатюры/фото удалённых
  /// медиа («старые неактуальные»).
  static Future<void> pruneKeep(
    String reportKey,
    Set<String> keepAbsolutePaths,
  ) async {
    if (kIsWeb) return;
    try {
      final dir = _reportDir(reportKey);
      if (dir == null || !await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        if (!keepAbsolutePaths.contains(e.path)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MediaCacheService.prune error: $e');
    }
  }

  /// Полностью очистить кэш отчёта (например, при удалении отчёта).
  static Future<void> clearReport(String reportKey) async {
    if (kIsWeb) return;
    try {
      final dir = _reportDir(reportKey);
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MediaCacheService.clear error: $e');
    }
  }
}