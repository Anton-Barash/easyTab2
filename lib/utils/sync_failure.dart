library;

import '../l10n/app_localizations.dart';
import '../services/api_result.dart';

/// Разбор типичных причин, почему синхронизация отчёта не удалась, и
/// составление понятного сообщения с подсказкой, что делать дальше.
///
/// Сервер отвечает HTTP-статусом и текстом ошибки (см. reportsService.js).
/// По статусу / маркерам текста различаем: отчёт удалён, нет доступа,
/// конфликт, истёкшее право, ошибка сервера, нет соединения.
String syncFailureMessage(ApiResult? res, AppLocalizations loc, {bool detached = false}) {
  final kind = syncFailureKind(res);

  switch (kind) {
    case SyncFailureKind.notFound:
      return loc.syncErrorNotFound;
    case SyncFailureKind.noAccess:
      return loc.syncErrorNoAccess;
    case SyncFailureKind.conflict:
      return loc.syncErrorConflict;
    case SyncFailureKind.permissionExpired:
      return loc.syncErrorPermissionExpired;
    case SyncFailureKind.serverError:
      return loc.syncErrorServer;
    case SyncFailureKind.network:
      return loc.syncErrorNetwork;
    case SyncFailureKind.generic:
      // Явный ответ есть, но не разобран. Если по флагу отвязки известно,
      // что это был истечённый доступ, — сообщаем об этом.
      if (detached) return loc.syncErrorPermissionExpired;
      final raw = res?.error ?? res?.data?.toString();
      return (raw == null || raw.isEmpty) ? loc.syncErrorMessage : '${loc.syncErrorMessage}: $raw';
  }
}

/// Классифицирует ответ сервера в константу причины.
SyncFailureKind syncFailureKind(ApiResult? res) {
  final sc = res?.statusCode;
  if (res == null) return SyncFailureKind.network;

  if (sc == 409) return SyncFailureKind.conflict;
  if (sc == 404) return SyncFailureKind.notFound;
  if (sc == 403) return SyncFailureKind.noAccess;

  // 410/прочее, что уже признано «постоянным отказом» (например истёкшая
  // ссылка). Должно идти после явных 404/403.
  if (res.isPermanentAccessDenied) return SyncFailureKind.permissionExpired;

  if (sc == null) return SyncFailureKind.network;
  if (sc >= 500) return SyncFailureKind.serverError;

  // Резерв: разбор маркеров текста для случаев без чёткого статуса.
  final text = '${res.data?.toString() ?? ''} ${res.error ?? ''}'.toLowerCase();
  if (text.contains('report not found') ||
      text.contains('not_found') ||
      text.contains('report_not_found')) {
    return SyncFailureKind.notFound;
  }
  if (text.contains('version_conflict') || text.contains('conflict')) {
    return SyncFailureKind.conflict;
  }
  if (text.contains('not the author') ||
      text.contains('permission') ||
      text.contains('access denied')) {
    return SyncFailureKind.noAccess;
  }
  if (text.contains('expired') || text.contains('gone')) {
    return SyncFailureKind.permissionExpired;
  }
  return SyncFailureKind.generic;
}

/// Причина неудачной синхронизации.
enum SyncFailureKind {
  /// Отчёт удалён на сервере / недоступен.
  notFound,

  /// Нет прав доступа (не владелец / запрещено).
  noAccess,

  /// Отчёт изменён другим редактором (VERSION_CONFLICT).
  conflict,

  /// Право доступа истекло / ссылка просрочена.
  permissionExpired,

  /// Внутренняя ошибка сервера (5xx).
  serverError,

  /// Нет ответа от сервера (сетевая проблема).
  network,

  /// Неразобранная ошибка.
  generic,
}