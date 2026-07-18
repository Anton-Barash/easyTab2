import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';

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

    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? loc.connectionOk : loc.connectionFailed),
        backgroundColor: ok ? const Color(0xFF2e7d32) : const Color(0xFFc62828),
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

    if (!mounted) return;

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
        color: isOutline ? Colors.white : const Color(0xFFe0e0e0),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(11),
        ),
        border: Border.all(width: 2.5, color: const Color(0xFF333333)),
        boxShadow: isOutline
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF333333),
                  blurRadius: 0,
                  spreadRadius: 1.5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.13),
                  offset: const Offset(2, 2),
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
                color: Color(0xFF424242),
                shadows: [
                  Shadow(
                    color: Color.fromRGBO(66, 66, 66, 0.45),
                    blurRadius: 1.2,
                  ),
                  Shadow(
                    color: Color.fromRGBO(255, 255, 255, 0.9),
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
      labelStyle: const TextStyle(color: Color(0xFF666666)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF333333), width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF333333), width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF333333), width: 2),
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
          border: Border.all(width: 2, color: const Color(0xFF333333)),
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
                    color: Color(0xFF424242),
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
                          color: const Color(0xFF666666),
                        ),
                        Text(
                          loc.serverSettings,
                          style: const TextStyle(
                            color: Color(0xFF666666),
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
                                    ? const Color(0xFF666666)
                                    : (_connectionStatus == true
                                        ? const Color(0xFF2e7d32)
                                        : const Color(0xFFc62828)),
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
                        color: Color(0xFF666666),
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
        side: const BorderSide(color: Color(0xFF333333), width: 2),
      ),
      title: Row(
        children: [
          const Icon(Icons.settings, size: 24, color: Color(0xFF424242)),
          const SizedBox(width: 8),
          Text(
            loc.settingsTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF424242),
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
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${loc.usernameLabel}: ${authProvider.username ?? "-"}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF424242)),
          ),
          if (authProvider.email != null) ...[
            const SizedBox(height: 4),
            Text(
              '${loc.emailLabel}: ${authProvider.email}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
            ),
          ],
          const SizedBox(height: 16),
          // Блок сервера
          Text(
            loc.serverSettings,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${authProvider.serverHost}:${authProvider.serverPort}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF424242)),
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
            foregroundColor: const Color(0xFFdc2626),
          ),
          child: Text(loc.logoutAction),
        ),
      ],
    ),
  );
}
