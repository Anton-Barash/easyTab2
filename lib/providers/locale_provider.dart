import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('ru');
  static const String _storageKey = 'selectedLocale';
  static const List<String> _supportedCodes = ['en', 'ru', 'zh'];

  Locale get locale => _locale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    String? code;

    if (kIsWeb) {
      try {
        final qp = Uri.base.queryParameters['lang'];
        if (qp != null && _supportedCodes.contains(qp.toLowerCase())) {
          code = qp.toLowerCase();
        }
      } catch (_) {}
    }

    code ??= prefs.getString(_storageKey);
    if (code != null && _supportedCodes.contains(code)) {
      _locale = Locale(code);
      notifyListeners();
    }
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
