import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_colors.dart';
import 'package:easy_tab/widgets/easy_tab_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _serverController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isLoading = false;
  bool _isTestingConnection = false;
  bool? _connectionStatus; // null = не проверено, true = ОК, false = провал
  bool _showServerField = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // На момент initState provider уже инициализирован (App запускает
    // EasyTabApp после await localeProvider.init() + authProvider.init()
    // в main.dart), поэтому можно синхронно заполнить поле адреса сервера.
    // addPostFrameCallback не нужен и не гоняется за TextEditingValue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncServerUrlFromProvider(force: false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Если пользователь закрыл диалог и снова открыл (mounted уже true,
    // initState не вызывается повторно), а сохранённые prefs успели
    // обновиться — подхватываем актуальный serverUrl.
    _syncServerUrlFromProvider(force: false);
  }

  /// Заполнить поле «адрес сервера» актуальным значением из AuthProvider.
  /// [force] — обновить даже если пользователь редактировал поле.
  void _syncServerUrlFromProvider({required bool force}) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final value = authProvider.serverUrl;
    if (force || _serverController.text.isEmpty) {
      _serverController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  /// Разобрать строку "host:port" → (host, port).
  /// Если порт не указан, используется 8000 (default для easyTab backend).
  (String, int) _parseServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return ('localhost', 8000);

    // Поддержка http:// или https:// префикса.
    String cleaned = trimmed;
    if (cleaned.startsWith('http://')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('https://')) {
      cleaned = cleaned.substring(8);
    }

    final lastColon = cleaned.lastIndexOf(':');
    if (lastColon > 0 && lastColon < cleaned.length - 1) {
      final portStr = cleaned.substring(lastColon + 1);
      final port = int.tryParse(portStr);
      if (port != null && port > 0 && port < 65536) {
        return (cleaned.substring(0, lastColon), port);
      }
    }
    return (cleaned, 8000);
  }

  Future<void> _testConnection(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final (host, port) = _parseServerUrl(_serverController.text);
    await authProvider.setServerUrl(host, port);

    setState(() {
      _isTestingConnection = true;
      _connectionStatus = null;
    });

    final ok = await authProvider.testConnection();

    setState(() {
      _isTestingConnection = false;
      _connectionStatus = ok;
    });

    if (!context.mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? loc.connectionOk : loc.connectionFailed),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.enterCredentials)));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Применяем текущий адрес сервера перед запросом.
    if (_serverController.text.isNotEmpty) {
      final (host, port) = _parseServerUrl(_serverController.text);
      await authProvider.setServerUrl(host, port);
    }

    bool success;
    if (_isRegisterMode) {
      success = await authProvider.register(
        _usernameController.text,
        _passwordController.text,
        email: _emailController.text,
        loc: loc,
      );
    } else {
      success = await authProvider.login(
        _usernameController.text,
        _passwordController.text,
        loc: loc,
      );
    }

    setState(() {
      _isLoading = false;
    });

    if (!context.mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.loginSuccess)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.lastError ??
                (_isRegisterMode ? loc.registerFailed : loc.loginError),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isNarrow = MediaQuery.sizeOf(context).shortestSide < 420;
    final contentPadding = isNarrow ? 18.0 : 24.0;
    final titleSize = isNarrow ? 20.0 : 24.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 14 : 24,
        vertical: 20,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isNarrow ? double.infinity : 400,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(width: 2, color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(contentPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isRegisterMode ? loc.registerTitle : loc.loginTitle,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                // Сворачиваемый блок выбора сервера.
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showServerField = !_showServerField;
                        if (_showServerField) {
                          // Пользователь раскрыл настройки — подставляем
                          // актуальный адрес (на случай, если успел измениться).
                          _syncServerUrlFromProvider(force: true);
                        }
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showServerField
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        Text(
                          loc.serverSettings,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showServerField) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverController,
                    keyboardType: TextInputType.url,
                    decoration: _fieldDecoration(loc.serverLabel).copyWith(
                      suffixIcon: _isTestingConnection
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                _connectionStatus == null
                                    ? Icons.wifi_find
                                    : (_connectionStatus == true
                                          ? Icons.check_circle
                                          : Icons.error_outline),
                                color: _connectionStatus == null
                                    ? AppColors.textSecondary
                                    : (_connectionStatus == true
                                          ? AppColors.success
                                          : AppColors.error),
                                size: 20,
                              ),
                              onPressed: _isTestingConnection
                                  ? null
                                  : () => _testConnection(context),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(height: isNarrow ? 10 : 16),
                TextField(
                  controller: _usernameController,
                  decoration: _fieldDecoration(loc.usernameLabel),
                ),
                SizedBox(height: isNarrow ? 10 : 16),
                if (_isRegisterMode) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _fieldDecoration(loc.emailLabel),
                  ),
                  SizedBox(height: isNarrow ? 10 : 16),
                ],
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _fieldDecoration(loc.passwordLabel),
                ),
                SizedBox(height: isNarrow ? 18 : 24),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  EasyTabButton(
                    label: _isRegisterMode
                        ? loc.registerAction
                        : loc.loginAction,
                    onTap: () => _handleSubmit(context),
                    fontSize: isNarrow ? 13 : 14,
                    verticalPadding: isNarrow ? 10 : 12,
                  ),
                  const SizedBox(height: 12),
                  EasyTabButton(
                    label: _isRegisterMode
                        ? loc.loginAction
                        : loc.registerAction,
                    onTap: () {
                      setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        _emailController.clear();
                      });
                    },
                    isOutline: true,
                    fontSize: isNarrow ? 13 : 14,
                    verticalPadding: isNarrow ? 10 : 12,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      loc.cancelAction,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Диалог авторизации с поддержкой двух режимов: вход и регистрация.
Future<void> showLoginDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const LoginScreen(),
  );
}

/// Диалог настроек пользователя: показывает данные аккаунта,
/// адрес сервера и кнопку выхода.
Future<void> showSettingsDialog(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final loc = AppLocalizations.of(context)!;

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 2),
      ),
      title: Row(
        children: [
          const Icon(Icons.settings, size: 24, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(
            loc.settingsTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Блок аккаунта
          Text(
            loc.accountSection,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${loc.usernameLabel}: ${authProvider.username ?? "-"}',
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          if (authProvider.email != null) ...[
            const SizedBox(height: 4),
            Text(
              '${loc.emailLabel}: ${authProvider.email}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Блок сервера
          Text(
            loc.serverSettings,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${authProvider.serverHost}:${authProvider.serverPort}',
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          // Настройка фона: звёзды вместо точечного узора
          Consumer<SettingsState>(
            builder: (ctx, settings, _) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                loc.starsBackground,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              value: settings.starsBackground,
              onChanged: (value) {
                settings.setStarsBackground(value ?? false);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(loc.close),
        ),
        TextButton(
          onPressed: () async {
            await authProvider.logout();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text(loc.logoutAction)));
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.errorLight),
          child: Text(loc.logoutAction),
        ),
      ],
    ),
  );
}
