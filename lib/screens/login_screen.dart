import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_colors.dart';

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
    // P1-56: инициализация _serverController.text в initState
    // через addPostFrameCallback вместо побочного эффекта в build().
    // Это гарантирует однократную установку и не сбивает позицию курсора.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (_serverController.text.isEmpty) {
        _serverController.text = authProvider.serverUrl;
      }
    });
  }

  /// Разобрать строку "host:port" → (host, port).
  /// Если порт не указан, используется 3000.
  (String, int) _parseServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return ('localhost', 3000);

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
    return (cleaned, 3000);
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
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loc = AppLocalizations.of(context)!;

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
      );
    } else {
      success = await authProvider.login(
        _usernameController.text,
        _passwordController.text,
      );
    }

    setState(() {
      _isLoading = false;
    });

    if (!context.mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.loginSuccess)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.lastError ?? loc.loginError),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onTap,
    bool isOutline = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isOutline ? Colors.white : AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(11),
        ),
        border: Border.all(width: 2.5, color: AppColors.border),
        boxShadow: isOutline
            ? null
            : [
                const BoxShadow(
                  color: AppColors.border,
                  blurRadius: 0,
                  spreadRadius: 1.5,
                ),
                const BoxShadow(
                  color: AppColors.shadowOverlay,
                  offset: Offset(2, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(11),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(9),
            bottomRight: Radius.circular(11),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                shadows: [
                  Shadow(
                    color: AppColors.textShadowDark,
                    blurRadius: 1.2,
                  ),
                  Shadow(
                    color: AppColors.textShadowLight,
                    blurRadius: 0.8,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(width: 2, color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isRegisterMode ? loc.registerTitle : loc.loginTitle,
                  style: const TextStyle(
                    fontSize: 24,
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: _fieldDecoration(loc.usernameLabel),
                ),
                const SizedBox(height: 16),
                if (_isRegisterMode) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _fieldDecoration(loc.emailLabel),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _fieldDecoration(loc.passwordLabel),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else ...[
                  _buildButton(
                    label: _isRegisterMode
                        ? loc.registerAction
                        : loc.loginAction,
                    onTap: () => _handleSubmit(context),
                  ),
                  const SizedBox(height: 12),
                  _buildButton(
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
                  ),
                  const SizedBox(height: 12),
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
  final authProvider = Provider.of<AuthProvider>(
    context,
    listen: false,
  );
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
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(loc.logoutAction)),
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.errorLight,
          ),
          child: Text(loc.logoutAction),
        ),
      ],
    ),
  );
}
