import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/report_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/media_quality.dart';

/// Секция «Качество медиаданных» — два компактных дропдауна:
///   1. Качество фото (MediaQualityLevel);
///   2. Качество видео (1/2/3).
///
/// Используется:
///  - в LoginScreen (главное меню → Настройки → Настройки медиаданных);
///  - в модальном окне «Выбор качества медиаданных» (FormFillScreen, меню).
///
/// При изменении применяет настройки в SettingsState и синхронизирует
/// их с ReportState (applyMediaQualitySettings).
class MediaQualitySection extends StatelessWidget {
  const MediaQualitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Consumer<SettingsState>(
      builder: (ctx, settings, _) {
        final imgCfg = settings.imageQualityConfig;

        // Локализованное название уровня качества фото.
        String photoLabel(MediaQualityLevel lvl) => switch (lvl) {
              MediaQualityLevel.high => loc.mediaImageQualityHigh,
              MediaQualityLevel.medium => loc.mediaImageQualityMedium,
              MediaQualityLevel.low => loc.mediaImageQualityLow,
            };

        // Подробные характеристики уровня фото (для подсказки/выбранного).
        String photoDetail(MediaQualityLevel lvl) {
          final c = MediaQuality.photo(lvl);
          return '${c.imageMaxSize}px · Q${c.imageJpegQuality}';
        }

        // Локализованное название уровня качества видео.
        String videoLabel(int vl) => switch (vl) {
              1 => loc.mediaVideoQualityHigh,
              2 => loc.mediaVideoQualityMedium,
              _ => loc.mediaVideoQualityLow,
            };

        // Подробные характеристики уровня видео.
        String videoDetail(int vl) {
          final c = VideoCompressionConfig.byLevel(vl);
          return '${c.width}×${c.height} · CRF ${c.crf} · ${c.fps}fps';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // —— Фото ——
            Text(
              loc.mediaImageQuality,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<MediaQualityLevel>(
              initialValue: settings.imageQualityLevel,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: MediaQualityLevel.values
                  .map(
                    (lvl) => DropdownMenuItem(
                      value: lvl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            photoLabel(lvl),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            photoDetail(lvl),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              // В закрытом состоянии показываем выбранный режим.
              selectedItemBuilder: (ctx) => MediaQualityLevel.values
                  .map(
                    (lvl) => Text(
                      photoLabel(lvl),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                await settings.setImageQualityLevel(v);
                if (!ctx.mounted) return;
                final newCfg = settings.imageQualityConfig;
                ctx.read<ReportState>().applyMediaQualitySettings(
                      imageMaxSize: newCfg.imageMaxSize,
                      imageJpegQuality: newCfg.imageJpegQuality,
                      videoQualityLevel: settings.videoQualityLevel,
                    );
              },
            ),

            const SizedBox(height: 12),

            // —— Видео ——
            Text(
              loc.mediaVideoQuality,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: settings.videoQualityLevel,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: const [1, 2, 3]
                  .map(
                    (vl) => DropdownMenuItem(
                      value: vl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            videoLabel(vl),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            videoDetail(vl),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (ctx) => const [1, 2, 3]
                  .map(
                    (vl) => Text(
                      videoLabel(vl),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                await settings.setVideoQualityLevel(v);
                if (!ctx.mounted) return;
                ctx.read<ReportState>().applyMediaQualitySettings(
                      imageMaxSize: imgCfg.imageMaxSize,
                      imageJpegQuality: imgCfg.imageJpegQuality,
                      videoQualityLevel: v,
                    );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Модальное окно «Выбор качества медиаданных».
/// Открывается из меню FormFillScreen.
Future<void> showMediaQualityDialog(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(loc.mediaQualityMenuItem),
      content: const SingleChildScrollView(
        child: MediaQualitySection(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(loc.ok),
        ),
      ],
    ),
  );
}
