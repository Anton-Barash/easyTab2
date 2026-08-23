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
    final loc = AppLocalizations.of(context)!;
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildContent(loc),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations loc) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          SelectableText(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 24),
          EasyTabButton(label: loc.retry, onTap: _loadShareInfo),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          _permissions == 'edit' ? Icons.edit_document : Icons.visibility,
          size: 64,
          color: AppColors.grey700,
        ),
        const SizedBox(height: 24),
        SelectableText(
          _reportTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _permissions == 'edit' ? loc.editAccess : loc.viewOnlyAccess,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        if (_expiresAt != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            '${loc.linkValidUntil} ${_formatExpiresAt()}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: 40),
        // Для view-only — только HTML просмотр + предупреждение.
        // Для edit — все действия.
        if (_permissions == 'view') ...[
          Container(
            padding: const EdgeInsets.all(16),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
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
            onTap: _openHtml,
          ),
        ] else ...[
          _ActionCard(
            icon: Icons.html,
            title: loc.openHtmlTooltip,
            subtitle: loc.openHtmlDesc,
            onTap: _openHtml,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.open_in_browser,
            title: loc.openWebEditor,
            subtitle: loc.openWebEditorDesc,
            onTap: _openWebEditor,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.folder_zip,
            title: loc.downloadZip,
            subtitle: loc.downloadZipDesc,
            onTap: _downloadZip,
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

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: AppColors.grey700),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
