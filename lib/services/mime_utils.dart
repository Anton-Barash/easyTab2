// ============================================================
// MIME-утилиты — определение типа файла по расширению.
//
// Единый источник правды для Dart-клиента (web + native).
// Синхронизирован с серверной таблицей
// easy_tab_Server/src/utils/fileUtils.js (MIME_TYPES), чтобы
// клиент и сервер согласованно определяли типы.
// ============================================================

/// Карта расширений → MIME-типов.
/// Включает основные типы, нужные приложению.
const Map<String, String> _mimeTypes = {
  // Текстовые и веб
  '.html': 'text/html',
  '.htm': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.txt': 'text/plain',
  '.xml': 'application/xml',
  '.csv': 'text/csv',

  // Изображения
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.bmp': 'image/bmp',

  // Видео
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.mov': 'video/quicktime',
  '.avi': 'video/x-msvideo',
  '.mkv': 'video/x-matroska',

  // Аудио
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',

  // Документы
  '.pdf': 'application/pdf',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.xls': 'application/vnd.ms-excel',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.doc': 'application/msword',

  // Архивы
  '.zip': 'application/zip',
};

/// MIME-тип по умолчанию для неизвестных расширений.
const String defaultMimeType = 'application/octet-stream';

/// Определяет MIME-тип по расширению файла.
///
/// Возвращает [defaultMimeType], если расширение неизвестно
/// или файл без расширения. Синхронизирована с серверной
/// `getMimeType()` из `fileUtils.js`.
String mimeTypeFromFilename(String filename) {
  if (filename.isEmpty) return defaultMimeType;

  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) {
    return defaultMimeType;
  }

  final ext = filename.substring(dotIndex).toLowerCase();
  return _mimeTypes[ext] ?? defaultMimeType;
}
