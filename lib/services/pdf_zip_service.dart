import 'dart:typed_data';

import 'package:archive/archive.dart';

// ============================================================
// PdfZipService — упаковка PDF-файлов в ZIP целиком в памяти.
//
// Отдельно от project_zip_service: тот работает с файловой системой
// (dart:io) и недоступен на web. Здесь используется только
// in-memory кодировщик archive — он безопасен на всех платформах,
// включая web.
// ============================================================

/// Собрать ZIP-архив из готовых файлов [files] (имя → байты).
///
/// Возвращает байты архива. Имена — плоские (без вложенных папок),
/// пользовательские имена уже санитизированы вызывающим кодом.
Uint8List buildZipFromBytes(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}
