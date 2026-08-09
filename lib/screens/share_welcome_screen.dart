import 'dart:async';
import 'package:flutter/material.dart';
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
/// Показывает название отчёта, срок действия ссылки и четыре
/// действия:
///   1. Скачать приложение Android/Windows (заглушка)
///   2. Открыть веб-версию для редактирования
///   3. Открыть HTML для просмотра
///   4. Скачать ZIP для офлайн-работы
///
/// Поддерживает переключение языка интерфейса (RU/EN/CN).
/// Весь текст можно выделять.
/// ============================================================

/// Локализованные строки для welcome-экрана.
class _Strings {
  final String appName;
  final String sharedReport;
  final String editAccess;
  final String viewAccess;
  final String validUntil;
  final String downloadApp;
  final String downloadAppDesc;
  final String openWebEditor;
  final String openWebEditorDesc;
  final String openHtml;
  final String openHtmlDesc;
  final String downloadZip;
  final String downloadZipDesc;
  final String retry;
  final String loadError;
  final String appLinksStub;
  final String viewOnlyWarning;

  const _Strings({
    required this.appName,
    required this.sharedReport,
    required this.editAccess,
    required this.viewAccess,
    required this.validUntil,
    required this.downloadApp,
    required this.downloadAppDesc,
    required this.openWebEditor,
    required this.openWebEditorDesc,
    required this.openHtml,
    required this.openHtmlDesc,
    required this.downloadZip,
    required this.downloadZipDesc,
    required this.retry,
    required this.loadError,
    required this.appLinksStub,
    required this.viewOnlyWarning,
  });

  static const Map<String, _Strings> _locales = {
    'RU': _Strings(
      appName: 'EasyTab',
      sharedReport: 'Общий отчёт',
      editAccess: 'Доступ для редактирования',
      viewAccess: 'Доступ только для просмотра',
      validUntil: 'Ссылка действует до',
      downloadApp: 'Скачайте приложение',
      downloadAppDesc: 'Для Android или Windows',
      openWebEditor: 'Открыть веб-версию',
      openWebEditorDesc: 'Для редактирования отчёта',
      openHtml: 'Открыть HTML',
      openHtmlDesc: 'Для просмотра в браузере',
      downloadZip: 'Скачать ZIP',
      downloadZipDesc: 'Отчёт с медиа для офлайн-работы',
      retry: 'Обновить',
      loadError: 'Не удалось загрузить ссылку',
      appLinksStub: 'Ссылки на приложения будут здесь',
      viewOnlyWarning: 'Доступен только просмотр. Для редактирования запросите доступ у владельца отчёта.',
    ),
    'EN': _Strings(
      appName: 'EasyTab',
      sharedReport: 'Shared Report',
      editAccess: 'Edit access',
      viewAccess: 'View only access',
      validUntil: 'Link valid until',
      downloadApp: 'Download App',
      downloadAppDesc: 'For Android or Windows',
      openWebEditor: 'Open Web Editor',
      openWebEditorDesc: 'To edit the report',
      openHtml: 'Open HTML',
      openHtmlDesc: 'To view in browser',
      downloadZip: 'Download ZIP',
      downloadZipDesc: 'Report with media for offline use',
      retry: 'Retry',
      loadError: 'Failed to load link',
      appLinksStub: 'App download links will be here',
      viewOnlyWarning: 'View only access. To edit, request access from the report owner.',
    ),
    'CN': _Strings(
      appName: 'EasyTab',
      sharedReport: '共享报告',
      editAccess: '编辑权限',
      viewAccess: '仅查看权限',
      validUntil: '链接有效期至',
      downloadApp: '下载应用',
      downloadAppDesc: '适用于 Android 或 Windows',
      openWebEditor: '打开网页版',
      openWebEditorDesc: '编辑报告',
      openHtml: '打开 HTML',
      openHtmlDesc: '在浏览器中查看',
      downloadZip: '下载 ZIP',
      downloadZipDesc: '包含媒体的离线报告',
      retry: '重试',
      loadError: '无法加载链接',
      appLinksStub: '应用下载链接将在此处',
      viewOnlyWarning: '仅可查看。如需编辑，请向报告所有者申请权限。',
    ),
  };

  static _Strings get(String lang) => _locales[lang] ?? _locales['RU']!;
}

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
  String _uiLanguage = 'RU';

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
        setState(() {
          _isLoading = false;
          _error = result.error ?? 'Не удалось загрузить ссылку';
        });
        return;
      }

      final data = result.data!;
      final report = data['report'] ?? {};
      final share = data['share'] ?? {};
      final reportData = report['reportData'] ?? {};

      setState(() {
        _isLoading = false;
        _reportTitle = (reportData['reportName'] ?? report['title'] ?? 'Отчёт').toString();
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
      setState(() {
        _isLoading = false;
        _error = 'Ошибка загрузки: $e';
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

  void _showDownloadAppsStub() {
    final s = _Strings.get(_uiLanguage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.appLinksStub)),
    );
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
    final s = _Strings.get(_uiLanguage);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _LanguageSwitcher(
            current: _uiLanguage,
            onChanged: (lang) => setState(() => _uiLanguage = lang),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildContent(s),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_Strings s) {
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
          EasyTabButton(
            label: s.retry,
            onTap: _loadShareInfo,
          ),
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
          _permissions == 'edit' ? s.editAccess : s.viewAccess,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        if (_expiresAt != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            '${s.validUntil} ${_formatExpiresAt()}',
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
                const Icon(Icons.lock_outline, size: 20, color: Color(0xFFE65100)),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    s.viewOnlyWarning,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ActionCard(
            icon: Icons.html,
            title: s.openHtml,
            subtitle: s.openHtmlDesc,
            onTap: _openHtml,
          ),
        ] else ...[
          _ActionCard(
            icon: Icons.phone_android,
            title: s.downloadApp,
            subtitle: s.downloadAppDesc,
            onTap: _showDownloadAppsStub,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.open_in_browser,
            title: s.openWebEditor,
            subtitle: s.openWebEditorDesc,
            onTap: _openWebEditor,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.html,
            title: s.openHtml,
            subtitle: s.openHtmlDesc,
            onTap: _openHtml,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.folder_zip,
            title: s.downloadZip,
            subtitle: s.downloadZipDesc,
            onTap: _downloadZip,
          ),
        ],
      ],
    );
  }
}

/// Переключатель языка интерфейса.
class _LanguageSwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _LanguageSwitcher({required this.current, required this.onChanged});

  static const _languages = ['RU', 'EN', 'CN'];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            current,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      itemBuilder: (ctx) => _languages
          .map((lang) => PopupMenuItem(
                value: lang,
                child: Row(
                  children: [
                    Text(lang),
                    if (lang == current)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 16),
                      ),
                  ],
                ),
              ))
          .toList(),
      onSelected: onChanged,
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
