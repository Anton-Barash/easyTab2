import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('ru');
  static const String _storageKey = 'selectedLocale';
  static const List<String> _supportedCodes = ['en', 'ru', 'zh'];

  Locale get locale => _locale;

  Future<void> init() async {
    final code = await resolveCurrentLocaleCode();
    if (code != null) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  /// Определяет сохранённый язык приложения (для переиспользования там, где
  /// нет доступа к BuildContext — например, при фоновой генерации PDF).
  ///
  /// Приоритет как в [init]: на web параметр `?lang=` в URL, иначе —
  /// сохранённое значение из SharedPreferences. `null`, если ничего не найдено.
  static Future<String?> resolveCurrentLocaleCode() async {
    if (kIsWeb) {
      try {
        final qp = Uri.base.queryParameters['lang'];
        if (qp != null && _supportedCodes.contains(qp.toLowerCase())) {
          return qp.toLowerCase();
        }
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_storageKey);
      if (code != null && _supportedCodes.contains(code)) return code;
    } catch (_) {}

    return null;
  }

  void setLocale(Locale locale) {
    final lc = locale.languageCode;
    if (!_supportedCodes.contains(lc)) return;
    _locale = Locale(lc);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_storageKey, lc);
    });
    notifyListeners();
  }
}
