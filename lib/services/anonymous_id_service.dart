import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для генерации и хранения anonymous_id.
///
/// Используется в share-ссылках: если пользователь не авторизован,
/// frontend генерирует стабильный UUID и сохраняет его в SharedPreferences.
/// Этот id передаётся на сервер для логов доступа.
class AnonymousIdService {
  static const _key = 'anonymous_id';

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Формат UUID v4.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final parts = [
      bytes
          .sublist(0, 4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(4, 6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(6, 8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(8, 10)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(10, 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    ];
    return parts.join('-');
  }

  /// Получить существующий anonymous_id или создать новый.
  static Future<String> getId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = _generate();
      await prefs.setString(_key, id);
    }
    return id;
  }

  /// Сбросить anonymous_id (например, при выходе из аккаунта).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
