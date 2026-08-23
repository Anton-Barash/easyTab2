import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../services/anonymous_id_service.dart';
import '../services/api_service.dart';
import '../services/share_token_storage.dart';
import '../utils/app_colors.dart';
import '../utils/filename_utils.dart';
import '../widgets/easy_tab_button.dart';
import 'form_fill_screen.dart';

// Conditional imports для открытия ссылок и скачивания на web.
import '../utils/share_link_opener_stub.dart'
    if (dart.library.html) '../utils/share_link_opener_web.dart';

/// ============================================================
/// ShareWelcomeScreen — приветственный экран по share-ссылке.
///
/// Открывается по маршруту `/welcome?token=abc123`.
/// Показывает название отчёта, срок действия ссылки и три
/// действия:
///   1. Просмотр (лёгкая HTML-версия)
///   2. Редактировать (веб-версия)
///   3. Скачать ZIP для офлайн-работы
///
/// Язык интерфейса управляется глобальной настройкой (LocaleProvider).
/// ============================================================

class ShareWelcomeScreen extends StatefulWidget {
  final String token;

  const ShareWelcomeScreen({super.key, required this.token});

  @override
  State<ShareWelcomeScreen> createState() => _ShareWelcomeScreenState();
}

class _ShareWelcomeScreenState extends State<ShareWelcomeScreen> {
  bool _isLoading = true;
  String? _error;
  String _reportTitle = '';
  String _permissions = 'edit';
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _loadShareInfo();
  }

  Future<void> _loadShareInfo() async {
    try {
      final anonymousId = await AnonymousIdService.getId();
      final result = await ApiService.getShareInfo(
        token: widget.token,
        anonymousId: anonymousId,
      );

      if (!mounted) return;

      if (!result.success || result.data == null) {
        final loc = AppLocalizations.of(context)!;
        setState(() {
          _isLoading = false;
          _error = result.error ?? loc.loadLinkFailed;
        });
        return;
      }

      final data = result.data!;
      final loc = AppLocalizations.of(context)!;
      final report = data['report'] ?? {};
      final share = data['share'] ?? {};
      final reportData = report['reportData'] ?? {};

      setState(() {
        _isLoading = false;
        _reportTitle = (reportData['reportName'] ?? report['title'] ?? loc.noName)
            .toString();
        _permissions = share['permissions']?.toString() ?? 'edit';
        final expiresRaw = share['expiresAt'];
        if (expiresRaw != null) {
          _expiresAt = DateTime.tryParse(expiresRaw.toString())?.toLocal();
        }
      });

      // Сохраняем токен, чтобы показать отчёт в списке отчётов
      await ShareTokenStorage.addToken(widget.token);
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context)!;
      setState(() {
        _isLoading = false;
        _error = loc.loadError(e.toString());
      });
    }
  }

  void _openWebEditor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FormFillScreen(shareToken: widget.token),
      ),
    );
  }

  Future<void> _openHtml() async {
    final anonymousId = await AnonymousIdService.getId();
    final baseUrl = ApiService.baseUrl;
    final uri = Uri.http(baseUrl, '/reports/shares/${widget.token}/html', {
      'anonymous_id': anonymousId,
    });
    openShareLink(uri.toString());
  }

  Future<void> _downloadZip() async {
    final anonymousId = await AnonymousIdService.getId();
    final baseUrl = ApiService.baseUrl;
    final uri = Uri.http(baseUrl, '/reports/shares/${widget.token}/zip', {
      'anonymous_id': anonymousId,
    });
    final zipName = buildShareZipName(_reportTitle, widget.token);
    downloadShareZip(uri.toString(), zipName);
  }

  String _formatExpiresAt() {
    if (_expiresAt == null) return '';
    final date = _expiresAt!;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).shortestSide < 400;
    final outerPadding = isNarrow ? 12.0 : 24.0;
    final contentSpacing = isNarrow ? 24.0 : 40.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          _LanguageSwitcher(),
        ],
      ),
      body: SafeArea(
        // SingleChildScrollView + адаптивные отступы: на узких экранах
        // контент не наплывает на кнопки и не переполняется (BOTTOM OVERFLOW).
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isNarrow ? double.infinity : 560,
              ),
              child: Padding(
                padding: EdgeInsets.all(outerPadding),
                child: _WelcomeContent(
                  isLoading: _isLoading,
                  error: _error,
                  reportTitle: _reportTitle,
                  permissions: _permissions,
                  expiresAt: _expiresAt,
                  isNarrow: isNarrow,
                  contentSpacing: contentSpacing,
                  onRetry: _loadShareInfo,
                  onOpenHtml: _openHtml,
                  onOpenWebEditor: _openWebEditor,
                  onDownloadZip: _downloadZip,
                  formatExpiresAt: _formatExpiresAt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final String reportTitle;
  final String permissions;
  final DateTime? expiresAt;
  final bool isNarrow;
  final double contentSpacing;
  final VoidCallback onRetry;
  final Future<void> Function() onOpenHtml;
  final VoidCallback onOpenWebEditor;
  final Future<void> Function() onDownloadZip;
  final String Function() formatExpiresAt;

  const _WelcomeContent({
    required this.isLoading,
    required this.error,
    required this.reportTitle,
    required this.permissions,
    required this.expiresAt,
    required this.isNarrow,
    required this.contentSpacing,
    required this.onRetry,
    required this.onOpenHtml,
    required this.onOpenWebEditor,
    required this.onDownloadZip,
    required this.formatExpiresAt,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return SizedBox(
        height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SelectableText(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            EasyTabButton(label: AppLocalizations.of(context)!.retry, onTap: onRetry),
          ],
        ),
      );
    }

    final loc = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          permissions == 'edit' ? Icons.edit_document : Icons.visibility,
          size: isNarrow ? 52 : 64,
          color: AppColors.grey700,
        ),
        SizedBox(height: isNarrow ? 16 : 24),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 0),
          child: SelectableText(
            reportTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isNarrow ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          permissions == 'edit' ? loc.editAccess : loc.viewOnlyAccess,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isNarrow ? 13 : 14,
            color: AppColors.textSecondary,
          ),
        ),
        if (expiresAt != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 0),
            child: SelectableText(
              '${loc.linkValidUntil} ${formatExpiresAt()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isNarrow ? 12 : 13,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
        SizedBox(height: contentSpacing),
        // Для view-only — только HTML просмотр + предупреждение.
        // Для edit — все действия.
        if (permissions == 'view') ...[
          Container(
            padding: EdgeInsets.all(isNarrow ? 12 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC107)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: Color(0xFFE65100),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    loc.viewOnlyWarning,
                    style: TextStyle(
                      fontSize: isNarrow ? 12 : 13,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ActionCard(
            icon: Icons.html,
            title: loc.openHtmlTooltip,
            subtitle: loc.openHtmlDesc,
            onTap: onOpenHtml,
            compact: isNarrow,
          ),
        ] else ...[
          _ActionCard(
            icon: Icons.html,
            title: loc.openHtmlTooltip,
            subtitle: loc.openHtmlDesc,
            onTap: onOpenHtml,
            compact: isNarrow,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.open_in_browser,
            title: loc.openWebEditor,
            subtitle: loc.openWebEditorDesc,
            onTap: onOpenWebEditor,
            compact: isNarrow,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.folder_zip,
            title: loc.downloadZip,
            subtitle: loc.downloadZipDesc,
            onTap: onDownloadZip,
            compact: isNarrow,
          ),
        ],
      ],
    );
  }
}

/// Переключатель языка интерфейса (управляет глобальной локалью).
class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher();

  static const _languages = ['ru', 'en', 'zh'];

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            localeProvider.locale.languageCode.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      itemBuilder: (ctx) => _languages
          .map(
            (lang) => PopupMenuItem(
              value: lang,
              child: Row(
                children: [
                  Text(lang.toUpperCase()),
                  if (localeProvider.locale.languageCode == lang)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, size: 16),
                    ),
                ],
              ),
            ),
          )
          .toList(),
      onSelected: (lang) => localeProvider.setLocale(Locale(lang)),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool compact;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = compact ? 12.0 : 16.0;
    final verticalPadding = compact ? 10.0 : 14.0;
    final iconSize = compact ? 18.0 : null;
    final titleSize = compact ? 14.0 : 15.0;
    final subtitleSize = compact ? 12.0 : 13.0;
    final titleMaxLines = compact ? 1 : 2;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.greyBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: compact ? 32 : 40,
                  minHeight: compact ? 32 : 40,
                ),
                child: Container(
                  width: compact ? 32 : 40,
                  height: compact ? 32 : 40,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.grey700,
                    size: iconSize,
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: compact ? 1 : 2),
                    Text(
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        color: AppColors.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: compact ? 18 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
