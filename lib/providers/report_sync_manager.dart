import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/report_summary.dart';
import '../services/api_result.dart';
import '../services/api_service.dart';
import '../services/share_token_storage.dart';
import '../services/anonymous_id_service.dart';

/// ReportSyncManager: minimal, iterative implementation.
class ReportSyncManager {
  ReportSyncManager();

  /// Если последняя синхронизация закончилась постоянным отказом (403/истёк
  /// срок права), содержит имя локальной папки, которую мы отвязали от
  /// сервера. Иначе null.
  String? lastDeniedUnlinkedFolder;

  /// Причина последней неудачной синхронизации/скачивания (ответ сервера).
  /// Используется, чтобы показать пользователю конкретную причину ошибки и
  /// подсказку, что делать. null — ошибки не было либо она не сетевого рода.
  ApiResult? lastSyncError;

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

    // Карта «локальная папка -> serverReportId» из sync_meta.json.
    // Локальная копия после заливки может хранить привязку к серверу
    // не по имени папки (server_<id>), а по id внутри sync_meta.json
    // (например, папка создана на телефоне как report_<ts>, потом залита).
    // Без этого в списке оставались бы и локальная, и облачная записи
    // с одинаковым названием (дубликат).
    final localServerIdByFolder = <String, String>{};
    if (!kIsWeb) {
      for (final f in localFolders) {
        final metaPath = '$reportsDirPath${Platform.pathSeparator}$f${Platform.pathSeparator}sync_meta.json';
        try {
          final mf = File(metaPath);
          if (await mf.exists()) {
            final meta = jsonDecode(await mf.readAsString());
            if (meta is Map) {
              final sid = meta['serverReportId'] ?? meta['serverId'] ?? meta['id'];
              if (sid != null) localServerIdByFolder[f] = sid.toString();
            }
          }
        } catch (e) {
          if (kDebugMode) print('readLocalSyncMeta error ($f): $e');
        }
      }
    }
    // Обратная карта: serverReportId -> локальная папка (если их несколько —
    // берём первую, остальные обработаются как локальные внизу).
    final localFolderByServerId = <String, String>{};
    localServerIdByFolder.forEach((folder, sid) {
      localFolderByServerId.putIfAbsent(sid, () => folder);
    });

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

      // Ищем локальную копию: сначала по классической папке server_<id>,
      // затем по привязке в sync_meta.json (serverReportId == id).
      final byName = 'server_$id';
      final linkedFolder = localFolderByServerId[id];
      String? matchedFolder;
      if (localFolders.contains(byName)) {
        matchedFolder = byName;
      } else if (linkedFolder != null && localFolders.contains(linkedFolder)) {
        matchedFolder = linkedFolder;
      }
      final localExists = matchedFolder != null;

      final status = localExists ? ReportSyncStatus.synced : ReportSyncStatus.cloudOnly;
      final version = s['version'] is int ? s['version'] as int : (s['ver'] is int ? s['ver'] as int : null);
      final author = (s['author'] ?? s['authorName'])?.toString();
      final publicId = (s['publicId'] ?? s['public_id'])?.toString();

      out.add(ReportSummary(
        id: id,
        title: title,
        createdAt: createdAt,
        modified: modified,
        localExists: localExists,
        onServer: true,
        serverVersion: version,
        status: status,
        publicId: publicId,
        authorName: author,
        localFolderPath: localExists
            ? '$reportsDirPath${Platform.pathSeparator}$matchedFolder'
            : null,
        thumbnailPath: localExists
            ? await _readLocalThumbnail(
                '$reportsDirPath${Platform.pathSeparator}$matchedFolder',
              )
            : null,
      ));

      if (matchedFolder != null) localFolders.remove(matchedFolder);
    }

    for (final f in localFolders) {
      final summary = await _readLocalReportSummary(
        f,
        '$reportsDirPath${Platform.pathSeparator}$f',
      );
      out.add(summary);
    }

    // Расшаренные отчёты (по сохранённым share-токенам). В список попадают
    // только те, где share.permissions == 'edit' — как и при сканировании QR
    // (view-only отчёты читают через welcome-экран, отдельной строкой не идут).
    final shareTokens = await ShareTokenStorage.getTokens();
    for (final token in shareTokens) {
      try {
        final anonymousId = await AnonymousIdService.getId();
        final shareResult = await ApiService.getShareInfo(
          token: token,
          anonymousId: anonymousId,
        );
        if (shareResult.success && shareResult.data != null) {
          final data = shareResult.data!;
          final share = data['share'] ?? {};
          final permissions = share['permissions']?.toString() ?? 'edit';
          if (permissions != 'edit') continue;
          final report = data['report'] ?? {};
          final reportData = report['reportData'] ?? {};
          final idRaw = report['id'] ?? report['publicId'];
          final idStr = idRaw?.toString() ?? '';
          if (idStr.isEmpty) continue;
          // Не дублируем отчёт, который уже есть в списке (локальный/облачный).
          if (out.any((r) => r.id == idStr)) continue;
          final title =
              (reportData['reportName'] ?? report['title'] ?? 'Shared')
                  .toString();
          DateTime createdAt = DateTime.now();
          final createdRaw = report['createdAt'];
          if (createdRaw != null) {
            final parsed = DateTime.tryParse(createdRaw.toString());
            if (parsed != null) createdAt = parsed.toLocal();
          }
          final publicId = (report['publicId'])?.toString();
          out.add(ReportSummary(
            id: idStr,
            title: title,
            createdAt: createdAt,
            modified: createdAt,
            localExists: false,
            onServer: true,
            status: ReportSyncStatus.cloudOnly,
            publicId: publicId,
          ));
        } else if (shareResult.statusCode == 404 ||
            shareResult.statusCode == 410) {
          // Токен протух/отозван — убираем, чтобы не копить мусор.
          await ShareTokenStorage.removeToken(token);
        }
      } catch (e) {
        if (kDebugMode) print('loadCombinedList share $token error: $e');
      }
    }

    // Сортируем по дате последнего изменения (сначала новые).
    out.sort((a, b) => b.modified.compareTo(a.modified));

    return out;
  }

  /// Читает header-изображение (обложку) из report.json локальной папки.
  /// Возвращает абсолютный путь, или null если обложки нет.
  Future<String?> _readLocalThumbnail(String folderPath) async {
    if (kIsWeb) return null;
    try {
      final jf = File('$folderPath${Platform.pathSeparator}report.json');
      if (await jf.exists()) {
        final map = jsonDecode(await jf.readAsString());
        if (map is Map) {
          final header = map['headerImagePath'];
          if (header is String && header.isNotEmpty) {
            return '$folderPath${Platform.pathSeparator}$header';
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('readLocalThumbnail error ($folderPath): $e');
    }
    return null;
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
      thumbnailPath: await _readLocalThumbnail(folderPath),
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
    lastSyncError = null;
    final res = await ApiService.getReport(serverReportId);
    if (!res.success || res.data == null) {
      lastSyncError = res;
      return '';
    }

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
    lastSyncError = null;
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
          lastSyncError = uploadRes;
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
          // При создании нового отчёта (serverReportId == null) сервер
          // возвращает новый id — запоминаем его в sync_meta, чтобы локальную
          // папку можно было связать с облачной по id (а не по имени server_<id>).
          final newId = res.data?['id'] ??
              res.data?['report']?['id'] ??
              serverReportId;
          final newVersion = res.data?['newVersion'] ?? res.data?['version'] ?? res.data?['report']?['version'];
          if (newId != null || newVersion != null) {
            final meta = <String, dynamic>{};
            if (newId != null) {
              meta['serverReportId'] = newId is int ? newId : int.tryParse(newId.toString());
            }
            if (newVersion != null) {
              meta['serverVersion'] = newVersion is int ? newVersion : int.tryParse(newVersion.toString());
            }
            final mf = File('$folderPath${Platform.pathSeparator}sync_meta.json');
            await mf.writeAsString(jsonEncode(meta));
          }
        } catch (_) {}
        return true;
      }

      if (res.isPermanentAccessDenied) {
        // Право на редактирование истекло / доступ закрыт: отвязываем
        // локальную копию, чтобы она стала обычным локальным отчётом.
        lastSyncError = res;
        lastDeniedUnlinkedFolder = await _detachFromServer(
          folderPath,
          isLibrary: absoluteFolderPath == null,
        );
        return false;
      }

      if (res.data != null && res.data is Map && res.data!['code'] == 'VERSION_CONFLICT') {
        if (kDebugMode) print('sync conflict: ${res.data}');
        lastSyncError = res;
        return false;
      }

      lastSyncError = res;
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
  /// Публичный метод «Отменить связь» для отчёта в списке.
  ///
  /// Разрывает привязку локальной копии [folderPath] к серверу: удаляет
  /// sync_meta.json и переименовывает папку в `report_<ts>_detached`, чтобы
  /// она стала обычным локальным отчётом в «Моих отчётах». Далее повторная
  /// заливка на сервер создаст новый отчёт (новый id) — синхронизация с
  /// прежним облачным отчётом теряется.
  ///
  /// Возвращает `true`, если отвязка выполнена.
  Future<bool> detachReportFromServer(String folderPath) async {
    final res = await _detachFromServer(folderPath, isLibrary: true);
    return res != null;
  }

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