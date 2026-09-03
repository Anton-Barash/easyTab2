import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/report_summary.dart';
import '../services/api_service.dart';
import '../utils/diff_utils.dart';

/// ReportSyncManager: minimal, iterative implementation.
/// Provides methods to list combined reports, download a report from server
/// and perform a sync (partial) by computing a diff and sending to server.
class ReportSyncManager {
  ReportSyncManager();

  /// Read local reports directory and return list of local report ids (folder names)
  Future<List<String>> _listLocalReportFolders() async {
    try {
      final dir = await _getReportsDir();
      final d = Directory(dir);
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
    final appDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${appDir.path}${Platform.pathSeparator}reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir.path;
  }

  /// Combined list: merges local folders and server entries (if logged in).
  /// This implementation is conservative — it returns simple ReportSummary objects
  /// with best-effort status detection.
  Future<List<ReportSummary>> loadCombinedList() async {
    final localFolders = await _listLocalReportFolders();

    List<Map<String, dynamic>> serverList = [];
    if (ApiService.authToken != null && ApiService.authToken!.isNotEmpty) {
      final res = await ApiService.listReports();
      if (res.success && res.data != null) {
        // Expecting data['reports'] or data itself a list. Be defensive.
        final data = res.data;
        if (data is Map && data['reports'] is List) {
          serverList = (data['reports'] as List).cast<Map<String, dynamic>>();
        } else if (data is List) {
          serverList = (data as List).cast<Map<String, dynamic>>();
        }
      }
    }

    // Build map by server id -> server meta
    final serverById = <String, Map<String, dynamic>>{};
    for (final s in serverList) {
      final id = (s['id'] ?? s['reportId'] ?? s['publicId'])?.toString();
      if (id != null) serverById[id] = s;
    }

    final out = <ReportSummary>[];

    // First, entries that are on server
    for (final s in serverList) {
      final id = (s['id'] ?? s['reportId'])?.toString() ?? s['publicId']?.toString() ?? '';
      final title = (s['title'] ?? s['name'] ?? 'Untitled').toString();
      final modRaw = s['modifiedAt'] ?? s['updatedAt'] ?? s['modified'];
      DateTime modified = DateTime.now();
      if (modRaw != null) {
        try {
          modified = DateTime.parse(modRaw.toString()).toLocal();
        } catch (_) {}
      }
      // try detect local existence by folder named server_<id>
      final localFolderName = 'server_$id';
      final localExists = localFolders.contains(localFolderName);

      final status = localExists ? ReportSyncStatus.synced : ReportSyncStatus.cloudOnly;
      final version = s['version'] is int ? s['version'] as int : (s['ver'] is int ? s['ver'] as int : null);

      out.add(ReportSummary(
        id: id,
        title: title,
        modified: modified,
        localExists: localExists,
        onServer: true,
        serverVersion: version,
        status: status,
      ));

      // remove from localFolders set so we don't duplicate
      localFolders.remove(localFolderName);
    }

    // Then remaining local-only folders
    for (final f in localFolders) {
      // For local-only we try to read report.json to get title and modified
      final summary = await _readLocalReportSummary(f);
      out.add(summary);
    }

    return out;
  }

  Future<ReportSummary> _readLocalReportSummary(String folderName) async {
    final reportsDir = await _getReportsDir();
    final folder = Directory('${reportsDir}${Platform.pathSeparator}$folderName');
    String title = folderName;
    DateTime modified = DateTime.now();
    try {
      final jf = File('${folder.path}${Platform.pathSeparator}report.json');
      if (await jf.exists()) {
        final str = await jf.readAsString();
        final map = jsonDecode(str) as Map<String, dynamic>;
        title = map['reportName']?.toString() ?? map['name']?.toString() ?? title;
        final stat = await jf.lastModified();
        modified = stat;
      }
    } catch (e) {
      if (kDebugMode) print('readLocalReportSummary error: $e');
    }

    return ReportSummary(
      id: folderName,
      title: title,
      modified: modified,
      localExists: true,
      onServer: false,
      serverVersion: null,
      status: ReportSyncStatus.localOnly,
    );
  }

  /// Download a report from server into local reports folder.
  /// Returns local folder name on success, null on failure.
  Future<String?> downloadReportFromServer(int serverReportId) async {
    try {
      final res = await ApiService.getReport(serverReportId);
      if (!res.success || res.data == null) return null;
      // Expect data['report'] or data['reportData']
      Map<String, dynamic> reportData = {};
      if (res.data is Map && res.data.containsKey('report')) {
        final r = res.data!['report'];
        if (r is Map && r.containsKey('reportData')) {
          reportData = Map<String, dynamic>.from(r['reportData'] as Map);
        } else if (r is Map && r.containsKey('data')) {
          reportData = Map<String, dynamic>.from(r['data'] as Map);
        }
      } else if (res.data is Map && res.data.containsKey('reportData')) {
        reportData = Map<String, dynamic>.from(res.data!['reportData'] as Map);
      } else if (res.data is Map) {
        reportData = Map<String, dynamic>.from(res.data as Map);
      }

      final reportsDir = await _getReportsDir();
      final folderName = 'server_$serverReportId';
      final folderPath = '${reportsDir}${Platform.pathSeparator}$folderName';
      final folder = Directory(folderPath);
      if (!await folder.exists()) await folder.create(recursive: true);

      // write report.json
      final jf = File('$folderPath${Platform.pathSeparator}report.json');
      await jf.writeAsString(jsonEncode(reportData));

      // download files if server provided file urls
      try {
        final urlsRes = await ApiService.getReportFileUrls(serverReportId);
        if (urlsRes.success && urlsRes.data != null && urlsRes.data is Map) {
          final urls = Map<String, dynamic>.from(urlsRes.data!['urls'] ?? urlsRes.data!);
          // Each key is relPath, value is url
          for (final entry in urls.entries) {
            final rel = entry.key.toString();
            final url = entry.value?.toString();
            if (url == null || url.isEmpty) continue;
            try {
              final uri = Uri.parse(url);
              final resp = await http.get(uri);
              if (resp.statusCode == 200) {
                // ensure directory exists
                final target = File('$folderPath${Platform.pathSeparator}$rel');
                final parent = target.parent;
                if (!await parent.exists()) await parent.create(recursive: true);
                await target.writeAsBytes(resp.bodyBytes);
              } else {
                if (kDebugMode) print('download file $url failed status ${resp.statusCode}');
              }
            } catch (e) {
              if (kDebugMode) print('download file $url failed: $e');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('getReportFileUrls error: $e');
      }

      return folderName;
    } catch (e) {
      if (kDebugMode) print('downloadReportFromServer error: $e');
      return null;
    }
  }

  /// Sync local report to server: compute diff and send PATCH via ApiService.saveReport.
  /// Uploads new local media (multipart native flow) and then sends updated report JSON.
  /// Returns true on success, false on failure or conflict.
  Future<bool> syncReport({required String localFolderName, int? serverReportId, int? baseVersion}) async {
    // Read local report
    try {
      final reportsDir = await _getReportsDir();
      final folderPath = '${reportsDir}${Platform.pathSeparator}$localFolderName';
      final jf = File('$folderPath${Platform.pathSeparator}report.json');
      if (!await jf.exists()) return false;
      final localJson = jsonDecode(await jf.readAsString()) as Map<String, dynamic>;

      // 1) Collect local media files that lack serverFileId
      final filesToUpload = <Map<String, String>>[]; // {filePath, relativePath}
      final markers = localJson['markers'] as Map<String, dynamic>?;
      if (markers != null) {
        for (final qEntry in markers.entries) {
          final qList = qEntry.value as List<dynamic>?;
          if (qList == null) continue;
          for (var i = 0; i < qList.length; i++) {
            final marker = qList[i] as Map<String, dynamic>;
            final mediaList = (marker['media'] as List<dynamic>?) ?? [];
            for (var m in mediaList) {
              final mm = m as Map<String, dynamic>;
              final localPath = mm['localPath'] as String?;
              final serverFileId = mm['serverFileId'] as String?;
              if (localPath != null && (serverFileId == null || serverFileId.isEmpty)) {
                final abs = '$folderPath${Platform.pathSeparator}$localPath';
                filesToUpload.add({'filePath': abs, 'relativePath': localPath});
              }
            }
          }
        }
      }

      // 2) Upload files via ApiService.uploadFiles (native multipart flow)
      if (filesToUpload.isNotEmpty) {
        final uploadRes = await ApiService.uploadFiles(files: filesToUpload, reportId: serverReportId);
        if (!uploadRes.success) {
          if (kDebugMode) print('uploadFiles failed: ${uploadRes.error}');
          // continue? return false to indicate failure
          return false;
        }

        final results = uploadRes.data?['results'] as List<dynamic>?;
        if (results != null) {
          for (final r in results) {
            try {
              final rel = r['relativePath'] as String?;
              final fileObj = r['file'];
              String? fileId;
              if (fileObj is Map) {
                if (fileObj['id'] != null) fileId = fileObj['id'].toString();
                else if (fileObj['file'] is Map && fileObj['file']['id'] != null) fileId = fileObj['file']['id'].toString();
                else if (fileObj['fileId'] != null) fileId = fileObj['fileId'].toString();
              }
              if (rel != null && fileId != null) {
                // find media entries with this relativePath and set serverFileId
                for (final qEntry in markers.entries) {
                  final qList = qEntry.value as List<dynamic>?;
                  if (qList == null) continue;
                  for (var i = 0; i < qList.length; i++) {
                    final marker = qList[i] as Map<String, dynamic>;
                    final mediaList = (marker['media'] as List<dynamic>?) ?? [];
                    for (var miIdx = 0; miIdx < mediaList.length; miIdx++) {
                      final mm = mediaList[miIdx] as Map<String, dynamic>;
                      final lp = mm['localPath'] as String?;
                      if (lp != null && lp == rel) {
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

        // persist updated report.json (with serverFileId fields)
        await jf.writeAsString(jsonEncode(localJson));
      }

      // 3) Send updated report JSON to server (create or update)
      final title = localJson['reportName']?.toString() ?? 'Report ${DateTime.now().toIso8601String()}';
      final res = await ApiService.saveReport(
        title: title,
        reportData: localJson,
        reportId: serverReportId,
        baseVersion: baseVersion,
        baseSnapshot: null,
      );

      if (res.success) {
        // Success: optionally update local metadata (e.g., write serverVersion if returned)
        try {
          final newVersion = res.data?['newVersion'] ?? res.data?['version'] ?? res.data?['report']?['version'];
          if (newVersion != null) {
            // store as meta file
            final meta = {'serverVersion': newVersion};
            final mf = File('$folderPath${Platform.pathSeparator}sync_meta.json');
            await mf.writeAsString(jsonEncode(meta));
          }
        } catch (_) {}
        return true;
      }

      if (res.data != null && res.data!['code'] == 'VERSION_CONFLICT') {
        // Conflict: caller should present resolution UI
        if (kDebugMode) print('sync conflict: ${res.data}');
        return false;
      }

      if (kDebugMode) print('saveReport failed: ${res.error}');
      return false;
    } catch (e) {
      if (kDebugMode) print('syncReport error: $e');
      return false;
    }
  }
}
