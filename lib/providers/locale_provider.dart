import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('ru');
  static const String _storageKey = 'selectedLocale';

  Locale get locale => _locale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedLocale = prefs.getString(_storageKey);
    if (storedLocale != null) {
      _locale = Locale(storedLocale);
      notifyListeners();
    }
  }

  void setLocale(Locale locale) {
    _locale = locale;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_storageKey, locale.languageCode);
    });
    notifyListeners();
  }
}
