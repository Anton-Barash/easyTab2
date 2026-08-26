import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/report_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/media_quality.dart';

/// Секция «Качество медиаданных» — радио-кнопки для фото и видео.
///
/// Используется:
///  - в SettingsDialog (LoginScreen);
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.mediaImageQuality,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            for (final lvl in MediaQualityLevel.values)
              RadioListTile<MediaQualityLevel>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                groupValue: settings.imageQualityLevel,
                value: lvl,
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
                title: Text(
                  switch (lvl) {
                    MediaQualityLevel.high => loc.mediaImageQualityHigh,
                    MediaQualityLevel.medium => loc.mediaImageQualityMedium,
                    MediaQualityLevel.low => loc.mediaImageQualityLow,
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${MediaQuality.photo(lvl).imageMaxSize}px · Q${MediaQuality.photo(lvl).imageJpegQuality}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              loc.mediaVideoQuality,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            for (final vl in const [1, 2, 3])
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                groupValue: settings.videoQualityLevel,
                value: vl,
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
                title: Text(
                  switch (vl) {
                    1 => loc.mediaVideoQualityHigh,
                    2 => loc.mediaVideoQualityMedium,
                    _ => loc.mediaVideoQualityLow,
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  () {
                    final cfg = VideoCompressionConfig.byLevel(vl);
                    return '${cfg.width}×${cfg.height} · CRF ${cfg.crf} · ${cfg.fps}fps';
                  }(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
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
