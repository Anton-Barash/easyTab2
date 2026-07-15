import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String? _userToken;
  String? _username;
  String? _email;
  int? _userId;
  String? _lastError;
  String _serverHost = 'localhost';
  int _serverPort = 3000;

  static const String _tokenKey = 'user_token';
  static const String _usernameKey = 'user_name';
  static const String _emailKey = 'user_email';
  static const String _userIdKey = 'user_id';
  static const String _serverHostKey = 'server_host';
  static const String _serverPortKey = 'server_port';

  bool get isLoggedIn => _isLoggedIn;
  String? get userToken => _userToken;
  String? get username => _username;
  String? get email => _email;
  int? get userId => _userId;
  String? get lastError => _lastError;
  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get serverUrl => '$_serverHost:$_serverPort';

  /// Инициализация: восстановление сохранённого токена и адреса сервера.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _userToken = prefs.getString(_tokenKey);
    _username = prefs.getString(_usernameKey);
    _email = prefs.getString(_emailKey);
    _userId = prefs.getInt(_userIdKey);
    _serverHost = prefs.getString(_serverHostKey) ?? 'localhost';
    _serverPort = prefs.getInt(_serverPortKey) ?? 3000;
    _isLoggedIn = _userToken != null && _userToken!.isNotEmpty;

    // Применяем сохранённый адрес сервера и токен к API-клиенту.
    ApiService.setBaseUrl(_serverHost, _serverPort);
    ApiService.authToken = _userToken;

    // Если есть сохранённый токен — проверяем его на сервере.
    if (_isLoggedIn) {
      await _verifyToken();
    }

    notifyListeners();
  }

  /// Установить адрес сервера. Сохраняется в SharedPreferences.
  Future<void> setServerUrl(String host, int port) async {
    _serverHost = host;
    _serverPort = port;
    ApiService.setBaseUrl(host, port);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverHostKey, host);
    await prefs.setInt(_serverPortKey, port);
    notifyListeners();
  }

  /// Проверить связь с сервером. Возвращает true, если сервер ответил.
  Future<bool> testConnection() async {
    return await ApiService.ping();
  }

  /// Проверка сохранённого токена на сервере.
  /// Если токен просрочен/невалиден — выходим.
  Future<void> _verifyToken() async {
    final result = await ApiService.me();
    if (result.success && result.user != null) {
      _username = result.user!['username'] as String?;
      _email = result.user!['email'] as String?;
      _userId = _toInt(result.user!['id']);

      final prefs = await SharedPreferences.getInstance();
      if (_username != null) await prefs.setString(_usernameKey, _username!);
      if (_email != null) await prefs.setString(_emailKey, _email!);
      if (_userId != null) await prefs.setInt(_userIdKey, _userId!);
    } else {
      // Токен невалиден — очищаем.
      await _clearStored();
    }
  }

  /// Вход по логину/паролю.
  /// Возвращает true при успехе, false при ошибке (см. lastError).
  Future<bool> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      _lastError = 'Введите имя пользователя и пароль';
      notifyListeners();
      return false;
    }

    final result = await ApiService.login(
      username: username.trim(),
      password: password,
    );

    if (result.success && result.token != null) {
      _userToken = result.token;
      _username = result.user?['username'] as String? ?? username.trim();
      _email = result.user?['email'] as String?;
      _userId = _toInt(result.user?['id']);
      _isLoggedIn = true;
      _lastError = null;

      ApiService.authToken = _userToken;
      await _persist();
      notifyListeners();
      return true;
    }

    _lastError = result.error ?? 'Ошибка входа';
    notifyListeners();
    return false;
  }

  /// Регистрация нового пользователя.
  /// Возвращает true при успехе, false при ошибке (см. lastError).
  Future<bool> register(
    String username,
    String password, {
    String? email,
    String? name,
  }) async {
    if (username.isEmpty || password.isEmpty) {
      _lastError = 'Введите имя пользователя и пароль';
      notifyListeners();
      return false;
    }

    final result = await ApiService.register(
      username: username.trim(),
      password: password,
      email: email?.trim().isEmpty ?? true ? null : email!.trim(),
      name: name?.trim().isEmpty ?? true ? null : name!.trim(),
    );

    if (result.success && result.token != null) {
      _userToken = result.token;
      _username = result.user?['username'] as String? ?? username.trim();
      _email = result.user?['email'] as String?;
      _userId = _toInt(result.user?['id']);
      _isLoggedIn = true;
      _lastError = null;

      ApiService.authToken = _userToken;
      await _persist();
      notifyListeners();
      return true;
    }

    _lastError = result.error ?? 'Ошибка регистрации';
    notifyListeners();
    return false;
  }

  /// Выход: очистка сохранённых данных и токена.
  Future<void> logout() async {
    await _clearStored();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userToken != null) await prefs.setString(_tokenKey, _userToken!);
    if (_username != null) await prefs.setString(_usernameKey, _username!);
    if (_email != null) await prefs.setString(_emailKey, _email!);
    if (_userId != null) await prefs.setInt(_userIdKey, _userId!);
  }

  Future<void> _clearStored() async {
    _isLoggedIn = false;
    _userToken = null;
    _username = null;
    _email = null;
    _userId = null;

    ApiService.authToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_userIdKey);
  }

  /// Безопасно конвертирует значение в int? (для JSON с web, где числа могут быть String).
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is num) return value.toInt();
    return null;
  }
}
