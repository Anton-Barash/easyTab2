import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/media_quality.dart';

class SettingsState extends ChangeNotifier {
  String _templatesFolder = '';
  String _reportsFolder = '';
  String _mediaFolder = '';
  String _platform = 'unknown';
  bool _starsBackground = false;
  MediaQualityLevel _imageQualityLevel = MediaQualityLevel.medium;
  int _videoQualityLevel = MediaQuality.defaultVideoLevel;

  String get templatesFolder => _templatesFolder;
  String get reportsFolder => _reportsFolder;
  String get mediaFolder => _mediaFolder;
  String get platform => _platform;

  /// Фон со звёздами вместо точечного узора.
  bool get starsBackground => _starsBackground;

  /// Уровень качества фото: high / medium (default) / low.
  /// Влияет на max px по стороне и JPEG-quality при сжатии изображений
  /// (см. utils/media_quality.dart и utils/image_compressor.dart).
  MediaQualityLevel get imageQualityLevel => _imageQualityLevel;

  MediaQualityConfig get imageQualityConfig =>
      MediaQuality.photo(_imageQualityLevel);

  /// Уровень качества видео: 1 — high, 2 — medium, 3 — low (default).
  /// Используется ffmpeg.wasm (web) и v_video_compressor (native).
  int get videoQualityLevel => _videoQualityLevel;

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
    _imageQualityLevel =
        MediaQuality.levelFromKey(prefs.getString('imageQualityLevel'));
    _videoQualityLevel =
        MediaQuality.videoLevelFromKey(prefs.getString('videoQualityLevel'));
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
    await prefs.setString(
      'imageQualityLevel',
      MediaQuality.keyForLevel(_imageQualityLevel),
    );
    await prefs.setString(
      'videoQualityLevel',
      MediaQuality.videoKeyForLevel(_videoQualityLevel),
    );
    notifyListeners();
  }

  /// Включает/выключает звёздный фон и сохраняет выбор.
  Future<void> setStarsBackground(bool value) async {
    _starsBackground = value;
    notifyListeners();
    await saveSettings();
  }

  /// Установить уровень качества фото и сразу сохранить.
  Future<void> setImageQualityLevel(MediaQualityLevel value) async {
    if (_imageQualityLevel == value) return;
    _imageQualityLevel = value;
    notifyListeners();
    await saveSettings();
  }

  /// Установить уровень качества видео (1 high / 2 medium / 3 low)
  /// и сразу сохранить в prefs.
  Future<void> setVideoQualityLevel(int level) async {
    final clamped = level.clamp(1, 3);
    if (_videoQualityLevel == clamped) return;
    _videoQualityLevel = clamped;
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
    await prefs.remove('imageQualityLevel');
    await prefs.remove('videoQualityLevel');
    _templatesFolder = '';
    _reportsFolder = '';
    _mediaFolder = '';
    _starsBackground = false;
    _imageQualityLevel = MediaQualityLevel.medium;
    _videoQualityLevel = MediaQuality.defaultVideoLevel;
    notifyListeners();
  }
}
