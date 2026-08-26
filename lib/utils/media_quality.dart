// ============================================================
// MediaQuality — уровни качества медиа (фото + видео).
//
// Используется в SettingsState как пользовательская настройка
// «Качество медиаданных» и применяется при компрессии
// изображений (ImageCompressor) и видео (web/native).
//
// Конфиг видео-компрессии (VideoCompressionConfig) общий для:
//   - WebVideoCompressor (ffmpeg.wasm crf/resolution/fps)
//   - native v_video_compressor preset mapping (high/medium/low)
// ============================================================

/// Уровень качества медиа (для фото и видео).
enum MediaQualityLevel {
  /// 2000px max side, JPEG quality 85 / видео — high (level 1).
  high,

  /// 1500px max side, JPEG quality 85 / видео — medium (level 2).
  /// Значение по умолчанию.
  medium,

  /// 1080px max side, JPEG quality 80 / видео — low (level 3).
  low,
}

/// Набор параметров компрессии фото для одного уровня.
class MediaQualityConfig {
  /// Максимальный размер по бОльшей стороне при ресайзе фото.
  final int imageMaxSize;

  /// JPEG-quality фото (0..100). PNG/WebP используют как fallback.
  final int imageJpegQuality;

  /// Соответствующий уровень качества видео: 1 — high, 2 — medium, 3 — low.
  final int videoLevel;

  /// Читаемое значение (для отладки / хранения в prefs).
  final String key;

  const MediaQualityConfig({
    required this.imageMaxSize,
    required this.imageJpegQuality,
    required this.videoLevel,
    required this.key,
  });
}

/// Конфиг компрессии видео (маппится на ffmpeg/native параметры).
///
/// Уровни: 1=high, 2=medium, 3=low (default, согласно ТЗ).
class VideoCompressionConfig {
  final int qualityLevel;
  final int crf;
  final int width;
  final int height;
  final int fps;
  final String key;

  const VideoCompressionConfig({
    required this.qualityLevel,
    required this.crf,
    required this.width,
    required this.height,
    required this.fps,
    required this.key,
  });

  factory VideoCompressionConfig.byLevel(int? level) {
    switch (level ?? 3) {
      case 1:
        return const VideoCompressionConfig(
          qualityLevel: 1,
          crf: 22,
          width: 1920,
          height: 1080,
          fps: 30,
          key: 'high',
        );
      case 2:
        return const VideoCompressionConfig(
          qualityLevel: 2,
          crf: 26,
          width: 1280,
          height: 720,
          fps: 24,
          key: 'medium',
        );
      case 3:
      default:
        return const VideoCompressionConfig(
          qualityLevel: 3,
          crf: 30,
          width: 854,
          height: 480,
          fps: 24,
          key: 'low',
        );
    }
  }
}

/// Карта: уровень → конфигурация компрессии фото.
///
/// Требования заказчика:
/// - High: 2000 px / 85%
/// - Medium: 1500 px / 85% (значение по умолчанию)
/// - Low: 1080 px / 80%
/// Видео по умолчанию — Низкое качество (level = 3).
class MediaQuality {
  static const MediaQualityConfig high = MediaQualityConfig(
    imageMaxSize: 2000,
    imageJpegQuality: 85,
    videoLevel: 1,
    key: 'high',
  );
  static const MediaQualityConfig medium = MediaQualityConfig(
    imageMaxSize: 1500,
    imageJpegQuality: 85,
    videoLevel: 2,
    key: 'medium',
  );
  static const MediaQualityConfig low = MediaQualityConfig(
    imageMaxSize: 1080,
    imageJpegQuality: 80,
    videoLevel: 3,
    key: 'low',
  );

  static const Map<MediaQualityLevel, MediaQualityConfig> photoLevels = {
    MediaQualityLevel.high: high,
    MediaQualityLevel.medium: medium,
    MediaQualityLevel.low: low,
  };

  /// Получить конфиг фото-уровня по enum.
  static MediaQualityConfig photo(MediaQualityLevel level) =>
      photoLevels[level] ?? medium;

  /// Получить конфиг по строковому ключу (из SharedPreferences).
  static MediaQualityConfig photoFromKey(String? key) {
    if (key == null) return medium;
    return photoLevels.values.firstWhere(
      (c) => c.key == key,
      orElse: () => medium,
    );
  }

  /// Enum по ключу prefs (для dropdown в UI).
  static MediaQualityLevel levelFromKey(String? key) {
    switch (key) {
      case 'high':
        return MediaQualityLevel.high;
      case 'low':
        return MediaQualityLevel.low;
      case 'medium':
      default:
        return MediaQualityLevel.medium;
    }
  }

  static String keyForLevel(MediaQualityLevel l) => photo(l).key;

  /// Уровень видео по умолчанию — Низкое (qualityLevel = 3).
  /// (Отдельно от фото, согласно ТЗ.)
  static const int defaultVideoLevel = 3;

  /// Соответствие qualityLevel integer → label key.
  static const Map<int, String> videoLevelKey = {
    1: 'high',
    2: 'medium',
    3: 'low',
  };

  static int videoLevelFromKey(String? key) {
    switch (key) {
      case 'high':
        return 1;
      case 'medium':
        return 2;
      case 'low':
      default:
        return 3;
    }
  }

  static String videoKeyForLevel(int level) =>
      videoLevelKey[level] ?? 'low';
}
