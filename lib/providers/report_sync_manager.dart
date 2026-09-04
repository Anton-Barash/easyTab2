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

  Future<List<ReportSummary>> loadCombinedList() async {
    final localFolders = await _listLocalReportFolders();

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
      final modRaw = s['modifiedAt'] ?? s['updatedAt'] ?? s['modified'];
      DateTime modified = DateTime.now();
      if (modRaw != null) {
        try {
          modified = DateTime.parse(modRaw.toString()).toLocal();
        } catch (_) {}
      }
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

      localFolders.remove(localFolderName);
    }

    for (final f in localFolders) {
      final summary = await _readLocalReportSummary(f);
      out.add(summary);
    }

    return out;
  }

  Future<ReportSummary> _readLocalReportSummary(String folderName) async {
    final reportsDir = await _getReportsDir();
    final folder = Directory('$reportsDir${Platform.pathSeparator}$folderName');
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

  Future<String?> downloadReportFromServer(int serverReportId) async {
    try {
      final res = await ApiService.getReport(serverReportId);
      if (!res.success || res.data == null) return null;

      final responseData = res.data!;

      Map<String, dynamic> reportData = {};
      if (responseData is Map) {
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
          reportData = Map<String, dynamic>.from(responseData);
        }
      }

      final reportsDir = await _getReportsDir();
      final folderName = 'server_$serverReportId';
      final folderPath = '$reportsDir${Platform.pathSeparator}$folderName';
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

  Future<bool> syncReport({required String localFolderName, int? serverReportId, int? baseVersion}) async {
    try {
      final reportsDir = await _getReportsDir();
      final folderPath = '$reportsDir${Platform.pathSeparator}$localFolderName';
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
          if (kDebugMode) print('uploadFiles failed: $uploadRes.error');
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
}