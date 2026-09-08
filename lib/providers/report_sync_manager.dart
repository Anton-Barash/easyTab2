import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/report_summary.dart';
import '../services/api_service.dart';

/// ReportSyncManager: minimal, iterative implementation.
class ReportSyncManager {
  ReportSyncManager();

  /// Если последняя синхронизация закончилась постоянным отказом (403/истёк
  /// срок права), содержит имя локальной папки, которую мы отвязали от
  /// сервера. Иначе null.
  String? lastDeniedUnlinkedFolder;

  Future<List<String>> _listLocalReportFolders(String reportsDir) async {
    // На web нет локальной файловой системы (path_provider отсутствует) —
    // локальные отчёты не существуют, список строится только из сервера.
    if (kIsWeb) return [];
    try {
      final d = Directory(reportsDir);
      if (!await d.exists()) return [];
      final folders = <String>[];
      await for (final e in d.list()) {
        if (e is Directory) folders.add(e.path.split(Platform.pathSeparator).last);
      }
      return folders;
    } catch (e) {
      if (kDebugMode) print('listLocalReportFolders error: $e');
      return [];
    }
  }

  Future<String> _getReportsDir() async {
    // На web path_provider недоступен; локальные папки там не используются.
    if (kIsWeb) return '';
    final appDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${appDir.path}${Platform.pathSeparator}reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir.path;
  }

  Future<List<ReportSummary>> loadCombinedList() async {
    final reportsDirPath = await _getReportsDir();
    final localFolders = await _listLocalReportFolders(reportsDirPath);

    List<Map<String, dynamic>> serverList = [];
    if (ApiService.authToken != null && ApiService.authToken!.isNotEmpty) {
      final res = await ApiService.listReports();
      if (res.success && res.data != null) {
        final data = res.data;
        final reports = (data is Map) ? (data as Map)['reports'] : null;
        if (reports is List) {
          serverList = reports.cast<Map<String, dynamic>>();
        } else if (data is List) {
          serverList = (data as List).cast<Map<String, dynamic>>();
        }
      }
    }

    final serverById = <String, Map<String, dynamic>>{};
    for (final s in serverList) {
      final id = (s['id'] ?? s['reportId'] ?? s['publicId'])?.toString();
      if (id != null) serverById[id] = s;
    }

    final out = <ReportSummary>[];

    for (final s in serverList) {
      final id = (s['id'] ?? s['reportId'])?.toString() ?? s['publicId']?.toString() ?? '';
      final title = (s['title'] ?? s['name'] ?? 'Untitled').toString();

      // Дата создания отчёта на сервере.
      final createdRaw = s['createdAt'] ?? s['created'];
      DateTime createdAt = DateTime.now();
      if (createdRaw != null) {
        final parsed = DateTime.tryParse(createdRaw.toString());
        if (parsed != null) createdAt = parsed.toLocal();
      }

      // Дата последнего изменения (если сервер её не отдал — берём дату создания).
      final modRaw = s['modifiedAt'] ?? s['updatedAt'] ?? s['modified'];
      DateTime modified = createdAt;
      if (modRaw != null) {
        final parsed = DateTime.tryParse(modRaw.toString());
        if (parsed != null) modified = parsed.toLocal();
      }

      final localFolderName = 'server_$id';
      final localExists = localFolders.contains(localFolderName);

      final status = localExists ? ReportSyncStatus.synced : ReportSyncStatus.cloudOnly;
      final version = s['version'] is int ? s['version'] as int : (s['ver'] is int ? s['ver'] as int : null);

      out.add(ReportSummary(
        id: id,
        title: title,
        createdAt: createdAt,
        modified: modified,
        localExists: localExists,
        onServer: true,
        serverVersion: version,
        status: status,
        localFolderPath: localExists
            ? '$reportsDirPath${Platform.pathSeparator}$localFolderName'
            : null,
      ));

      localFolders.remove(localFolderName);
    }

    for (final f in localFolders) {
      final summary = await _readLocalReportSummary(
        f,
        '$reportsDirPath${Platform.pathSeparator}$f',
      );
      out.add(summary);
    }

    // Сортируем по дате последнего изменения (сначала новые).
    out.sort((a, b) => b.modified.compareTo(a.modified));

    return out;
  }

  Future<ReportSummary> _readLocalReportSummary(
    String folderName,
    String folderPath,
  ) async {
    final folder = Directory(folderPath);
    String title = folderName;
    DateTime modified = DateTime.now();
    DateTime createdAt = modified;
    try {
      final jf = File('${folder.path}${Platform.pathSeparator}report.json');
      if (await jf.exists()) {
        final stat = await jf.lastModified();
        modified = stat;
        final str = await jf.readAsString();
        final map = jsonDecode(str) as Map<String, dynamic>;
        title = map['reportName']?.toString() ?? map['name']?.toString() ?? title;
        // В отчёте хранится метка создания (timestamp, мс с эпохи).
        final ts = map['timestamp'];
        if (ts is int) {
          createdAt = DateTime.fromMillisecondsSinceEpoch(ts);
        } else if (ts != null) {
          final parsed = DateTime.tryParse(ts.toString());
          if (parsed != null) createdAt = parsed;
        }
      }
    } catch (e) {
      if (kDebugMode) print('readLocalReportSummary error: $e');
    }

    return ReportSummary(
      id: folderName,
      title: title,
      createdAt: createdAt,
      modified: modified,
      localExists: true,
      onServer: false,
      serverVersion: null,
      status: ReportSyncStatus.localOnly,
      localFolderPath: folderPath,
    );
  }

  /// Скачать отчёт с сервера в «Мои отчёты» (локальная папка `server_<id>`).
  ///
  /// Возвращает имя папки (например, `server_5`) для обратной совместимости.
  Future<String?> downloadReportFromServer(int serverReportId) async {
    if (kIsWeb) return null;
    try {
      final base = await _getReportsDir();
      final path = await _downloadReportToDir(serverReportId, base);
      if (path.isEmpty) return null;
      return path.split(Platform.pathSeparator).last;
    } catch (e) {
      if (kDebugMode) print('downloadReportFromServer error: $e');
      return null;
    }
  }

  /// Скрытая рабочая копия облачного отчёта для «быстрого открытия».
  ///
  /// Скачивает report.json + медиа в кэш приложения (не в «Мои отчёты»),
  /// чтобы открыть отчёт на редактирование без появления в списке отчётов.
  /// Возвращает абсолютный путь к папке копии (или null при ошибке).
  Future<String?> downloadReportToCache(int serverReportId) async {
    if (kIsWeb) return null;
    try {
      final cache = await _getCloudCacheDir();
      final path = await _downloadReportToDir(serverReportId, cache);
      return path.isEmpty ? null : path;
    } catch (e) {
      if (kDebugMode) print('downloadReportToCache error: $e');
      return null;
    }
  }

  /// Синхронизация скрытой рабочей копии облачного отчёта с сервером.
  ///
  /// Загружает новые медиа и сохраняет report.json на сервер. Вызывается
  /// перед удалением временной копии, чтобы правки в «быстром открытии»
  /// не терялись.
  Future<bool> syncCloudSession(String absoluteFolderPath, int serverReportId) {
    return syncReport(
      localFolderName:
          absoluteFolderPath.split(Platform.pathSeparator).last,
      serverReportId: serverReportId,
      absoluteFolderPath: absoluteFolderPath,
    );
  }

  /// Удалить одну скрытую рабочую копию (после закрытия редактора).
  Future<void> deleteCloudCacheFolder(String folderPath) async {
    try {
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) print('deleteCloudCacheFolder error: $e');
    }
  }

  /// Очистить все скрытые рабочие копии (запускается при открытии списка,
  /// чтобы «осиротевшие» кэши после обрыва не копились на диске).
  Future<void> purgeCloudCache() async {
    if (kIsWeb) return;
    try {
      final cache = await _getCloudCacheDir();
      final dir = Directory(cache);
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) print('purgeCloudCache error: $e');
    }
  }

  String? _cloudCacheDir;

  Future<String> _getCloudCacheDir() async {
    if (_cloudCacheDir != null) return _cloudCacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final cache = Directory('${appDir.path}${Platform.pathSeparator}cloud_cache');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    _cloudCacheDir = cache.path;
    return cache.path;
  }

  /// Общая логика загрузки отчёта с сервера: пишет report.json и файлы
  /// медиа в папку `$baseDir/server_<id>`. Возвращает абсолютный путь
  /// папки, либо пустую строку при ошибке.
  Future<String> _downloadReportToDir(int serverReportId, String baseDir) async {
    final res = await ApiService.getReport(serverReportId);
    if (!res.success || res.data == null) return '';

    final responseData = res.data!;
    Map<String, dynamic> reportData = {};
    if (responseData.containsKey('report')) {
      final r = responseData['report'];
      if (r is Map) {
        if (r.containsKey('reportData')) {
          final rd = r['reportData'];
          if (rd is Map) reportData = Map<String, dynamic>.from(rd);
        } else if (r.containsKey('data')) {
          final rd = r['data'];
          if (rd is Map) reportData = Map<String, dynamic>.from(rd);
        }
      }
    } else if (responseData.containsKey('reportData')) {
      final rd = responseData['reportData'];
      if (rd is Map) reportData = Map<String, dynamic>.from(rd);
    } else {
      reportData = Map<String, dynamic>.from(responseData as Map);
    }

    final folderName = 'server_$serverReportId';
    final folderPath = '$baseDir${Platform.pathSeparator}$folderName';
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final jf = File('$folderPath${Platform.pathSeparator}report.json');
    await jf.writeAsString(jsonEncode(reportData));

    try {
      final urlsRes = await ApiService.getReportFileUrls(serverReportId);
      if (urlsRes.success && urlsRes.data != null && urlsRes.data is Map) {
        final urlsMap = urlsRes.data! as Map;
        final urls = Map<String, dynamic>.from(urlsMap['urls'] ?? urlsMap);
        for (final entry in urls.entries) {
          final rel = entry.key.toString();
          final url = entry.value?.toString();
          if (url == null || url.isEmpty) continue;
          try {
            final uri = Uri.parse(url);
            final resp = await http.get(uri);
            if (resp.statusCode == 200) {
              final target = File('$folderPath${Platform.pathSeparator}$rel');
              final parent = target.parent;
              if (!await parent.exists()) await parent.create(recursive: true);
              await target.writeAsBytes(resp.bodyBytes);
            } else {
              if (kDebugMode) {
                print('download file $url failed status ${resp.statusCode}');
              }
            }
          } catch (e) {
            if (kDebugMode) print('download file $url failed: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('getReportFileUrls error: $e');
    }

    return folderPath;
  }

  Future<bool> syncReport({required String localFolderName, int? serverReportId, int? baseVersion, String? absoluteFolderPath}) async {
    // На web нет локальных файлов — синхронизация локальной папки недоступна.
    if (kIsWeb) return false;
    lastDeniedUnlinkedFolder = null;
    try {
      final reportsDir = await _getReportsDir();
      final folderPath = absoluteFolderPath ??
          '$reportsDir${Platform.pathSeparator}$localFolderName';
      final jf = File('$folderPath${Platform.pathSeparator}report.json');
      if (!await jf.exists()) return false;
      final localJson = jsonDecode(await jf.readAsString()) as Map<String, dynamic>;

      final filesToUpload = <Map<String, String>>[];
      final markers = localJson['markers'] as Map<String, dynamic>?;
      if (markers != null) {
        for (final qEntry in markers.entries) {
          final qList = qEntry.value as List<dynamic>?;
          if (qList == null) continue;
          for (final marker in qList) {
            if (marker is! Map<String, dynamic>) continue;
            final mediaList = (marker['media'] as List<dynamic>?) ?? [];
            for (final m in mediaList) {
              if (m is! Map<String, dynamic>) continue;
              final localPath = m['localPath'] as String?;
              final serverFileId = m['serverFileId'] as String?;
              if (localPath != null && (serverFileId == null || serverFileId.isEmpty)) {
                final abs = '$folderPath${Platform.pathSeparator}$localPath';
                filesToUpload.add({'filePath': abs, 'relativePath': localPath});
              }
            }
          }
        }
      }

      if (filesToUpload.isNotEmpty) {
        final uploadRes = await ApiService.uploadFiles(files: filesToUpload, reportId: serverReportId);
        if (!uploadRes.success) {
          if (uploadRes.isPermanentAccessDenied) {
            // Право на редактирование истекло — отвязываем копию от сервера.
            lastDeniedUnlinkedFolder = await _detachFromServer(
              folderPath,
              isLibrary: absoluteFolderPath == null,
            );
          } else if (kDebugMode) {
            print('uploadFiles failed: $uploadRes.error');
          }
          return false;
        }

        final results = uploadRes.data?['results'] as List<dynamic>?;
        if (results != null) {
          for (final r in results) {
            try {
              if (r is! Map) continue;
              final rel = r['relativePath'] as String?;
              final fileObj = r['file'];
              String? fileId;
              if (fileObj is Map) {
                if (fileObj['id'] != null) {
                  fileId = fileObj['id'].toString();
                } else if (fileObj['file'] is Map && (fileObj['file'] as Map)['id'] != null) {
                  fileId = (fileObj['file'] as Map)['id'].toString();
                } else if (fileObj['fileId'] != null) {
                  fileId = fileObj['fileId'].toString();
                }
              }
              if (rel != null && fileId != null && markers != null) {
                for (final qEntry in markers.entries) {
                  final qList = qEntry.value as List<dynamic>?;
                  if (qList == null) continue;
                  for (final marker in qList) {
                    if (marker is! Map<String, dynamic>) continue;
                    final mediaList = (marker['media'] as List<dynamic>?) ?? [];
                    for (final mm in mediaList) {
                      if (mm is! Map<String, dynamic>) continue;
                      if (mm['localPath'] == rel) {
                        mm['serverFileId'] = fileId;
                      }
                    }
                  }
                }
              }
            } catch (e) {
              if (kDebugMode) print('processing upload result entry failed: $e');
            }
          }
        }
        await jf.writeAsString(jsonEncode(localJson));
      }

      final title = localJson['reportName']?.toString() ?? 'Report ${DateTime.now().toIso8601String()}';
      final res = await ApiService.saveReport(
        title: title,
        reportData: localJson,
        reportId: serverReportId,
        baseVersion: baseVersion,
        baseSnapshot: null,
      );

      if (res.success) {
        try {
          final newVersion = res.data?['newVersion'] ?? res.data?['version'] ?? res.data?['report']?['version'];
          if (newVersion != null) {
            final meta = {'serverVersion': newVersion};
            final mf = File('$folderPath${Platform.pathSeparator}sync_meta.json');
            await mf.writeAsString(jsonEncode(meta));
          }
        } catch (_) {}
        return true;
      }

      if (res.isPermanentAccessDenied) {
        // Право на редактирование истекло / доступ закрыт: отвязываем
        // локальную копию, чтобы она стала обычным локальным отчётом.
        lastDeniedUnlinkedFolder = await _detachFromServer(
          folderPath,
          isLibrary: absoluteFolderPath == null,
        );
        return false;
      }

      if (res.data != null && res.data is Map && res.data!['code'] == 'VERSION_CONFLICT') {
        if (kDebugMode) print('sync conflict: ${res.data}');
        return false;
      }

      if (kDebugMode) print('saveReport failed: $res.error');
      return false;
    } catch (e) {
      if (kDebugMode) print('syncReport error: $e');
      return false;
    }
  }

  /// Снять привязку локальной копии к серверу после истечения права.
  ///
  /// - Для папок библиотеки (reports/…) удаляет sync_meta.json и
  ///   переименовывает `server_<id>` → `report_<ts>_detached`, чтобы
  ///   привязка не восстанавливалась по имени папки.
  /// - Для скрытых рабочих копий (cloud_cache) удаляет метаданные и
  ///   переносит папку в библиотеку как `report_<ts>_detached` — иначе
  ///   локальные правки исчезли бы при очистке кэша.
  ///
  /// Возвращает прежнее имя папки, если отвязка выполнена, иначе null.
  Future<String?> _detachFromServer(String folderPath, {required bool isLibrary}) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return null;
      final meta = File('$folderPath${Platform.pathSeparator}sync_meta.json');
      if (await meta.exists()) {
        await meta.delete();
      }
      final name = dir.path.split(Platform.pathSeparator).last;
      final newName =
          'report_${DateTime.now().millisecondsSinceEpoch}_detached';
      if (isLibrary) {
        if (name.startsWith('server_')) {
          final newPath =
              '${dir.parent.path}${Platform.pathSeparator}$newName';
          await dir.rename(newPath);
          if (kDebugMode) print('Detached from server: $name -> $newName');
        }
      } else {
        // cloud_cache/server_<id>: сохраняем правки как локальный отчёт
        // в «Мои отчёты» (родительская папка библиотеки reports/).
        final reportsDir = await _getReportsDir();
        final newPath = '$reportsDir${Platform.pathSeparator}$newName';
        await dir.rename(newPath);
        if (kDebugMode) {
          print('Detached cloud session -> library: $name -> $newName');
        }
      }
      return name;
    } catch (e) {
      if (kDebugMode) print('detachFromServer error: $e');
      return null;
    }
  }
}