import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  String _templatesFolder = '';
  String _reportsFolder = '';
  String _mediaFolder = '';
  String _platform = 'unknown';
  bool _starsBackground = false;

  String get templatesFolder => _templatesFolder;
  String get reportsFolder => _reportsFolder;
  String get mediaFolder => _mediaFolder;
  String get platform => _platform;

  /// Фон со звёздами вместо точечного узора.
  bool get starsBackground => _starsBackground;

  SettingsState() {
    // P1-55: _loadSettings() теперь вызывается через init(),
    // а не fire-and-forget в конструкторе.
    // Это гарантирует, что загрузка завершится до runApp().
  }

  /// Инициализация настроек. Вызывается в main() до runApp().
  Future<void> init() async {
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _templatesFolder = prefs.getString('templatesFolder') ?? '';
    _reportsFolder = prefs.getString('reportsFolder') ?? '';
    _mediaFolder = prefs.getString('mediaFolder') ?? '';
    _platform = _detectPlatform();
    _starsBackground = prefs.getBool('starsBackground') ?? false;
    notifyListeners();
  }

  String _detectPlatform() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'Android';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'iOS';
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'Windows';
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      return 'macOS';
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      return 'Linux';
    }
    return 'Unknown';
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('templatesFolder', _templatesFolder);
    await prefs.setString('reportsFolder', _reportsFolder);
    await prefs.setString('mediaFolder', _mediaFolder);
    await prefs.setBool('starsBackground', _starsBackground);
    notifyListeners();
  }

  /// Включает/выключает звёздный фон и сохраняет выбор.
  Future<void> setStarsBackground(bool value) async {
    _starsBackground = value;
    notifyListeners();
    await saveSettings();
  }

  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // TODO-35: НЕ используем prefs.clear() — он удаляет ВСЕ ключи,
    // включая auth-токен (user_token) и другие данные AuthProvider'а.
    // Удаляем только собственные ключи настроек.
    await prefs.remove('templatesFolder');
    await prefs.remove('reportsFolder');
    await prefs.remove('mediaFolder');
    await prefs.remove('starsBackground');
    _templatesFolder = '';
    _reportsFolder = '';
    _mediaFolder = '';
    _starsBackground = false;
    notifyListeners();
  }
}
