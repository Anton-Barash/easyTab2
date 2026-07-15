import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// API client for easyTab server.
///
/// Адрес сервера настраивается через [setBaseUrl] — вызывается AuthProvider'ом
/// при инициализации и при смене адреса пользователем.
class ApiService {
  static String _host = 'localhost';
  static int _port = 3000;

  static const Duration _timeout = Duration(seconds: 15);

  /// Установить адрес/порт сервера.
  static void setBaseUrl(String host, int port) {
    _host = host;
    _port = port;
  }

  static String get baseUrl => '$_host:$_port';

  static Uri _uri(String path) {
    return Uri.http('$_host:$_port', path);
  }

  /// Токен авторизации (устанавливается AuthProvider'ом после входа).
  static String? authToken;

  /// Заголовки для JSON-запросов (с токеном авторизации).
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  /// Заголовки для multipart-запросов (только токен, без Content-Type —
  /// его установит MultipartRequest с boundary).
  static Map<String, String> get _authHeaders => {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  /// Регистрация нового пользователя.
  /// Возвращает {success, user?, token?, error?}
  static Future<ApiResult> register({
    required String username,
    required String password,
    String? email,
    String? name,
  }) async {
    try {
      final response = await http
          .post(
            _uri('/auth/register'),
            headers: _headers,
            body: jsonEncode({
              'username': username,
              'password': password,
              if (email != null && email.isNotEmpty) 'email': email,
              if (name != null && name.isNotEmpty) 'name': name,
            }),
          )
          .timeout(_timeout);

      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Вход по логину/паролю.
  static Future<ApiResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            _uri('/auth/login'),
            headers: _headers,
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(_timeout);

      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить текущего пользователя по токену.
  static Future<ApiResult> me() async {
    try {
      final response = await http
          .get(_uri('/auth/me'), headers: _headers)
          .timeout(_timeout);

      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Проверка доступности сервера (health check).
  /// Возвращает true, если сервер ответил 200.
  static Future<bool> ping() async {
    try {
      final response = await http
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // Методы для работы с файлами (/files)
  // ============================================================

  /// Загрузить один файл на сервер (multipart/form-data).
  ///
  /// [filePath] — абсолютный путь к файлу на устройстве.
  /// [relativePath] — путь внутри папки отчёта (например "media/photo1.jpg").
  ///
  /// Возвращает ApiResult с данными файла в [data] при успехе.
  static Future<ApiResult> uploadFile({
    required String filePath,
    required String relativePath,
  }) async {
    try {
      // Получаем имя файла из пути
      final fileName = filePath.split(Platform.pathSeparator).last;

      // Создаём multipart-запрос
      final request = http.MultipartRequest('POST', _uri('/files/upload'));
      request.headers.addAll(_authHeaders);

      // Добавляем файл
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: fileName,
        ),
      );

      // Добавляем относительный путь (для сохранения структуры папок)
      request.fields['relativePath'] = relativePath;

      // Отправляем с увеличенным таймаутом (файлы могут быть большими)
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка загрузки: $e');
    }
  }

  /// Загрузить файл из памяти (байты) на сервер.
  ///
  /// Используется на web, где нет локального файла — только байты в памяти.
  /// [bytes] — содержимое файла.
  /// [filename] — имя файла (например, 'report.html').
  /// [relativePath] — путь внутри папки отчёта.
  ///
  /// Возвращает ApiResult с данными файла в [data]['file'] (включая id).
  static Future<ApiResult> uploadFileFromBytes({
    required Uint8List bytes,
    required String filename,
    required String relativePath,
    int? reportId,
    String? ks3Folder,
  }) async {
    try {
      final request = http.MultipartRequest('POST', _uri('/files/upload'));
      request.headers.addAll(_authHeaders);

      // Определяем MIME-тип по расширению
      final ext = filename.split('.').last.toLowerCase();
      String mimeType = 'application/octet-stream';
      if (ext == 'html' || ext == 'htm') mimeType = 'text/html';
      else if (ext == 'json') mimeType = 'application/json';
      else if (ext == 'xlsx') mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      else if (ext == 'png') mimeType = 'image/png';
      else if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
      else if (ext == 'mp4') mimeType = 'video/mp4';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      );

      request.fields['relativePath'] = relativePath;
      // Если есть reportId и ks3Folder — файл привяжется к отчёту
      if (reportId != null) {
        request.fields['reportId'] = reportId.toString();
      }
      if (ks3Folder != null) {
        request.fields['ks3Folder'] = ks3Folder;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка загрузки: $e');
    }
  }

  /// Загрузить несколько файлов на сервер.
  ///
  /// [files] — список карт с ключами:
  ///   'filePath' — абсолютный путь к файлу
  ///   'relativePath' — путь внутри папки отчёта
  ///
  /// [onProgress] — callback для отслеживания прогресса (currentIndex, totalCount).
  ///
  /// Возвращает ApiResult с массивом результатов в [data].
  static Future<ApiResult> uploadFiles({
    required List<Map<String, String>> files,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <Map<String, dynamic>>[];
    var successCount = 0;

    for (var i = 0; i < files.length; i++) {
      onProgress?.call(i + 1, files.length);

      final result = await uploadFile(
        filePath: files[i]['filePath']!,
        relativePath: files[i]['relativePath']!,
      );

      if (result.success) {
        successCount++;
        results.add({
          'relativePath': files[i]['relativePath'],
          'success': true,
          'file': result.data?['file'],
        });
      } else {
        results.add({
          'relativePath': files[i]['relativePath'],
          'success': false,
          'error': result.error,
        });
      }
    }

    return ApiResult(
      success: successCount > 0,
      data: {
        'results': results,
        'total': files.length,
        'successCount': successCount,
        'failedCount': files.length - successCount,
      },
      error: successCount == 0 ? 'Не удалось загрузить ни одного файла' : null,
    );
  }

  /// Получить список всех файлов пользователя на сервере.
  static Future<ApiResult> listFiles() async {
    try {
      final response = await http
          .get(_uri('/files'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить подписанный URL для скачивания/просмотра файла.
  ///
  /// [fileId] — UUID файла на сервере.
  /// Возвращает ApiResult с URL в [data]['url'].
  static Future<ApiResult> getDownloadUrl(String fileId) async {
    try {
      final response = await http
          .get(_uri('/files/$fileId/download'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить список файлов, привязанных к отчёту.
  ///
  /// [reportId] — ID отчёта на сервере.
  /// Возвращает ApiResult с data['files'] — массив файлов.
  static Future<ApiResult> listFilesByReport(int reportId) async {
    try {
      final response = await http
          .get(_uri('/files/by-report/$reportId'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить подписанные URL для всех файлов отчёта.
  ///
  /// [reportId] — ID отчёта на сервере.
  /// Возвращает ApiResult с data['urls'] — объект { 'photos/f1_1.jpg': 'https://...', ... }.
  static Future<ApiResult> getReportFileUrls(int reportId) async {
    try {
      final response = await http
          .get(_uri('/files/by-report/$reportId/urls'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Удалить файл на сервере.
  ///
  /// [fileId] — UUID файла на сервере.
  static Future<ApiResult> deleteFile(String fileId) async {
    try {
      final response = await http
          .delete(_uri('/files/$fileId'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  // ============================================================
  // Методы для работы с отчётами (/reports)
  // Используются на web, где нет локальной файловой системы.
  // ============================================================

  /// Сохранить отчёт на сервере (создать новый или обновить).
  ///
  /// [title] — название отчёта.
  /// [reportData] — JSON-объект отчёта (Map).
  /// [reportId] — ID существующего отчёта (для обновления), null для нового.
  ///
  /// Возвращает ApiResult с data['report']['id'] — ID отчёта на сервере.
  static Future<ApiResult> saveReport({
    required String title,
    required Map<String, dynamic> reportData,
    int? reportId,
  }) async {
    try {
      final body = jsonEncode({
        'title': title,
        'reportData': reportData,
        if (reportId != null) 'reportId': reportId,
      });

      final response = await http
          .post(_uri('/reports'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 30));
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить список отчётов пользователя с сервера.
  ///
  /// Возвращает ApiResult с data['reports'] — массив метаданных.
  static Future<ApiResult> listReports() async {
    try {
      final response = await http
          .get(_uri('/reports'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить полный JSON отчёта по ID.
  ///
  /// [reportId] — ID отчёта на сервере.
  /// Возвращает ApiResult с data['report']['reportData'] — JSON отчёта.
  static Future<ApiResult> getReport(int reportId) async {
    try {
      final response = await http
          .get(_uri('/reports/$reportId'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Удалить отчёт на сервере.
  ///
  /// [reportId] — ID отчёта.
  static Future<ApiResult> deleteReport(int reportId) async {
    try {
      final response = await http
          .delete(_uri('/reports/$reportId'), headers: _headers)
          .timeout(_timeout);
      return _parseResponse(response);
    } on SocketException {
      return ApiResult(success: false, error: 'Нет соединения с сервером');
    } catch (e) {
      return ApiResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  static ApiResult _parseResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult(
          success: body['success'] == true,
          data: body,
          token: body['token'] as String?,
          user: body['user'] as Map<String, dynamic>?,
          error: body['success'] == true
              ? null
              : (body['error'] as String?) ?? 'Неизвестная ошибка',
        );
      }

      return ApiResult(
        success: false,
        error: (body['error'] as String?) ?? 'Ошибка ${response.statusCode}',
      );
    } catch (e) {
      return ApiResult(
        success: false,
        error: 'Некорректный ответ сервера: ${response.statusCode}',
      );
    }
  }
}

/// Результат вызова API.
class ApiResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  ApiResult({
    required this.success,
    this.data,
    this.token,
    this.user,
    this.error,
  });
}
