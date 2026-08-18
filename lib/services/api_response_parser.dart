// ============================================================
// Парсер ответа API — единая логика разбора JSON-ответа сервера.
//
// Используется api_service.dart и обоими upload_helper'ами
// (web/native), чтобы убрать дублирование трёх копий
// _parseResponse / _parseResponseString.
// ============================================================

import 'dart:convert';

import '../l10n/app_localizations.dart';
import 'api_result.dart';

/// Разобрать JSON-ответ сервера по тексту тела и HTTP-статусу.
///
/// Контракт ответа сервера:
///   { "success": bool, "error"?: string, "token"?: string,
///     "user"?: object, ...прочие поля }
///
/// На 2xx: success определяется полем `success` (не статусом),
/// т.к. сервер может вернуть 200 с success=false при логической ошибке.
/// На прочие статусы: всегда успех = false.
ApiResult parseApiResponse(
  String responseBody,
  int statusCode, {
  AppLocalizations? loc,
}) {
  try {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResult(
        success: body['success'] == true,
        data: body,
        token: body['token'] as String?,
        user: body['user'] as Map<String, dynamic>?,
        error: body['success'] == true
            ? null
            : (body['error'] as String?) ??
                loc?.unknownError ??
                'Неизвестная ошибка',
        statusCode: statusCode,
      );
    }

    return ApiResult(
      success: false,
      error: (body['error'] as String?) ??
          loc?.statusError(statusCode) ??
          'Ошибка $statusCode',
      statusCode: statusCode,
    );
  } catch (_) {
    return ApiResult(
      success: false,
      error:
          loc?.invalidServerResponse(statusCode) ??
          'Некорректный ответ сервера: $statusCode',
      statusCode: statusCode,
    );
  }
}
