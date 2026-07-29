import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_result.dart';

Future<ApiResult> uploadFileFromBytesWithProgress({
  required Uri uri,
  required Uint8List bytes,
  required String filename,
  required String relativePath,
  required Map<String, String> headers,
  int? reportId,
  String? ks3Folder,
  void Function(double progress)? onUploadProgress,
}) async {
  try {
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);

    final ext = filename.split('.').last.toLowerCase();
    String mimeType = 'application/octet-stream';
    if (ext == 'html' || ext == 'htm') {
      mimeType = 'text/html';
    } else if (ext == 'json') {
      mimeType = 'application/json';
    } else if (ext == 'xlsx') {
      mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    } else if (ext == 'png') {
      mimeType = 'image/png';
    } else if (ext == 'jpg' || ext == 'jpeg') {
      mimeType = 'image/jpeg';
    } else if (ext == 'mp4') {
      mimeType = 'video/mp4';
    }

    request.fields['relativePath'] = relativePath;
    if (reportId != null) {
      request.fields['reportId'] = reportId.toString();
    }
    if (ks3Folder != null) {
      request.fields['ks3Folder'] = ks3Folder;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    );

    onUploadProgress?.call(0.1);
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 300),
    );
    final response = await http.Response.fromStream(streamedResponse);
    onUploadProgress?.call(1.0);

    return _parseResponse(response);
  } on SocketException {
    return const ApiResult(success: false, error: 'Нет соединения с сервером');
  } catch (e) {
    return ApiResult(success: false, error: 'Ошибка загрузки: $e');
  }
}

ApiResult _parseResponse(http.Response response) {
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
