import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для хранения share-токенов в SharedPreferences.
///
/// Когда пользователь открывает share-ссылку, токен сохраняется.
/// Это позволяет показывать расшаренные отчёты в списке отчётов
/// даже для анонимных пользователей.
class ShareTokenStorage {
  static const _key = 'share_tokens';

  /// Сохранить share-токен.
  static Future<void> addToken(String token) async {
    if (token.isEmpty) return;
    final tokens = await getTokens();
    if (!tokens.contains(token)) {
      tokens.add(token);
      await _save(tokens);
    }
  }

  /// Получить все сохранённые share-токены.
  static Future<List<String>> getTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// Удалить share-токен.
  static Future<void> removeToken(String token) async {
    final tokens = await getTokens();
    tokens.remove(token);
    await _save(tokens);
  }

  static Future<void> _save(List<String> tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(tokens));
  }
}
