import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// ============================================================
// ProjectZipService — импорт/экспорт проектов в ZIP-архивах.
//
// Выделено в отдельный модуль для deferred loading:
// пакет archive тяжёлый и не нужен в основном бандле до
// первого импорта/экспорта проекта пользователем.
// ============================================================

/// Распаковать ZIP-архив [zipPath] в папку [targetPath].
///
/// БЕЗОПАСНОСТЬ (H-23): защита от path traversal — файлы, чей
/// итоговый путь выходит за пределы [targetPath], пропускаются.
///
/// Если папка [targetPath] существует — она предварительно очищается.
/// Возвращает true при успешной распаковке.
Future<bool> extractProjectZip(String zipPath, String targetPath) async {
  final zipFile = File(zipPath);
  if (!await zipFile.exists()) {
    if (kDebugMode) debugPrint('ZIP file not found: $zipPath');
    return false;
  }

  if (await Directory(targetPath).exists()) {
    await Directory(targetPath).delete(recursive: true);
  }
  await Directory(targetPath).create(recursive: true);

  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  final canonicalTarget = path.canonicalize(targetPath);

  for (final file in archive) {
    if (!file.isFile) continue;

    // Склеиваем через path.join (обрабатывает разные разделители),
    // затем нормализуем и проверяем, что путь остался внутри targetPath.
    final joined = path.join(canonicalTarget, file.name);
    final canonical = path.canonicalize(joined);
    if (!path.isWithin(canonicalTarget, canonical)) {
      if (kDebugMode) {
        debugPrint('ZIP path traversal blocked: ${file.name}');
      }
      continue;
    }

    final fileDir = Directory(path.dirname(canonical));
    if (!await fileDir.exists()) {
      await fileDir.create(recursive: true);
    }
    await File(canonical).writeAsBytes(file.content);
  }

  return true;
}

/// Проверить, что относительный путь безопасен для добавления в ZIP
/// (P2-39): без `..`, ведущих слэшей и NUL-байтов.
bool isSafeZipPath(String relativePath) {
  return !relativePath.contains('..') &&
      !relativePath.startsWith('/') &&
      !relativePath.startsWith('\\') &&
      !relativePath.contains('\x00');
}

/// Создать ZIP-архив [zipPath] из файлов папки [folderPath].
///
/// [relativePaths] — относительные пути файлов внутри [folderPath].
/// Небезопасные пути отбрасываются (P2-39). Несуществующие файлы
/// пропускаются с логом в debug-режиме.
Future<void> createProjectZip(
  String zipPath,
  String folderPath,
  Set<String> relativePaths,
) async {
  final zipDir = Directory(path.dirname(zipPath));
  if (!await zipDir.exists()) {
    await zipDir.create(recursive: true);
  }

  final zipFile = File(zipPath);
  if (await zipFile.exists()) {
    await zipFile.delete();
  }

  final encoder = ZipFileEncoder();
  encoder.create(zipFile.path);

  for (final relativePath in relativePaths) {
    if (!isSafeZipPath(relativePath)) {
      if (kDebugMode) {
        debugPrint('ZIP export: skipping unsafe path: $relativePath');
      }
      continue;
    }

    final filePath = '$folderPath/$relativePath';
    final file = File(filePath);
    if (await file.exists()) {
      if (kDebugMode) debugPrint('Adding file to zip: $filePath');
      await encoder.addFile(file, relativePath);
      // Даём event loop передышку, чтобы UI не фризился на больших архивах.
      await Future.delayed(const Duration(milliseconds: 20));
    } else {
      if (kDebugMode) debugPrint('File not found: $filePath');
    }
  }

  await Future.delayed(const Duration(milliseconds: 200));
  encoder.close();
}
