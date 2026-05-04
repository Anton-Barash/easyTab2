import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  String _templatesFolder = '';
  String _reportsFolder = '';
  String _mediaFolder = '';
  String _platform = 'unknown';

  String get templatesFolder => _templatesFolder;
  String get reportsFolder => _reportsFolder;
  String get mediaFolder => _mediaFolder;
  String get platform => _platform;

  SettingsState() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _templatesFolder = prefs.getString('templatesFolder') ?? '';
    _reportsFolder = prefs.getString('reportsFolder') ?? '';
    _mediaFolder = prefs.getString('mediaFolder') ?? '';
    _platform = _detectPlatform();
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
    notifyListeners();
  }

  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _templatesFolder = '';
    _reportsFolder = '';
    _mediaFolder = '';
    notifyListeners();
  }
}
