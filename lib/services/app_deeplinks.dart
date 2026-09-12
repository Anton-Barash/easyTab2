import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Слушает deep-link'и (Android App Links / iOS Universal Links) и направляет
/// пользователя на маршрут `/welcome?token=...` (существующий обработчик
/// welcome-экрана расшаренного отчёта).
///
/// Поддерживает два сценария:
/// - тёплый старт: приложение уже запущено, ссылку открыли в браузере;
/// - холодный старт: приложение свёрнуто/убито и открывается по ссылке.
class AppDeeplinks {
  AppDeeplinks._();

  static final AppDeeplinks instance = AppDeeplinks._();

  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Инициализирует сервис. Вызывается из [main] до `runApp`, чтобы захватить
  /// холодный старт. На web deep-link не нужен — там роутинг работает через
  /// hash-часть URL, и ссылка открывается естественным образом.
  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (kIsWeb) return;
    _navigatorKey = navigatorKey;

    // Холодный старт: приложение запущено именно по deep-link'у.
    final initial = await _links.getInitialLink();
    if (initial != null) _handle(initial);

    // Тёплый старт: приложение уже открыто, приходит новый URI.
    _sub = _links.uriLinkStream.listen(_handle);
  }

  void _handle(Uri uri) {
    final token = _extractToken(uri);
    if (token == null || token.isEmpty) return;
    // onGenerateRoute в main.dart парсит имя маршрута как URI, поэтому
    // строка с query-параметром корректно открывает /welcome.
    // ignore: unawaited_futures
    _navigatorKey?.currentState?.pushNamed('/welcome?token=$token');
  }

  /// Извлекает share-токен из URL вида
  /// `https://easytab.cloud/#/welcome?token=XXX`.
  String? _extractToken(Uri uri) {
    final rawFragment = uri.fragment;
    if (rawFragment.isNotEmpty) {
      // Фрагмент обычно выглядит как `/welcome?token=...` (hash-роутинг SPA).
      final fragmentUri = Uri.tryParse(rawFragment);
      final token = fragmentUri?.queryParameters['token'] ??
          (rawFragment.startsWith('/')
              ? null
              : Uri.tryParse('?$rawFragment')?.queryParameters['token']);
      if (token != null && token.isNotEmpty) return token;
    }
    return uri.queryParameters['token'];
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}