import 'dart:async';
import 'dart:convert';

import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
// share_plus (~50-80 KB) нужен только при экспорте ZIP — deferred.
import 'package:share_plus/share_plus.dart' deferred as share_plus;
import '../models/report_models.dart';
import '../services/api_service.dart';
import '../services/report_merge_service.dart';
// Тяжёлые сервисы (Excel/Sync/HTML/ZIP, видео-очередь, сжатие видео,
// генерация превью) загружаются лениво (deferred) — они нужны только
// на экране заполнения отчёта (form_fill), а не на старте.
// Каждый станет отдельным чанком, подгружаемым при первом использовании.
import '../services/report_excel_service.dart' deferred as excel_service;
import '../services/report_html_service.dart' deferred as html_service;
import '../services/report_sync_service.dart' deferred as sync_service;
import '../services/project_zip_service.dart' deferred as zip_service;
import '../services/native_video_compress_service.dart'
    deferred as native_compress;
import '../services/share_token_storage.dart';
import '../services/api_result.dart';
import '../services/anonymous_id_service.dart';
import '../services/mime_utils.dart';
import '../services/upload_helper.dart';
// Пакет image (~0.5 MB) нужен только при добавлении фото — deferred.
import '../utils/image_compressor.dart' deferred as image_compressor;
import '../services/video_upload_queue.dart' deferred as video_upload_queue;
import '../utils/video_thumbnail_generator.dart' deferred as thumbnail_gen;

const String reportFilename = 'report.json';
const String exportDir = 'reports';

class ReportInfo {
  final String folderName;
  final String name;
  final DateTime dateTime;
  final String? thumbnailPath;
  final String? publicId;

  ReportInfo({
    required this.folderName,
    required this.name,
    required this.dateTime,
    this.thumbnailPath,
    this.publicId,
  });
}

/// Действие, выбранное пользователем при конфликте версий (409).
enum ConflictAction { reload, overwrite, resolved }

/// Результат попытки сохранения через ops-PATCH (merge-by-ID).
enum _OpsSaveResult { saved, fallbackLegacy, failed }

/// Конфликт одного ответа/ячейки: два пользователя изменили один и тот же
/// подответ. При новом (merge-by-ID) контракте сервер возвращает qid/rid/lang,
/// клиент транслирует их в позиционные индексы для существующего UI-диалога.
class AnswerConflict {
  final int questionIndex;
  final int answerIndex;
  final String language;

  /// Стабильные id из нового 409-формата (merge-by-ID).
  final String? qid;
  final String? rid;
  final String? field;

  final String serverText;
  final String clientText;
  final int? clientUpdatedAt;
  final int? serverUpdatedAt;

  /// Кто последним правил ячейку на сервере (автор чужой правки).
  /// Используется, чтобы показать пользователю, чей вариант он видит.
  final String? serverAuthor;

  AnswerConflict({
    required this.questionIndex,
    required this.answerIndex,
    required this.language,
    required this.serverText,
    required this.clientText,
    this.qid,
    this.rid,
    this.field,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    this.serverAuthor,
  });
}

/// Детали конфликта, передаваемые в UI для разрешения.
class ConflictDetails {
  final int currentVersion;
  final List<AnswerConflict> answerConflicts;

  /// true — конфликт по той же ячейке возник повторно: пока пользователь
  /// выбирал вариант, ячейку успел изменить ещё кто-то. UI показывает
  /// отдельное сообщение «ответ был изменён снова».
  final bool isRepeat;

  ConflictDetails({
    required this.currentVersion,
    required this.answerConflicts,
    this.isRepeat = false,
  });
}

/// Метаданные активной share-ссылки отчёта (из listShareLinks).
class ShareLinkInfo {
  final String token;
  final String url;
  final DateTime? expiresAt;
  final bool isActive;
  final String permissions;
  final DateTime? createdAt;

  ShareLinkInfo({
    required this.token,
    required this.url,
    this.expiresAt,
    this.isActive = true,
    this.permissions = 'edit',
    this.createdAt,
  });
}

class ReportState extends ChangeNotifier {
  /// Включает ops-путь сохранения (merge-by-ID, Фаза 2b).
  /// Сервер реализует ops-контракт (PATCH /reports/:id и /reports/shares/:token),
  /// поэтому включено: параллельные правки сливаются по-cell, а конфликт одной
  /// ячейки показывает диалог выбора. При 400/404/405 или отсутствии `merged`
  /// клиент автоматически откатывается на legacy-путь (см. фолбэк ниже).
  static const bool mergeOpsEnabled = true;

  Report? _currentReport;
  String? _currentReportPath;

  /// Версия отчёта на сервере (optimistic locking).
  int? _serverReportVersion;

  /// Снимок отчёта при открытии (для PATCH/merge на сервере).
  Map<String, dynamic>? _baseReportSnapshot;

  /// true, если текущий сервер не понимает ops-PATCH — используем legacy-путь.
  bool _mergeOpsUnsupported = false;

  /// Причина последней неудачной операции сохранения/синхронизации.
  /// Нужна, чтобы показывать пользователю конкретную ошибку (401/409/500/сеть)
  /// вместо безликого «ошибка синхронизации».
  String? _lastSyncError;

  // ===== Параметры компрессии медиа (из настроек) =====
  // Значения по умолчанию — ТЗ: 1500px / 85%, видео — low (level 3).
  int _imageMaxSize = 1500;
  int _imageJpegQuality = 85;
  int _videoQualityLevel = 3;

  /// Текущие параметры компрессии фото (max px по стороне).
  int get imageMaxSize => _imageMaxSize;

  /// Текущие параметры компрессии фото (JPEG quality 0..100).
  int get imageJpegQuality => _imageJpegQuality;

  /// Текущий уровень качества видео (1 high / 2 medium / 3 low).
  int get videoQualityLevel => _videoQualityLevel;

  /// Применить настройки качества медиа. Вызывается из Settings UI
  /// (LoginScreen при инициализации и при смене значений).
  void applyMediaQualitySettings({
    required int imageMaxSize,
    required int imageJpegQuality,
    required int videoQualityLevel,
  }) {
    _imageMaxSize = imageMaxSize;
    _imageJpegQuality = imageJpegQuality;
    _videoQualityLevel = videoQualityLevel;
    notifyListeners();
  }

  // ============================================================
  // Attachments — произвольные файлы (не фото/видео), ≤55 MB.
  // Не сжимаются. Хранятся в Report.attachments, привязаны к
  // конкретному questionIndex / answerIndex.
  // ============================================================

  /// Максимальный размер attachment (55 MB).
  static const int kMaxAttachmentBytes = 55 * 1024 * 1024;

  /// Все attachments текущего отчёта.
  List<Attachment> get attachments =>
      _currentReport?.attachments ?? const <Attachment>[];

  /// Attachments для конкретного вопроса.
  List<Attachment> attachmentsForQuestion(int questionIndex) =>
      attachments.where((a) => a.questionIndex == questionIndex).toList();

  /// Количество attachments текущего отчёта (для бейджа на скрепке).
  int get attachmentsCount => attachments.length;

  /// Количество attachments для конкретного ответа.
  int attachmentsCountForAnswer(int questionIndex, int answerIndex) =>
      attachments
          .where(
            (a) =>
                a.questionIndex == questionIndex &&
                a.answerIndex == answerIndex,
          )
          .length;

  /// Добавить attachment на web (из байтов).
  /// Автоматически загружает на сервер (presigned PUT на web / multipart на native).
  Future<bool> addAttachmentFromBytes({
    required int questionIndex,
    required int answerIndex,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final report = _currentReport;
    if (report == null) return false;

    if (bytes.length > kMaxAttachmentBytes) {
      if (kDebugMode) {
        debugPrint(
          'Attachment too large: $fileName (${bytes.length} bytes > $kMaxAttachmentBytes)',
        );
      }
      return false;
    }

    final id =
        'att_${DateTime.now().millisecondsSinceEpoch}_'
        '${attachments.length}';
    final attachment = Attachment(
      id: id,
      questionIndex: questionIndex,
      answerIndex: answerIndex,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      webBytes: bytes,
    );
    report.attachments.add(attachment);
    notifyListeners();

    // Загружаем на сервер (без компрессии).
    await _uploadAttachmentToServer(
      attachment,
      bytes,
      fileName,
      'attachments/$fileName',
      mimeType,
    );
    return attachment.serverFileId != null;
  }

  /// Добавить attachment на native (из пути файла).
  /// Читает байты и вызывает [_uploadAttachmentToServer].
  Future<bool> addAttachmentFromFile({
    required int questionIndex,
    required int answerIndex,
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    final report = _currentReport;
    if (report == null) return false;

    Uint8List bytes;
    try {
      bytes = await File(filePath).readAsBytes();
    } catch (e) {
      if (kDebugMode) debugPrint('Attachment read error: $filePath — $e');
      return false;
    }

    if (bytes.length > kMaxAttachmentBytes) {
      if (kDebugMode) {
        debugPrint(
          'Attachment too large: $fileName (${bytes.length} bytes > $kMaxAttachmentBytes)',
        );
      }
      return false;
    }

    final id =
        'att_${DateTime.now().millisecondsSinceEpoch}_'
        '${attachments.length}';
    final attachment = Attachment(
      id: id,
      questionIndex: questionIndex,
      answerIndex: answerIndex,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      localPath: filePath,
    );
    report.attachments.add(attachment);
    notifyListeners();

    await _uploadAttachmentToServer(
      attachment,
      bytes,
      fileName,
      'attachments/$fileName',
      mimeType,
    );
    return attachment.serverFileId != null;
  }

  /// Загрузить attachment на сервер (аналог _uploadMediaToServer, но без
  /// компрессии и без генерации превью).
  Future<void> _uploadAttachmentToServer(
    Attachment attachment,
    Uint8List bytes,
    String fileName,
    String relativePath,
    String mimeType,
  ) async {
    if (attachment.isUploading) return;
    attachment.isUploading = true;
    attachment.uploadProgress = 0.0;
    notifyListeners();

    try {
      ApiResult result;
      if (kIsWeb) {
        // Используем presigned PUT как для медиа — консистентно.
        // _uploadViaPresignedUrl требует MediaItem; для attachment используем
        // общий presign+PUT+confirm напрямую.
        result = await _uploadAttachmentViaPresigned(
          attachment: attachment,
          bytes: bytes,
          fileName: fileName,
          relativePath: relativePath,
          mimeType: mimeType,
        );
      } else {
        result = await ApiService.uploadFileFromBytes(
          bytes: bytes,
          filename: fileName,
          relativePath: relativePath,
          reportId: _serverReportId,
          onUploadProgress: (progress) {
            attachment.uploadProgress = progress;
            notifyListeners();
          },
        );
      }

      if (result.success && result.data?['file'] != null) {
        final fileId = result.data!['file']['id'];
        if (fileId is String) {
          attachment.serverFileId = fileId;
          attachment.uploadProgress = 1.0;
          // После успешной загрузки очищаем webBytes (экономим память на web).
          attachment.webBytes = null;
          notifyListeners();
        }
      } else if (kDebugMode) {
        debugPrint('Attachment upload failed: $fileName — ${result.error}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Attachment upload error: $fileName — $e');
    } finally {
      attachment.isUploading = false;
      notifyListeners();
    }
  }

  /// Presigned-загрузка attachment (web only) — тот же flow, что и для медиа,
  /// но без MediaItem.
  Future<ApiResult> _uploadAttachmentViaPresigned({
    required Attachment attachment,
    required Uint8List bytes,
    required String fileName,
    required String relativePath,
    required String mimeType,
  }) async {
    final isShare = _shareToken != null && _shareToken!.isNotEmpty;

    final ApiResult presignResult;
    if (isShare) {
      presignResult = await ApiService.presignUploadForShare(
        fileName: fileName,
        shareToken: _shareToken!,
        relativePath: relativePath,
        reportId: _serverReportId,
      );
    } else {
      presignResult = await ApiService.presignUpload(
        fileName: fileName,
        relativePath: relativePath,
        reportId: _serverReportId,
      );
    }
    if (!presignResult.success) return presignResult;

    final uploadUrl = presignResult.data!['uploadUrl'] as String;
    final fileId = presignResult.data!['fileId'] as String;
    final storageKey = presignResult.data!['storageKey'] as String;
    final serverMimeType =
        presignResult.data!['mimeType'] as String? ?? mimeType;
    final relPath = presignResult.data!['relPath'] as String? ?? relativePath;

    final uploadResult = await uploadToPresignedUrl(
      uploadUrl: uploadUrl,
      bytes: bytes,
      onUploadProgress: (progress) {
        attachment.uploadProgress = progress;
        notifyListeners();
      },
    );
    if (uploadResult != true) {
      return ApiResult(success: false, error: uploadResult.toString());
    }

    if (isShare) {
      return ApiService.confirmUploadForShare(
        fileId: fileId,
        storageKey: storageKey,
        fileName: fileName,
        size: bytes.length,
        mimeType: serverMimeType,
        relPath: relPath,
        shareToken: _shareToken!,
      );
    }
    return ApiService.confirmUpload(
      fileId: fileId,
      storageKey: storageKey,
      fileName: fileName,
      size: bytes.length,
      mimeType: serverMimeType,
      relPath: relPath,
    );
  }

  /// Удалить attachment (с сервера + из списка).
  Future<bool> removeAttachment(String attachmentId) async {
    final report = _currentReport;
    if (report == null) return false;

    final idx = report.attachments.indexWhere((a) => a.id == attachmentId);
    if (idx < 0) return false;
    final attachment = report.attachments[idx];

    // Удаляем с сервера, если был загружен.
    if (attachment.serverFileId != null) {
      final res = await ApiService.deleteFile(attachment.serverFileId!);
      if (!res.success && kDebugMode) {
        debugPrint(
          'Attachment delete server error: ${attachment.fileName} — ${res.error}',
        );
      }
    }

    // Удаляем локальный файл (native), если есть.
    if (!kIsWeb && attachment.localPath != null) {
      try {
        final f = File(attachment.localPath!);
        if (await f.exists()) await f.delete();
      } catch (e) {
        if (kDebugMode) debugPrint('Attachment local delete error: $e');
      }
    }

    report.attachments.removeAt(idx);
    notifyListeners();
    return true;
  }

  /// Получить URL для открытия/скачивания attachment.
  /// На web сначала пробуем webUrl (presigned из getReportFileUrls),
  /// иначе запрашиваем через getDownloadUrl.
  Future<String?> getAttachmentUrl(Attachment attachment) async {
    if (attachment.webUrl != null && attachment.webUrl!.isNotEmpty) {
      return attachment.webUrl;
    }
    if (attachment.serverFileId == null) return null;
    final res = await ApiService.getDownloadUrl(attachment.serverFileId!);
    if (res.success) {
      final url = res.data?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        attachment.webUrl = url;
        return url;
      }
    }
    return null;
  }

  /// Фоновая очередь сжатия и загрузки видео (web only).
  ///
  /// Создаётся лениво при первом enqueue: очередь тянет за собой
  /// ffmpeg.wasm-обвязку и не должна входить в основной бандл.
  ///
  /// Тип dynamic: deferred-тип (VideoUploadQueue) нельзя использовать
  /// в объявлениях полей — только после loadLibrary() в рантайме.
  dynamic _videoQueue;
  StreamSubscription<dynamic>? _videoProgressSub;

  /// Ленивая инициализация видео-очереди (deferred chunk).
  Future<dynamic> _getVideoQueue() async {
    if (_videoQueue == null) {
      await video_upload_queue.loadLibrary();
      final queue = video_upload_queue.VideoUploadQueue();
      _videoProgressSub = queue.progressStream.listen((_) {
        // Прогресс хранится внутри MediaItem; UI сам его отрисовывает.
        notifyListeners();
        _flushPendingDeletions();
      });
      _videoQueue = queue;
    }
    return _videoQueue!;
  }

  /// Медиа, которые нужно удалить с сервера после завершения фоновой
  /// обработки. Используется в removeQuestion/removeAnswer/removeMedia,
  /// когда пользователь удаляет медиа, которое в данный момент сжимается
  /// или загружается.
  final Set<MediaItem> _pendingDeletion = <MediaItem>{};

  /// Пути видео, уже сжатых в этой сессии (native), чтобы не сжимать
  /// повторно. Очищается при загрузке отчёта (в [_sanitizeMediaState]).
  final Set<String> _compressedVideoPaths = {};

  ReportState();

  Report? get currentReport => _currentReport;
  String? get currentReportPath => _currentReportPath;

  /// Флаг загрузки фото шапки (для индикатора в UI).
  bool _isUploadingHeader = false;
  bool get isUploadingHeader => _isUploadingHeader;

  /// Создать новый отчёт по шаблону.
  ///
  /// Инициализирует структуру вопросов, переводов и маркеров.
  /// Сбрасывает серверные идентификаторы — новый отчёт ещё не сохранён.
  void newReport(
    String name,
    List<Question> questions,
    List<String> languages, {
    String productType = 'Аэрогриль',
    String factory = '',
    String model = '',
    String? headerImagePath,
  }) {
    final now = DateTime.now();
    _currentReport = Report(
      reportName: name,
      availableLanguages: languages,
      currentLanguage: languages.isNotEmpty ? languages[0] : 'RU',
      questions: questions,
      translations: {},
      markers: {},
      mediaCounter: {'photos': 1, 'X': 1},
      timestamp: now.millisecondsSinceEpoch,
      productType: productType,
      factory: factory,
      model: model,
      dateTimestamp: now.millisecondsSinceEpoch,
      headerImagePath: headerImagePath,
    );
    for (int i = 0; i < questions.length; i++) {
      // Новые отчёты не пре-создают пустых ответов: строка ввода в UI
      // остаётся «фантомной», а ответ (id + rowId) создаётся только при
      // первом введённом символе (см. updateAnswerText). Это исключает
      // затирание одновременных правок одного и того же ответа с разных
      // устройств — каждый ряд получает свежий rowId при первой записи.
      _currentReport!.translations[i.toString()] = {};
      _currentReport!.markers[i.toString()] = [];
      for (final lang in languages) {
        _currentReport!.translations[i.toString()]![lang] = [];
      }
    }
    _currentReportPath = null;
    // Сбрасываем ID отчёта на сервере — это новый отчёт
    _serverReportId = null;
    _serverReportVersion = null;
    // База для diff-движка (Фаза 2): документ в том виде, в котором он создан.
    _baseReportSnapshot = _currentReport?.toJson();
    _serverPublicId = null;
    _ks3Folder = null;
    notifyListeners();
  }

  void setLanguage(String langCode) {
    if (_currentReport == null) return;
    if (_currentReport!.availableLanguages.contains(langCode)) {
      _currentReport!.currentLanguage = langCode;
      notifyListeners();
    }
  }

  void updateHeaderInfo({
    String? productType,
    String? factory,
    String? model,
    int? dateTimestamp,
  }) {
    if (_currentReport == null) return;
    if (productType != null) _currentReport!.productType = productType;
    if (factory != null) _currentReport!.factory = factory;
    if (model != null) _currentReport!.model = model;
    if (dateTimestamp != null) _currentReport!.dateTimestamp = dateTimestamp;
    updateReportName();
    notifyListeners();
  }

  void updateReportName() {
    if (_currentReport == null) return;
    final productType = _currentReport!.productType.isNotEmpty
        ? '(${_currentReport!.productType})'
        : '';
    final factory = _currentReport!.factory.isNotEmpty
        ? '${_currentReport!.factory} '
        : '';
    final model = _currentReport!.model.isNotEmpty ? _currentReport!.model : '';
    _currentReport!.reportName = '$factory$productType $model'.trim();
    notifyListeners();
  }

  Future<void> addHeaderImage(File file) async {
    if (_currentReport == null) return;

    _isUploadingHeader = true;
    notifyListeners();

    try {
      if (_currentReportPath == null) {
        final folderPath = await _generateFolderName();
        _currentReportPath = folderPath;
        final folder = Directory(folderPath);
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        await Directory('$folderPath/photos').create(recursive: true);
        await Directory('$folderPath/X').create(recursive: true);
      }

      final ext = file.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'header_$timestamp.$ext';
      final destPath = File('$_currentReportPath/$fileName');

      if (_currentReport!.headerImagePath != null) {
        final oldFilePath = File(
          '$_currentReportPath/${_currentReport!.headerImagePath}',
        );
        if (await oldFilePath.exists()) {
          await oldFilePath.delete();
        }
      }

      final mimeType = mimeTypeFromFilename(file.path);
      if (mimeType.startsWith('image/')) {
        final bytes = await file.readAsBytes();
        await image_compressor.loadLibrary();
        final compressed = image_compressor.ImageCompressor.compress(
          Uint8List.fromList(bytes),
          _imageMaxSize,
          jpegQuality: _imageJpegQuality,
        );
        await destPath.writeAsBytes(compressed);
      } else {
        await file.copy(destPath.path);
      }

      _currentReport!.headerImagePath = fileName;
    } finally {
      _isUploadingHeader = false;
      notifyListeners();
    }
  }

  /// Добавить фото шапки из байтов (для web-версии).
  ///
  /// Байты сохраняются в памяти и загружаются при следующем saveReport().
  Future<void> addHeaderImageFromBytes(Uint8List bytes, String fileName) async {
    if (_currentReport == null) return;

    // Сжимаем изображение (deferred-чанк с пакетом image).
    await image_compressor.loadLibrary();
    final compressed = image_compressor.ImageCompressor.compress(
      bytes,
      _imageMaxSize,
      jpegQuality: _imageJpegQuality,
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = fileName.split('.').last;
    final generatedName = 'header_$timestamp.$ext';

    // На web: сохраняем байты в webBytes, загрузим при saveReport
    // На native: сохраняем файл на диск (если есть _currentReportPath)
    if (kIsWeb) {
      _currentReport!.headerImagePath = generatedName;
      // Сохраняем байты в отчёте для последующей загрузки
      // (используем временное хранилище через webBytes в MediaItem-совместимом формате)
      _headerImageBytes = compressed;
      _headerImageFileName = generatedName;
    } else {
      if (_currentReportPath == null) {
        final folderPath = await _generateFolderName();
        _currentReportPath = folderPath;
        final folder = Directory(folderPath);
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        await Directory('$folderPath/photos').create(recursive: true);
        await Directory('$folderPath/X').create(recursive: true);
      }

      // Удаляем старое фото
      if (_currentReport!.headerImagePath != null) {
        final oldFilePath = File(
          '$_currentReportPath/${_currentReport!.headerImagePath}',
        );
        if (await oldFilePath.exists()) {
          await oldFilePath.delete();
        }
      }

      final destPath = File('$_currentReportPath/$generatedName');
      await destPath.writeAsBytes(compressed);
      _currentReport!.headerImagePath = generatedName;
    }

    notifyListeners();
  }

  // Временное хранилище байтов фото шапки (для web)
  Uint8List? _headerImageBytes;
  String? _headerImageFileName;

  // Ограничение одновременных загрузок медиа на web: много параллельных
  // PUT в KS3 даёт пики памяти и трафика. Фото загружаются с максимальной
  // степенью параллелизма _maxConcurrentWebMediaUploads.
  static const int _maxConcurrentWebMediaUploads = 3;
  int _runningWebMediaUploads = 0;
  final List<Completer<void>> _webMediaUploadWaiters = [];

  Future<void> removeHeaderImage() async {
    if (_currentReport == null) return;
    if (_currentReportPath != null && _currentReport!.headerImagePath != null) {
      final absolutePath =
          '$_currentReportPath/${_currentReport!.headerImagePath}';
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentReport!.headerImagePath = null;
    notifyListeners();
  }

  void addQuestion([int? index]) {
    if (_currentReport == null) return;
    final newIndex = index == null
        ? _currentReport!.questions.length
        : index + 1;
    final newQuestion = Question(
      id: DateTime.now().millisecondsSinceEpoch,
      localizations: {},
    );
    for (final lang in _currentReport!.availableLanguages) {
      newQuestion.localizations[lang] = QuestionLocalization();
    }
    _currentReport!.questions.insert(newIndex, newQuestion);

    final newTranslations = <String, Map<String, List<TranslationAnswer>>>{};
    _currentReport!.translations.forEach((key, langMap) {
      final k = int.parse(key);
      if (k >= newIndex) {
        newTranslations[(k + 1).toString()] = langMap;
      } else {
        newTranslations[key] = langMap;
      }
    });

    final newMarkers = <String, List<AnswerMarkers>>{};
    _currentReport!.markers.forEach((key, markersList) {
      final k = int.parse(key);
      if (k >= newIndex) {
        newMarkers[(k + 1).toString()] = markersList;
      } else {
        newMarkers[key] = markersList;
      }
    });

    newTranslations[newIndex.toString()] = {};
    for (final lang in _currentReport!.availableLanguages) {
      newTranslations[newIndex.toString()]![lang] = [TranslationAnswer()];
    }
    newMarkers[newIndex.toString()] = [AnswerMarkers()];

    // Новый вопрос (qid уже в newQuestion) получает первый ряд с rid.
    final rid = const Uuid().v4();
    newMarkers[newIndex.toString()]!.first.rowId = rid;
    for (final lang in _currentReport!.availableLanguages) {
      newTranslations[newIndex.toString()]![lang]!.first.rowId = rid;
    }

    _currentReport!.translations = newTranslations;
    _currentReport!.markers = newMarkers;
    notifyListeners();
  }

  Future<void> removeQuestion(int index) async {
    if (_currentReport == null) return;
    if (index < 0 || index >= _currentReport!.questions.length) return;

    // P3-59: перед удалением вопроса удаляем все его медиафайлы с сервера/диска
    // и отменяем фоновую обработку видео.
    final qid = index.toString();
    final markersList = _currentReport!.markers[qid];
    if (markersList != null) {
      for (final markers in markersList) {
        for (final media in markers.media) {
          _videoQueue?.cancel(media);
          if (media.isCompressing || media.isUploading) {
            // Фоновая обработка ещё идёт — удалим с сервера/диска,
            // как только задача завершится.
            _pendingDeletion.add(media);
          } else {
            await _deleteMediaItem(media);
          }
        }
      }
    }

    _currentReport!.questions.removeAt(index);

    final newTranslations = <String, Map<String, List<TranslationAnswer>>>{};
    _currentReport!.translations.forEach((key, langMap) {
      final k = int.parse(key);
      if (k == index) {
        return;
      } else if (k > index) {
        newTranslations[(k - 1).toString()] = langMap;
      } else {
        newTranslations[key] = langMap;
      }
    });

    final newMarkers = <String, List<AnswerMarkers>>{};
    _currentReport!.markers.forEach((key, markersList) {
      final k = int.parse(key);
      if (k == index) {
        return;
      } else if (k > index) {
        newMarkers[(k - 1).toString()] = markersList;
      } else {
        newMarkers[key] = markersList;
      }
    });

    _currentReport!.translations = newTranslations;
    _currentReport!.markers = newMarkers;
    notifyListeners();
  }

  void updateQuestionLocalization(
    int index,
    String langCode,
    String? name,
    String? description,
    String? example,
  ) {
    if (_currentReport == null || index >= _currentReport!.questions.length) {
      return;
    }
    final loc =
        _currentReport!.questions[index].localizations[langCode] ??
        QuestionLocalization();
    if (name != null) loc.name = name;
    if (description != null) loc.description = description;
    if (example != null) loc.example = example;
    _currentReport!.questions[index].localizations[langCode] = loc;
    notifyListeners();
  }

  void addAnswer(int questionIndex) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    for (final lang in _currentReport!.availableLanguages) {
      if (!_currentReport!.translations.containsKey(qid)) {
        _currentReport!.translations[qid] = {};
      }
      if (!_currentReport!.translations[qid]!.containsKey(lang)) {
        _currentReport!.translations[qid]![lang] = [TranslationAnswer()];
      }
      _currentReport!.translations[qid]![lang]!.add(TranslationAnswer());
    }

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    _currentReport!.markers[qid]!.add(AnswerMarkers());

    // Новая строка ответа получает стабильный rid (одинаковый во всех языках
    // и в маркере) — основа будущего merge-by-id.
    final rid = const Uuid().v4();
    for (final lang in _currentReport!.availableLanguages) {
      final list = _currentReport!.translations[qid]![lang];
      if (list != null && list.isNotEmpty) {
        list.last.rowId = rid;
      }
    }
    _currentReport!.markers[qid]!.last.rowId = rid;

    notifyListeners();
  }

  Future<void> removeAnswer(int questionIndex, int answerIndex) async {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    for (final lang in _currentReport!.availableLanguages) {
      if (_currentReport!.translations.containsKey(qid) &&
          _currentReport!.translations[qid]!.containsKey(lang) &&
          _currentReport!.translations[qid]![lang]!.length > 1) {
        _currentReport!.translations[qid]![lang]!.removeAt(answerIndex);
      }
    }

    if (_currentReport!.markers.containsKey(qid) &&
        _currentReport!.markers[qid]!.length > 1) {
      final markers = _currentReport!.markers[qid]![answerIndex];
      // P3-59: удаляем все медиафайлы ответа с сервера (web) или диска (native)
      // и отменяем фоновую обработку видео.
      for (final media in markers.media) {
        _videoQueue?.cancel(media);
        if (media.isCompressing || media.isUploading) {
          _pendingDeletion.add(media);
        } else {
          await _deleteMediaItem(media);
        }
      }
      _currentReport!.markers[qid]!.removeAt(answerIndex);
    }

    notifyListeners();
  }

  void updateAnswerText(
    int questionIndex,
    int answerIndex,
    String text, {
    String? language,
  }) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = language ?? _currentReport!.currentLanguage;

    if (_currentReport!.translations.containsKey(qid) &&
        _currentReport!.translations[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.translations[qid]![lang]!.length) {
      final cell = _currentReport!.translations[qid]![lang]![answerIndex];
      final changed = cell.text != text;
      cell.text = text;
      cell.isEmpty = text.isEmpty;
      if (changed) {
        // updatedAt фиксирует момент последнего изменения ячейки — он нужен
        // diff-движку (Фаза 2) как per-cell optimistic lock (baseUpdatedAt).
        cell.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }

      // При обычном редактировании текущего языка очищаем переводы в других
      // языках. При разрешении конфликта для конкретного языка — не трогаем.
      if (language == null) {
        for (final otherLang in _currentReport!.availableLanguages) {
          if (otherLang != lang &&
              _currentReport!.translations[qid]!.containsKey(otherLang) &&
              answerIndex <
                  _currentReport!.translations[qid]![otherLang]!.length) {
            final otherCell =
                _currentReport!.translations[qid]![otherLang]![answerIndex];
            final otherChanged = otherCell.text != '';
            otherCell.text = '';
            otherCell.isEmpty = true;
            if (otherChanged) {
              otherCell.updatedAt = DateTime.now().millisecondsSinceEpoch;
            }
          }
        }
      }
    } else if (answerIndex ==
            _currentReport!.translations[qid]![lang]!.length &&
        text.isNotEmpty) {
      // «Фантомный» ряд: ответа ещё нет в данных (новые отчёты не создают
      // пустые rows). При первом введённом символе создаём ряд со свежим
      // rowId — он будет воспринят merge-движком как новый (answer.add),
      // а не как перезапись чужого ответа.
      _ensureAnswerRow(questionIndex, language: lang);
      final cell = _currentReport!.translations[qid]![lang]![answerIndex];
      cell.text = text;
      cell.isEmpty = false;
      cell.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Создать реальный ряд ответа (свежий id + общий rowId во всех языках),
  /// если его ещё нет. Используется для ленивого создания при первом вводе.
  void _ensureAnswerRow(int questionIndex, {String? language}) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    for (final l in _currentReport!.availableLanguages) {
      if (!_currentReport!.translations.containsKey(qid)) {
        _currentReport!.translations[qid] = {};
      }
      if (!_currentReport!.translations[qid]!.containsKey(l)) {
        _currentReport!.translations[qid]![l] = [];
      }
    }

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }

    // Новый ряд (пока в пустом состоянии — текст задаётся вызывающим).
    _currentReport!.markers[qid]!.add(AnswerMarkers());
    for (final l in _currentReport!.availableLanguages) {
      _currentReport!.translations[qid]![l]!.add(TranslationAnswer());
    }

    final rid = const Uuid().v4();
    _currentReport!.markers[qid]!.last.rowId = rid;
    for (final l in _currentReport!.availableLanguages) {
      _currentReport!.translations[qid]![l]!.last.rowId = rid;
    }
  }

  /// Есть ли уже реальный ряд ответа по индексу (иначе это «фантом»)?
  bool _needsAnswerRow(String qid, int answerIndex) {
    final markers = _currentReport?.markers[qid];
    return markers == null || markers.length <= answerIndex;
  }

  void updateAnswerAttention(
    int questionIndex,
    int answerIndex,
    bool attention,
  ) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    _currentReport!.markers[qid]![answerIndex].attention = attention;
    notifyListeners();
  }

  Future<void> addMedia(
    int questionIndex,
    int answerIndex,
    File file,
    bool isAttention,
  ) async {
    if (_currentReport == null) return;

    if (_currentReportPath == null) {
      final folderPath = await _generateFolderName();
      _currentReportPath = folderPath;
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      await Directory('$folderPath/photos').create(recursive: true);
      await Directory('$folderPath/X').create(recursive: true);
    }

    final qid = questionIndex.toString();

    // Медиа — тоже ответ: если реального ряда ещё нет (фантом), создаём его
    // лениво, чтобы медиа привязалось к существующему ряду с rowId.
    if (_needsAnswerRow(qid, answerIndex)) {
      _ensureAnswerRow(questionIndex);
    }

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    final counterKey =
        '${questionIndex}_${answerIndex}_${isAttention ? 'X' : 'photos'}';
    if (!_currentReport!.mediaCounter.containsKey(counterKey)) {
      _currentReport!.mediaCounter[counterKey] = 1;
    }
    var counter = _currentReport!.mediaCounter[counterKey]!;
    final ext = file.path.split('.').last;
    final mimeType = mimeTypeFromFilename(file.path);
    final typePrefix = mimeType.startsWith('video/') ? 'v' : 'f';
    String fileName;
    // Гарантия уникальности: счётчик мог сброситься после синхронизации
    // (перезапись существующего файла = «пропавшее» фото), поэтому имя
    // проверяется по всем медиа отчёта и по файлам на диске.
    final usedNames = _collectMediaNames();
    final folderName = isAttention ? 'X' : 'photos';
    do {
      fileName =
          '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${counter.toString().padLeft(3, '0')}.$ext';
      counter++;
    } while (usedNames.contains(fileName) ||
        File('$_currentReportPath/$folderName/$fileName').existsSync());
    _currentReport!.mediaCounter[counterKey] = counter;

    final destFolder = Directory('$_currentReportPath/$folderName');
    if (!await destFolder.exists()) {
      await destFolder.create(recursive: true);
    }

    final destPath = File('${destFolder.path}/$fileName');

    if (mimeType.startsWith('image/')) {
      final bytes = await file.readAsBytes();
      await image_compressor.loadLibrary();
      final compressed = image_compressor.ImageCompressor.compress(
        Uint8List.fromList(bytes),
        _imageMaxSize,
        jpegQuality: _imageJpegQuality,
      );
      await destPath.writeAsBytes(compressed);
    } else {
      await file.copy(destPath.path);
    }

    final relativePath = '$folderName/$fileName';

    final mediaItem = MediaItem(
      name: fileName,
      type: mimeType,
      attention: isAttention,
      originalName: file.path.split(Platform.pathSeparator).last,
      localPath: relativePath,
      fileSize: await file.length(),
    );

    _currentReport!.markers[qid]![answerIndex].media.add(mediaItem);

    notifyListeners();
  }

  /// Собрать все имена медиафайлов отчёта (для проверки уникальности).
  Set<String> _collectMediaNames() {
    final names = <String>{};
    _currentReport?.markers.forEach((_, markersList) {
      for (final markers in markersList) {
        for (final media in markers.media) {
          names.add(media.name);
        }
      }
    });
    return names;
  }

  /// Добавить медиафайл из байтов (для web-версии).
  ///
  /// Все файлы добавляются в UI сразу; загрузка на сервер идёт в фоне.
  /// - Если есть _serverReportId и _ks3Folder — фоновая загрузка в KS3.
  /// - Если нет — файл хранится в памяти (webBytes), загрузится при saveReport.
  ///
  /// Параметры:
  /// - [questionIndex], [answerIndex] — индексы вопроса и ответа
  /// - [bytes] — содержимое файла (из XFile.readAsBytes())
  /// - [fileName] — имя файла с расширением (например, 'photo.jpg')
  /// - [mimeType] — MIME-тип (например, 'image/jpeg', 'video/mp4')
  /// - [isAttention] — true для папки X (внимание), false для photos
  /// - [onUploadProgress] — callback для отслеживания прогресса (0.0 - 1.0)
  /// - [originalSize] — размер оригинального файла (для видео, когда в
  ///   [bytes] переданы уже сжатые байты). Используется для проверки
  ///   реального сжатия и отображения в UI.
  Future<String?> addMediaFromBytes({
    required int questionIndex,
    required int answerIndex,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    bool isAttention = false,
    int? originalSize,
    int? compressedSize,
    void Function(double progress)? onUploadProgress,
    void Function(String errorCode)? onVideoError,
  }) async {
    if (_currentReport == null) return null;

    final qid = questionIndex.toString();

    // Медиа — тоже ответ: если реального ряда ещё нет (фантом), создаём его
    // лениво, чтобы медиа привязалось к существующему ряду с rowId.
    if (_needsAnswerRow(qid, answerIndex)) {
      _ensureAnswerRow(questionIndex);
    }

    // Создаём markers для вопроса, если нет
    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    // Счётчик медиа для этого вопроса/ответа
    final counterKey =
        '${questionIndex}_${answerIndex}_${isAttention ? 'X' : 'photos'}';
    if (!_currentReport!.mediaCounter.containsKey(counterKey)) {
      _currentReport!.mediaCounter[counterKey] = 1;
    }
    var counter = _currentReport!.mediaCounter[counterKey]!;

    // Генерируем имя файла: f/v + вопрос + ответ + номер
    // f = photo, v = video
    final typePrefix = mimeType.startsWith('video/') ? 'v' : 'f';
    final ext = fileName.split('.').last;
    // Гарантия уникальности: счётчик мог сброситься после синхронизации —
    // имя не должно совпадать с уже существующим медиа отчёта.
    final usedNames = _collectMediaNames();
    String generatedName;
    do {
      generatedName =
          '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${counter.toString().padLeft(3, '0')}.$ext';
      counter++;
    } while (usedNames.contains(generatedName));
    _currentReport!.mediaCounter[counterKey] = counter;

    // Относительный путь (для совместимости с mobile/desktop)
    final folderName = isAttention ? 'X' : 'photos';
    final relativePath = '$folderName/$generatedName';

    // Сжимаем изображение, если нужно (deferred-чанк с пакетом image).
    Uint8List finalBytes = bytes;
    if (mimeType.startsWith('image/')) {
      await image_compressor.loadLibrary();
      finalBytes = image_compressor.ImageCompressor.compress(
        bytes,
        _imageMaxSize,
        jpegQuality: _imageJpegQuality,
      );
    }

    // Создаём MediaItem с байтами для web.
    final isVideo = mimeType.startsWith('video/');
    final mediaItem = MediaItem(
      name: generatedName,
      type: mimeType,
      attention: isAttention,
      originalName: fileName,
      localPath: relativePath,
      fileSize: finalBytes.length,
      compressedSize: isVideo ? null : finalBytes.length,
      webBytes: finalBytes, // Байты для превью в UI
    );

    _currentReport!.markers[qid]![answerIndex].media.add(mediaItem);

    notifyListeners();

    // ===== Загрузка на сервер в фоне =====
    if (isVideo && kIsWeb) {
      // На web видео сжимается и загружается через фоновую очередь.
      // Оригинальные байты передаются в очередь; UI показывает прогресс.
      final queue = await _getVideoQueue();
      unawaited(
        queue.enqueue(
          media: mediaItem,
          originalBytes: bytes,
          fileName: generatedName,
          mimeType: mimeType,
          relativePath: relativePath,
          reportId: _serverReportId,
          shareToken: _shareToken,
          qualityLevel: _videoQualityLevel,
          onError: (code) {
            if (kDebugMode) {
              debugPrint('Video queue error ($code): $generatedName');
            }
            onVideoError?.call(code);
          },
        ),
      );
    } else if (_serverReportId != null &&
        (_ks3Folder != null ||
            (_shareToken != null && _shareToken!.isNotEmpty))) {
      // Фото (и native видео без сжатия) загружаем сразу, если отчёт сохранён.
      // В share-режиме _ks3Folder может быть null — сервер найдёт его сам.
      _boundedMediaUpload(
        () =>
            _uploadMediaToServer(
              mediaItem,
              finalBytes,
              generatedName,
              relativePath,
              mimeType,
              onUploadProgress,
            ).catchError((e) {
              if (kDebugMode) debugPrint('Background upload failed: $e');
            }),
      );
    }

    return generatedName;
  }

  /// Загрузить фото шапки на сервер (web).
  Future<void> _uploadHeaderImageToServer() async {
    if (_headerImageBytes == null ||
        _headerImageFileName == null ||
        _serverReportId == null) {
      return;
    }

    try {
      final result = await ApiService.uploadFileFromBytes(
        bytes: _headerImageBytes!,
        filename: _headerImageFileName!,
        relativePath: _headerImageFileName!,
        reportId: _serverReportId,
        onUploadProgress: (_) {},
      );

      if (result.success) {
        if (kDebugMode) {
          debugPrint('Header image uploaded: $_headerImageFileName');
        }
        // Очищаем временное хранилище
        _headerImageBytes = null;
        _headerImageFileName = null;
      } else {
        if (kDebugMode) {
          debugPrint('Header image upload failed: ${result.error}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Header image upload error: $e');
      }
    }
  }

  /// Выполняет загрузку медиа, ограничивая число одновременных загрузок
  /// на web значением [_maxConcurrentWebMediaUploads]. На native лимит
  /// не применяется (загрузка идёт через локальные файлы).
  Future<void> _boundedMediaUpload(Future<void> Function() upload) async {
    if (!kIsWeb) {
      await upload();
      return;
    }
    while (_runningWebMediaUploads >= _maxConcurrentWebMediaUploads) {
      final wait = Completer<void>();
      _webMediaUploadWaiters.add(wait);
      await wait.future;
    }
    _runningWebMediaUploads++;
    try {
      await upload();
    } finally {
      _runningWebMediaUploads--;
      if (_webMediaUploadWaiters.isNotEmpty) {
        _webMediaUploadWaiters.removeAt(0).complete();
      }
    }
  }

  /// Загрузить медиафайл на сервер KS3.
  ///
  /// Вызывается из addMediaFromBytes. После успешной загрузки:
  /// - Сохраняет serverFileId в MediaItem
  /// - Очищает webBytes (чтобы не держать в памяти)
  /// - Вызывает notifyListeners() для обновления UI
  Future<void> _uploadMediaToServer(
    MediaItem mediaItem,
    Uint8List bytes,
    String fileName,
    String relativePath,
    String mimeType,
    void Function(double progress)? onUploadProgress,
  ) async {
    // P3-45: Защита от race condition — если файл уже загружается, пропускаем.
    if (mediaItem.isUploading) {
      if (kDebugMode) {
        debugPrint('Upload skipped (already uploading): $fileName');
      }
      return;
    }

    // P3-58: для web-видео загрузка разрешена только после реального сжатия.
    // На native платформах видео не сжимается через ffmpeg.wasm, поэтому
    // guard применяем только на web.
    if (mediaItem.type.startsWith('video/') && kIsWeb) {
      final compressed = mediaItem.compressedSize;
      final original = mediaItem.fileSize;
      if (compressed == null || original == null || compressed >= original) {
        if (kDebugMode) {
          debugPrint(
            'Upload BLOCKED (video not compressed): $fileName '
            '(compressed=$compressed, original=$original)',
          );
        }
        return;
      }
    }

    mediaItem.isUploading = true;

    try {
      mediaItem.uploadProgress = 0.0;
      notifyListeners();

      final uploadStart = DateTime.now();
      if (kDebugMode) {
        debugPrint('Upload start: $fileName (${bytes.length} bytes)');
      }

      // Web — всегда presigned. Native — multipart, НО только для владельца:
      // эндпоинт /files/upload требует, чтобы JWT-пользователь был создателем
      // отчёта. Share-пользователь (аноним по ссылке/QR) получал 403, файл не
      // попадал в БД — владелец видел «битое» фото, а HTML-просмотр его не
      // показывал вовсе. Для share-режима используем presigned share-загрузку.
      final isShare = _shareToken != null && _shareToken!.isNotEmpty;
      ApiResult result;
      if (kIsWeb || isShare) {
        result = await _uploadViaPresignedUrl(
          mediaItem: mediaItem,
          bytes: bytes,
          fileName: fileName,
          relativePath: relativePath,
          mimeType: mimeType,
          onUploadProgress: onUploadProgress,
        );
      } else {
        result = await ApiService.uploadFileFromBytes(
          bytes: bytes,
          filename: fileName,
          relativePath: relativePath,
          reportId: _serverReportId,
          onUploadProgress: (progress) {
            if (kDebugMode) {
              debugPrint(
                'Upload progress: $fileName = ${(progress * 100).toStringAsFixed(0)}%',
              );
            }
            mediaItem.uploadProgress = progress;
            notifyListeners();
            onUploadProgress?.call(progress);
          },
        );
      }

      final uploadEnd = DateTime.now();
      final uploadDuration = uploadEnd.difference(uploadStart).inSeconds;
      if (kDebugMode) {
        debugPrint('Upload complete: $fileName in ${uploadDuration}s');
      }

      mediaItem.uploadProgress = 1.0;
      notifyListeners();
      onUploadProgress?.call(1.0);

      if (result.success && result.data?['file'] != null) {
        // Сохраняем serverFileId (UUID файла на сервере)
        final fileId = result.data!['file']['id'];
        if (fileId is String) {
          mediaItem.serverFileId = fileId;
          // Сохраняем URL для превью и освобождаем webBytes.
          final uploadedUrl = result.data?['url'] as String?;
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            mediaItem.webUrl = uploadedUrl;
            if (kIsWeb) {
              // После успешной загрузки байты в памяти не нужны: превью
              // строится из webUrl/сервера. Это предотвращает накопление
              // всех фото/видео в куче браузера при множественной загрузке.
              mediaItem.webBytes = null;
            }
          }
          notifyListeners();
          if (kDebugMode) {
            debugPrint('Media uploaded: $fileName → fileId=$fileId');
          }

          // Для видео — генерируем и загружаем превью (кадр из видео).
          if (mediaItem.type.startsWith('video/')) {
            _uploadThumbnail(mediaItem, bytes, fileName, relativePath);
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('Media upload failed: $fileName — ${result.error}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Media upload error: $fileName — $e');
    } finally {
      mediaItem.isUploading = false;
      notifyListeners();
    }
  }

  /// Генерирует и загружает превью (кадр) для видео на KS3.
  ///
  /// Вызывается в фоне после успешной загрузки видео.
  /// Не блокирует UI — ошибки логируются, но не прерывают работу.
  Future<void> _uploadThumbnail(
    MediaItem mediaItem,
    Uint8List videoBytes,
    String videoFileName,
    String videoRelativePath,
  ) async {
    try {
      // Deferred: генератор превью подгружается при первом вызове.
      await thumbnail_gen.loadLibrary();

      // Генерируем превью из видео-байтов.
      Uint8List? thumbnailBytes;
      if (kIsWeb) {
        final generator = thumbnail_gen.VideoThumbnailGenerator.create();
        thumbnailBytes = await generator.generateThumbnail(
          videoBytes,
          maxWidth: 256,
          maxHeight: 256,
          quality: 70,
        );
      } else {
        // Native: генерируем из локального файла.
        if (mediaItem.localPath == null) return;
        final absPath = _currentReportPath != null
            ? '$_currentReportPath/${mediaItem.localPath}'
            : mediaItem.localPath!;
        if (!File(absPath).existsSync()) {
          if (kDebugMode) {
            debugPrint('Thumbnail: video file not found: $absPath');
          }
          return;
        }
        final nativeGenerator = thumbnail_gen.VideoThumbnailGenerator.create();
        final fileBytes = Uint8List.fromList(await File(absPath).readAsBytes());
        thumbnailBytes = await nativeGenerator.generateThumbnail(
          fileBytes,
          maxWidth: 256,
          maxHeight: 256,
          quality: 70,
        );
      }

      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('Thumbnail generation returned null for $videoFileName');
        }
        return;
      }

      // Загружаем превью на сервер.
      final thumbFileName = 'thumb_${videoFileName.split('.').first}.jpg';
      final thumbRelativePath = videoRelativePath.replaceAll(
        videoFileName,
        thumbFileName,
      );

      if (kDebugMode) {
        debugPrint(
          'Uploading thumbnail: $thumbFileName (${thumbnailBytes.length} bytes)',
        );
      }

      ApiResult thumbResult;
      if (kIsWeb && (_shareToken != null || _serverReportId != null)) {
        thumbResult = await _uploadViaPresignedUrl(
          mediaItem: mediaItem,
          bytes: thumbnailBytes,
          fileName: thumbFileName,
          relativePath: thumbRelativePath,
          mimeType: 'image/jpeg',
        );
      } else {
        thumbResult = await ApiService.uploadFileFromBytes(
          bytes: thumbnailBytes,
          filename: thumbFileName,
          relativePath: thumbRelativePath,
          reportId: _serverReportId,
        );
      }

      if (thumbResult.success && thumbResult.data?['file'] != null) {
        final thumbFileId = thumbResult.data!['file']['id'];
        if (thumbFileId is String) {
          mediaItem.thumbnailServerFileId = thumbFileId;
          notifyListeners();
          if (kDebugMode) {
            debugPrint(
              'Thumbnail uploaded: $thumbFileName → fileId=$thumbFileId',
            );
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            'Thumbnail upload failed: $thumbFileName — ${thumbResult.error}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Thumbnail error for $videoFileName: $e');
      }
    }
  }

  /// Прямая загрузка в KS3 через presigned PUT URL (web only).
  ///
  /// Flow:
  ///   1. POST /files/presign-upload (или /files/presign-upload-share для share-ссылки)
  ///      → получаем presigned URL + fileId
  ///   2. PUT directly to KS3 → загружаем байты
  ///   3. POST /files/confirm-upload (или /files/confirm-upload-share)
  ///      → создаём запись в БД
  Future<ApiResult> _uploadViaPresignedUrl({
    required MediaItem mediaItem,
    required Uint8List bytes,
    required String fileName,
    required String relativePath,
    required String mimeType,
    void Function(double progress)? onUploadProgress,
  }) async {
    final isShare = _shareToken != null && _shareToken!.isNotEmpty;

    // Шаг 1: presign
    final ApiResult presignResult;
    if (isShare) {
      presignResult = await ApiService.presignUploadForShare(
        fileName: fileName,
        shareToken: _shareToken!,
        relativePath: relativePath,
        reportId: _serverReportId,
      );
    } else {
      presignResult = await ApiService.presignUpload(
        fileName: fileName,
        relativePath: relativePath,
        reportId: _serverReportId,
      );
    }

    if (!presignResult.success) {
      return presignResult;
    }

    final uploadUrl = presignResult.data!['uploadUrl'] as String;
    final fileId = presignResult.data!['fileId'] as String;
    final storageKey = presignResult.data!['storageKey'] as String;
    final serverMimeType =
        presignResult.data!['mimeType'] as String? ?? mimeType;
    final relPath = presignResult.data!['relPath'] as String? ?? relativePath;

    // Шаг 2: прямая загрузка в KS3
    final uploadResult = await uploadToPresignedUrl(
      uploadUrl: uploadUrl,
      bytes: bytes,
      onUploadProgress: (progress) {
        if (kDebugMode) {
          debugPrint(
            'KS3 direct upload progress: $fileName = ${(progress * 100).toStringAsFixed(0)}%',
          );
        }
        mediaItem.uploadProgress = progress;
        notifyListeners();
        onUploadProgress?.call(progress);
      },
    );

    if (uploadResult != true) {
      return ApiResult(success: false, error: uploadResult.toString());
    }

    // Шаг 3: подтвердить загрузку — создать запись в БД
    if (isShare) {
      return ApiService.confirmUploadForShare(
        fileId: fileId,
        storageKey: storageKey,
        fileName: fileName,
        size: bytes.length,
        mimeType: serverMimeType,
        relPath: relPath,
        shareToken: _shareToken!,
      );
    }

    return ApiService.confirmUpload(
      fileId: fileId,
      storageKey: storageKey,
      fileName: fileName,
      size: bytes.length,
      mimeType: serverMimeType,
      relPath: relPath,
      reportId: _serverReportId,
    );
  }

  /// Загрузить все медиа, у которых ещё нет serverFileId.
  ///
  /// Вызывается после сохранения отчёта на сервер, когда _serverReportId и
  /// _ks3Folder уже установлены. Проходит по всем медиа отчёта и загружает те,
  /// у которых serverFileId == null.
  ///
  /// Байты берутся из webBytes (web / только что добавленное медиа) либо,
  /// если их нет, читаются с диска по localPath — после перезапуска приложения
  /// webBytes не сохраняется в JSON, поэтому на native это единственный
  /// источник. Возвращает число успешно загруженных файлов.
  Future<int> _uploadPendingMedia() async {
    // В share-режиме адрес отчёта известен по токену, а _ks3Folder может
    // быть null — сервер найдёт папку сам (как в addMediaBytes).
    final shareMode = _shareToken != null && _shareToken!.isNotEmpty;
    if (_currentReport == null) return 0;
    if (_serverReportId == null && !shareMode) return 0;
    if (_ks3Folder == null && !shareMode) return 0;

    if (kDebugMode) {
      debugPrint('_uploadPendingMedia: scanning for pending media...');
    }

    int uploadedCount = 0;

    // Проходим по всем markers и их media
    for (final entry in _currentReport!.markers.entries) {
      final markersList = entry.value;

      for (int answerIdx = 0; answerIdx < markersList.length; answerIdx++) {
        final mediaList = markersList[answerIdx].media;

        for (int mediaIdx = 0; mediaIdx < mediaList.length; mediaIdx++) {
          final media = mediaList[mediaIdx];

          // Пропускаем уже загруженные
          if (media.serverFileId != null) continue;

          // Источник байтов: память (web/только что добавлено) или диск.
          final bytes =
              media.webBytes ?? await _readLocalMediaBytes(media.localPath);
          if (bytes == null) continue;

          // Загружаем на сервер
          if (kDebugMode) {
            debugPrint('_uploadPendingMedia: uploading ${media.name}...');
          }

          await _boundedMediaUpload(
            () => _uploadMediaToServer(
              media,
              bytes,
              media.name,
              media.localPath ?? media.name,
              media.type,
              null,
            ),
          );

          if (media.serverFileId != null) {
            uploadedCount++;
          }
        }
      }
    }

    if (kDebugMode) {
      debugPrint('_uploadPendingMedia: uploaded $uploadedCount files');
    }
    return uploadedCount;
  }

  /// Прочитать байты медиафайла из локальной папки отчёта (native).
  ///
  /// [path] — путь относительно папки отчёта (например "photos/f1_1_001.jpg");
  /// абсолютный путь тоже поддерживается. На web всегда null.
  Future<Uint8List?> _readLocalMediaBytes(String? path) async {
    if (kIsWeb || path == null || path.isEmpty) return null;
    try {
      var file = File(path);
      if (!await file.exists()) {
        final folder = _currentReportPath;
        if (folder == null) return null;
        file = File('$folder/$path');
        if (!await file.exists()) return null;
      }
      return await file.readAsBytes();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_readLocalMediaBytes failed ($path): $e');
      }
      return null;
    }
  }

  /// Флаг защиты от рекурсии при дозаливке медиа.
  bool _mediaRelinkInProgress = false;

  /// Загрузить медиа без serverFileId и, если что-то реально загрузилось,
  /// повторно отправить отчёт: сервер должен узнать serverFileId файлов
  /// (media-ссылки живут в самом документе отчёта, а не только в файлах).
  Future<void> _uploadPendingMediaAndRelink() async {
    if (_mediaRelinkInProgress) return;
    _mediaRelinkInProgress = true;
    try {
      final uploaded = await _uploadPendingMedia();
      if (uploaded == 0) return;
      final shareMode = _shareToken != null && _shareToken!.isNotEmpty;
      if (_serverReportId == null && !shareMode) return;
      if (kDebugMode) {
        debugPrint(
          '_uploadPendingMediaAndRelink: $uploaded uploaded, pushing file ids',
        );
      }
      await saveReportToServer();

      // На web сразу подтягиваем presigned URL миниатюр: иначе сетка
      // грузит полные фото до следующей перезагрузки отчёта с сервера.
      if (kIsWeb && !shareMode && _serverReportId != null) {
        await _populateMediaWebUrls(_serverReportId!);
      }
    } finally {
      _mediaRelinkInProgress = false;
    }
  }

  /// Удалить медиафайлы, ожидающие завершения фоновой обработки.
  ///
  /// Вызывается при каждом событии прогресса очереди. Как только
  /// обработка медиа завершена (не сжимается и не загружается),
  /// пытаемся удалить его с сервера/диска.
  Future<void> _flushPendingDeletions() async {
    final ready = _pendingDeletion.where((media) {
      return !media.isCompressing && !media.isUploading;
    }).toList();

    for (final media in ready) {
      _pendingDeletion.remove(media);
      await _deleteMediaItem(media);
    }
  }

  /// Удалить медиафайл с сервера (web) или с диска (native).
  ///
  /// Используется в removeMedia, removeAnswer и removeQuestion.
  Future<void> _deleteMediaItem(MediaItem media) async {
    if (kIsWeb) {
      // На web удаляем файл с сервера, если он уже туда загружен.
      if (media.serverFileId != null) {
        try {
          final result = await ApiService.deleteFile(media.serverFileId!);
          if (result.success) {
            if (kDebugMode) {
              debugPrint('Media deleted from server: ${media.serverFileId}');
            }
          } else if (kDebugMode) {
            debugPrint(
              'Server returned error when deleting media: ${result.error}',
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to delete media from server: $e');
        }
      }
    } else {
      // На нативных платформах удаляем локальный файл.
      if (_currentReportPath != null && media.localPath != null) {
        final absolutePath = '$_currentReportPath/${media.localPath}';
        final file = File(absolutePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  /// Удалить медиафайл.
  ///
  /// На web: если файл уже загружен на сервер (serverFileId) — удаляем с сервера.
  /// На mobile/desktop: удаляем локальный файл и переименовываем оставшиеся
  /// для сохранения порядка именования.
  Future<void> removeMedia(
    int questionIndex,
    int answerIndex,
    int mediaIndex,
  ) async {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    if (!_currentReport!.markers.containsKey(qid) ||
        answerIndex >= _currentReport!.markers[qid]!.length ||
        mediaIndex >= _currentReport!.markers[qid]![answerIndex].media.length) {
      return;
    }

    final media = _currentReport!.markers[qid]![answerIndex].media[mediaIndex];

    // Отменяем фоновую обработку видео, если она ещё в очереди.
    _videoQueue?.cancel(media);

    if (media.isCompressing || media.isUploading) {
      _pendingDeletion.add(media);
    } else {
      await _deleteMediaItem(media);
    }

    _currentReport!.markers[qid]![answerIndex].media.removeAt(mediaIndex);

    // Переименование оставшихся файлов актуально только для локального хранения.
    if (!kIsWeb) {
      final remainingMedia = _currentReport!.markers[qid]![answerIndex].media;
      for (int i = 0; i < remainingMedia.length; i++) {
        final item = remainingMedia[i];
        final ext = item.name.split('.').last;
        final typePrefix = item.name.startsWith('v') ? 'v' : 'f';
        final newName =
            '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${(i + 1).toString().padLeft(3, '0')}.$ext';

        if (item.name != newName) {
          final oldName = item.name;
          if (_currentReportPath != null && item.localPath != null) {
            final oldPath = '$_currentReportPath/${item.localPath}';
            final newPath =
                '$_currentReportPath/${item.localPath!.replaceFirst(oldName, newName)}';
            final oldFile = File(oldPath);
            if (await oldFile.exists()) {
              await oldFile.rename(newPath);
            }
            item.localPath = item.localPath!.replaceFirst(oldName, newName);
          }
          item.name = newName;
        }
      }
    }

    final counterKey =
        '${questionIndex}_${answerIndex}_${media.attention ? 'X' : 'photos'}';
    _currentReport!.mediaCounter[counterKey] =
        _currentReport!.markers[qid]![answerIndex].media.length + 1;

    notifyListeners();
  }

  void updateAnswerNeedsWork(
    int questionIndex,
    int answerIndex,
    bool needsWork,
  ) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();

    if (!_currentReport!.markers.containsKey(qid)) {
      _currentReport!.markers[qid] = [];
    }
    while (_currentReport!.markers[qid]!.length <= answerIndex) {
      _currentReport!.markers[qid]!.add(AnswerMarkers());
    }

    _currentReport!.markers[qid]![answerIndex].needsWork = needsWork;
    notifyListeners();
  }

  bool hasAnswersInOtherLanguages(int questionIndex, int answerIndex) {
    return _currentReport?.hasAnswersInOtherLanguages(
          questionIndex,
          answerIndex,
        ) ??
        false;
  }

  Future<String> _getReportsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${appDir.path}/$exportDir');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir.path;
  }

  /// Папка отчёта для серверных/share-отчётов.
  ///
  /// На web локальной ФС нет — возвращается [folderKey] как логическое имя.
  /// На native нужен АБСОЛЮТНЫЙ путь внутри документов приложения: относительное
  /// имя разрешалось бы от рабочей директории процесса (на Android это «/»,
  /// read-only) и запись медиа падала бы с EROFS (errno 30).
  Future<String> _resolveLocalFolderPath(
    String folderKey, {
    bool reuseExisting = false,
  }) async {
    if (kIsWeb) return folderKey;
    final reportsDir = await _getReportsDir();
    // Тот же отчёт перезагружается — оставляем его текущую локальную папку
    // (в ней уже лежат добавленные фото).
    final existing = _currentReportPath;
    if (reuseExisting &&
        existing != null &&
        existing.isNotEmpty &&
        existing.startsWith('$reportsDir${Platform.pathSeparator}')) {
      return existing;
    }
    final folderPath = '$reportsDir/$folderKey';
    if (existing == folderPath) return folderPath;
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return folderPath;
  }

  Future<String> _generateFolderName() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Читаемое имя папки из названия отчёта (карточка 0). Санитизируем,
    // чтобы убрать недопустимые символы и лишние пробелы; добавляем короткий
    // суффикс — гарантируем уникальность и совместимость с ФС.
    final rawTitle = _currentReport?.reportName.trim().isNotEmpty == true
        ? _currentReport!.reportName.trim()
        : 'report';
    final safeTitle = rawTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final shortTitle = safeTitle.length > 40
        ? safeTitle.substring(0, 40)
        : safeTitle;
    final baseName = '${shortTitle.isEmpty ? 'report' : shortTitle}_$now';
    final reportsDir = await _getReportsDir();
    return '$reportsDir/$baseName';
  }

  Future<bool> saveReport() async {
    if (_currentReport == null) return false;
    _serverLinkDetachedOnDeny = false;
    try {
      // ===== Web: сохраняем на сервер =====
      // На web нет локальной файловой системы (path_provider не работает),
      // поэтому отчёт сохраняется напрямую на сервер через API.
      if (kIsWeb) {
        return await saveReportToServer();
      }

      // ===== Mobile/Desktop: сохраняем локально =====
      String folderPath;
      if (_currentReportPath == null) {
        folderPath = await _generateFolderName();
        _currentReportPath = folderPath;
      } else {
        folderPath = _currentReportPath!;
      }
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      await Directory('$folderPath/photos').create(recursive: true);
      await Directory('$folderPath/X').create(recursive: true);

      final jsonFile = File('$folderPath/$reportFilename');
      final jsonData = _currentReport!.toJson();
      await jsonFile.writeAsString(jsonEncode(jsonData));

      if (kDebugMode) {
        debugPrint(
          'saveReport: availableLanguages=${_currentReport!.availableLanguages}',
        );
        debugPrint(
          'saveReport: translations keys=${_currentReport!.translations.keys}',
        );
        for (final qid in _currentReport!.translations.keys) {
          debugPrint(
            'saveReport: translations[$qid] keys=${_currentReport!.translations[qid]!.keys}',
          );
        }
      }

      // Переименовываем локальную папку, чтобы имя отражало название отчёта
      // (легче найти отчёт по имени папки). Делаем после успешной записи JSON,
      // только если папка не `server_<id>` (такие привязаны к облаку) и имя
      // действительно изменилось.
      await _renameReportFolderIfNeeded(folderPath);

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving report: $e');
      return false;
    }
  }

  /// Переименовать локальную папку отчёта под имя текущего названия
  /// (карточка 0). Пропускает облачные папки `server_<id>`.
  Future<void> _renameReportFolderIfNeeded(String currentPath) async {
    if (_currentReport == null) return;
    final reportName = _currentReport!.reportName.trim();
    if (reportName.isEmpty) return;

    final dirName = currentPath.split(Platform.pathSeparator).last;
    // Не трогаем папки, привязанные к облаку по имени.
    if (dirName.startsWith('server_')) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = reportName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final shortTitle = safeTitle.length > 40
        ? safeTitle.substring(0, 40)
        : safeTitle;
    if (shortTitle.isEmpty) return;

    final separatorIdx = currentPath.lastIndexOf(Platform.pathSeparator);
    final reportsDir = currentPath.substring(0, separatorIdx);
    final newPath = '$reportsDir${Platform.pathSeparator}${shortTitle}_$now';
    if (newPath == currentPath) return;

    try {
      final oldDir = Directory(currentPath);
      if (!await oldDir.exists()) return;
      final newDir = Directory(newPath);
      if (await newDir.exists()) return; // коллизия имени — не трогаем
      await oldDir.rename(newPath);
      _currentReportPath = newPath;
      if (kDebugMode) {
        debugPrint('renameReportFolder: $currentPath -> $newPath');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('renameReportFolder error: $e');
    }
  }

  /// Сохранить отчёт на сервер (создать/обновить запись в БД).
  ///
  /// Возвращает true при успехе. Заполняет [serverReportId], [ks3Folder],
  /// [serverPublicId]. Используется кнопкой «Залить на сервер» на нативных
  /// платформах, а также вызывается из [saveReport] на web.
  Future<bool> saveReportToServer() async {
    if (_currentReport == null) return false;
    _serverLinkDetachedOnDeny = false;

    // Медиа без serverFileId заливаем ДО отправки документа: тогда их ID
    // попадут в ops/snapshot этого же сохранения. На web это ещё и
    // обязательно: ops-путь пересобирает отчёт из серверного `merged`,
    // а webBytes (runtime-only) при этом теряются.
    await _uploadPendingMedia();

    final canMergeOps =
        mergeOpsEnabled &&
        !_mergeOpsUnsupported &&
        _serverReportId != null &&
        _baseReportSnapshot != null;
    final bool saved;
    if (canMergeOps) {
      final result = await _saveViaMergeOps();
      if (result == _OpsSaveResult.saved) {
        saved = true;
      } else if (result == _OpsSaveResult.fallbackLegacy) {
        saved = await _saveReportToServer();
      } else {
        saved = false;
      }
    } else {
      saved = await _saveReportToServer();
    }
    if (!saved) return false;

    // Первое сохранение создало запись и KS3-папку — догружаем оставшиеся
    // медиа и повторно отправляем документ, чтобы сервер узнал их ID.
    await _uploadPendingMediaAndRelink();
    return true;
  }

  /// Догрузить медиа, у которых ещё нет serverFileId, и отправить документ
  /// с их ID. Используется кнопкой «Синхронизировать», когда локальных
  /// правок нет, но есть незалитые файлы.
  Future<void> syncPendingMedia() => _uploadPendingMediaAndRelink();

  /// Подтянуть актуальную версию отчёта с сервера, не отправляя локальные
  /// правки.
  ///
  /// Используется кнопкой «Синхронизировать», а также после сохранения:
  /// изменения, сделанные другими (в другом окне браузера или на другом
  /// устройстве), появляются в открытом отчёте. Вызывать только когда
  /// несохранённых локальных правок нет, иначе они будут перезаписаны.
  ///
  /// Возвращает true при успехе. Для отчёта без связи с сервером — false.
  Future<bool> pullFromServer() async {
    final shareToken = _shareToken;
    if (shareToken != null && shareToken.isNotEmpty) {
      return loadSharedReport(shareToken);
    }
    final reportId = _serverReportId;
    if (reportId == null) return false;
    if (kIsWeb) return _loadReportFromServer(reportId);
    // Нативный владелец: тянем актуальную версию с сервера и сохраняем её в
    // локальную папку (локальная папка остаётся источником истины). Ранее pull
    // здесь был отключён, из-за чего изменения, сделанные другим устройством
    // (например через share-ссылку в вебе), не подтягивались, и копия на
    // телефоне расходилась с сервером.
    return _pullIntoLocalFolder(reportId);
  }

  /// Нативный pull для владельца: обновляет открытый отчёт из сервера и
  /// перезаписывает report.json в локальной папке актуальной версией.
  Future<bool> _pullIntoLocalFolder(int reportId) async {
    try {
      final result = await ApiService.getReport(reportId);
      if (!result.success || result.data?['report'] == null) {
        _lastSyncError = result.error;
        if (kDebugMode) debugPrint('pullIntoLocalFolder: ${result.error}');
        return false;
      }
      final server = result.data!['report'] as Map<String, dynamic>;
      final reportData =
          (server['reportData'] as Map?)?.cast<String, dynamic>() ?? {};
      if (reportData.isEmpty) return false;

      // Обновляем модель в памяти — пользователь видит актуальную версию.
      // Сохраняем выбранный пользователем язык заполнения, чтобы pull/синк
      // не сбрасывал его на язык по умолчанию (первый в списке).
      final prevLanguage = _currentReport?.currentLanguage;
      final prevCounter = _currentReport?.mediaCounter;
      _currentReport = Report.fromJson(
        reportData,
        folderPath: _currentReportPath,
      );
      // Счётчик имён медиа монотонен: серверный документ мог потерять
      // mediaCounter — наследуем локальный, чтобы новое фото не получило
      // имя существующего файла (перезапись = «пропавшее» фото).
      _mergeMediaCounters(prevCounter, _currentReport!.mediaCounter);
      if (prevLanguage != null &&
          prevLanguage.isNotEmpty &&
          _currentReport?.availableLanguages.contains(prevLanguage) == true) {
        _currentReport!.currentLanguage = prevLanguage;
      }
      _baseReportSnapshot = reportData;

      final publicId = server['publicId'];
      _serverPublicId = (publicId is String && publicId.isNotEmpty)
          ? publicId
          : null;

      final folder = server['ks3Folder'];
      _ks3Folder = (folder is String && folder.isNotEmpty) ? folder : null;

      final version = server['version'];
      _serverReportVersion = version is int
          ? version
          : int.tryParse(version.toString());

      // Медиа, добавленные другими (например на web по share-ссылке), на этом
      // устройстве локальных файлов не имеют. Заполняем webUrl/thumbnailUrl,
      // чтобы виджеты могли показать их по сети.
      await _populateMediaWebUrls(reportId);

      // Персистим pull-нутую версию в локальную папку (источник истины на native).
      final folderPath = _currentReportPath;
      if (folderPath != null && folderPath.isNotEmpty) {
        final jsonFile = File('$folderPath/$reportFilename');
        await jsonFile.writeAsString(jsonEncode(reportData));
        final metaFile = File('$folderPath/sync_meta.json');
        if (await metaFile.exists()) {
          try {
            final meta =
                jsonDecode(await metaFile.readAsString())
                    as Map<String, dynamic>;
            meta['serverVersion'] = _serverReportVersion;
            await metaFile.writeAsString(jsonEncode(meta));
          } catch (_) {}
        }
      }

      _sanitizeMediaState();
      notifyListeners();
      return true;
    } catch (e) {
      _lastSyncError = e.toString();
      if (kDebugMode) debugPrint('pullIntoLocalFolder error: $e');
      return false;
    }
  }

  /// Сохранить отчёт через ops-PATCH (merge-by-ID, Фаза 2b).
  ///
  /// Строит ops из [_baseReportSnapshot] -> текущий документ, отправляет на
  /// сервер, применяет `merged`. При 409 (конфликт одной ячейки) переустанавливает
  /// базу на серверную версию ячейки и через [onVersionConflict] показывает
  /// существующий диалог (rid транслируется в индексы), затем повторяет ops.
  Future<_OpsSaveResult> _saveViaMergeOps() async {
    if (_currentReport == null) return _OpsSaveResult.failed;
    final serverId = _serverReportId;
    final base = _baseReportSnapshot;
    if (serverId == null || base == null) return _OpsSaveResult.fallbackLegacy;
    final shareToken = (_shareToken == null || _shareToken!.isEmpty)
        ? null
        : _shareToken;

    // ops оперируют ids, которые должны совпадать с сервером. Пока серверный
    // документ legacy (нет canonical answers) — сначала шлём полный документ
    // legacy-путём (он «посеет» на сервере canonical c теми же qid/rid),
    // и только следующие сохранения идут через ops.
    final baseAnswers = base['answers'];
    if (baseAnswers is! Map || baseAnswers.isEmpty) {
      return _OpsSaveResult.fallbackLegacy;
    }

    // Ключи ячеек, по которым уже показывали диалог в этой попытке сохранения.
    // Повторный конфликт по тому же ключу = ячейку изменили снова, пока
    // пользователь выбирал вариант.
    final seenConflictCells = <String>{};

    for (var attempt = 0; attempt < 3; attempt++) {
      // Используем поле (а не локальный `base`): при разрешении конфликта
      // или при гонке версий `_baseReportSnapshot` мог быть обновлён.
      final ops = buildReportOps(
        _baseReportSnapshot!,
        _currentReport!.toJson(),
      );
      if (ops.isEmpty) return _OpsSaveResult.saved;

      final ApiResult result;
      if (shareToken != null) {
        final anonymousId = await AnonymousIdService.getId();
        result = await ApiService.patchSharedReportOps(
          token: shareToken,
          anonymousId: anonymousId,
          ops: ops,
        );
      } else {
        result = await ApiService.patchReportOps(reportId: serverId, ops: ops);
      }

      if (result.success) {
        final merged = result.data?['merged'];
        if (merged is Map) {
          await _applyMergedSnapshot(
            Map<String, dynamic>.from(merged),
            result.data?['newVersion'],
          );
          return _OpsSaveResult.saved;
        }
        // Сервер не вернул merged — ops-контракт не поддерживается.
        _mergeOpsUnsupported = true;
        return _OpsSaveResult.fallbackLegacy;
      }

      if (result.statusCode == 409 &&
          result.data?['code'] == 'VERSION_CONFLICT') {
        final details = _parseCellConflicts(result.data);
        if (details == null || details.answerConflicts.isEmpty) {
          // 409 БЕЗ списка конфликтов = гонка версий: на сервере версия
          // изменилась между чтением и записью (retry в patchReportOps
          // исчерпан). Это НЕ «сервер без ops» — обновляем базу актуальной
          // серверной версией (сохраняя локальные правки) и пробуем ops снова.
          if (await _refreshBaseSnapshotFromServer()) {
            continue;
          }
          _lastSyncError = 'Failed to refresh report version';
          return _OpsSaveResult.failed;
        }
        // Повторный конфликт по той же ячейке: пока пользователь выбирал
        // вариант, ячейку успел изменить ещё кто-то.
        final keys = details.answerConflicts
            .map((c) => '${c.qid ?? ''}|${c.rid ?? ''}|${c.language}')
            .toList();
        final isRepeat = keys.any(seenConflictCells.contains);
        seenConflictCells.addAll(keys);
        final resolvedDetails = isRepeat
            ? ConflictDetails(
                currentVersion: details.currentVersion,
                answerConflicts: details.answerConflicts,
                isRepeat: true,
              )
            : details;
        // База ячеек = серверная версия, чтобы повторные ops не конфликтовали.
        _rebaseBaseToServer(resolvedDetails);
        if (onVersionConflict == null) {
          _lastSyncError = 'Conflict handler not available';
          return _OpsSaveResult.failed;
        }
        final action = await onVersionConflict!(resolvedDetails);
        if (action == ConflictAction.reload) {
          if (shareToken != null) {
            await loadSharedReport(shareToken);
          } else {
            await _loadReportFromServer(serverId);
          }
          return _OpsSaveResult.saved;
        }
        if (action == ConflictAction.overwrite) {
          // Перезапись не переключает режим навсегда: следующий save снова
          // пробует ops-merge. Флаг _mergeOpsUnsupported ставится только когда
          // сервер честно сообщает, что не понимает ops-контракт.
          return _OpsSaveResult.fallbackLegacy;
        }
        continue; // resolved: пользователь разрешил — пробуем ops ещё раз
      }

      // Постоянный отказ доступа (403/410 или явный текст denied/expired).
      // 404 исключаем: под ним может быть старый сервер без ops-роута
      // (обрабатывается ниже как fallbackLegacy). Если отчёт действительно
      // удалён — отвязку выполнит legacy-путь _saveReportToServer.
      final isDenial =
          result.statusCode == 403 ||
          result.statusCode == 410 ||
          (result.isPermanentAccessDenied && result.statusCode != 404);
      if (isDenial) {
        await _detachServerLinkIfDenied();
        return _OpsSaveResult.failed;
      }

      // Код 4xx/5xx без VERSION_CONFLICT — вероятно, сервер без ops.
      // НЕ ставим _mergeOpsUnsupported навсегда: fallback разовый для этого
      // сохранения, следующий save снова пробует ops-merge.
      if (result.statusCode == 400 ||
          result.statusCode == 404 ||
          result.statusCode == 405) {
        return _OpsSaveResult.fallbackLegacy;
      }
      _lastSyncError = result.error != null && result.error!.isNotEmpty
          ? result.error
          : 'HTTP ${result.statusCode ?? 'error'}';
      return _OpsSaveResult.failed;
    }
    _lastSyncError = 'Save retry limit exceeded';
    return _OpsSaveResult.failed;
  }

  /// Обновить `_baseReportSnapshot` актуальной серверной версией, НЕ трогая
  /// `_currentReport` (сохраняет несохранённые локальные правки). Используется
  /// при гонке версий (409 без conflicts): пересобираем ops от свежей базы и
  /// пробуем снова.
  Future<bool> _refreshBaseSnapshotFromServer() async {
    final shareToken = (_shareToken == null || _shareToken!.isEmpty)
        ? null
        : _shareToken;
    try {
      if (shareToken != null) {
        final result = await ApiService.getShareInfo(token: shareToken);
        final reportData = result.data?['report']?['reportData'];
        if (!result.success || reportData is! Map) {
          _lastSyncError = result.error ?? 'Failed to refresh report';
          return false;
        }
        _baseReportSnapshot = Map<String, dynamic>.from(reportData);
        final version = result.data?['report']?['version'];
        _serverReportVersion = version is int
            ? version
            : int.tryParse(version.toString());
        return true;
      }

      final serverId = _serverReportId;
      if (serverId == null) return false;
      final result = await ApiService.getReport(serverId);
      final reportData = result.data?['report']?['reportData'];
      if (!result.success || reportData is! Map) {
        _lastSyncError = result.error ?? 'Failed to refresh report';
        return false;
      }
      _baseReportSnapshot = Map<String, dynamic>.from(reportData);
      final version = result.data?['report']?['version'];
      _serverReportVersion = version is int
          ? version
          : int.tryParse(version.toString());
      return true;
    } catch (e) {
      _lastSyncError = e.toString();
      return false;
    }
  }

  /// Разобрать новый (merge-by-ID) 409 и спроецировать на существующий диалог.
  ConflictDetails? _parseCellConflicts(dynamic raw) {
    if (raw is! Map) return null;
    final currentVersion = raw['currentVersion'] is int
        ? raw['currentVersion'] as int
        : 0;
    final conflictsRaw = raw['conflicts'];
    if (conflictsRaw is! List || conflictsRaw.isEmpty) return null;

    final out = <AnswerConflict>[];
    for (final c in conflictsRaw) {
      if (c is! Map) continue;
      final qid = c['qid']?.toString();
      final rid = c['rid']?.toString();
      final lang = c['lang']?.toString() ?? '';
      final field = c['field']?.toString();
      final serverText = c['serverText']?.toString() ?? '';
      final clientText = c['clientText']?.toString() ?? '';
      final serverUpdatedAt = c['serverUpdatedAt'] is int
          ? c['serverUpdatedAt'] as int
          : null;
      final clientUpdatedAt = c['clientUpdatedAt'] is int
          ? c['clientUpdatedAt'] as int
          : null;
      final serverAuthor = c['serverAuthor']?.toString();

      int qIndex = -1;
      int aIndex = -1;
      if (qid != null && _currentReport != null) {
        qIndex = _currentReport!.questions.indexWhere((q) => q.qid == qid);
        if (rid != null && qIndex >= 0) {
          aIndex = _answerIndexByRid(qIndex, rid);
        }
      }
      // Fallback: legacy-сервер мог вернуть индексы напрямую.
      if (qIndex < 0) {
        qIndex = c['questionIndex'] is int ? c['questionIndex'] as int : -1;
      }
      if (aIndex < 0) {
        aIndex = c['answerIndex'] is int ? c['answerIndex'] as int : -1;
      }
      if (qIndex < 0 || aIndex < 0) continue;

      out.add(
        AnswerConflict(
          questionIndex: qIndex,
          answerIndex: aIndex,
          language: lang,
          serverText: serverText,
          clientText: clientText,
          qid: qid,
          rid: rid,
          field: field,
          clientUpdatedAt: clientUpdatedAt,
          serverUpdatedAt: serverUpdatedAt,
          serverAuthor: (serverAuthor != null && serverAuthor.isEmpty)
              ? null
              : serverAuthor,
        ),
      );
    }
    if (out.isEmpty) return null;
    return ConflictDetails(
      currentVersion: currentVersion,
      answerConflicts: out,
    );
  }

  /// Индекс строки (ряда) ответа в вопросе по её rid.
  int _answerIndexByRid(int questionIndex, String rid) {
    final report = _currentReport;
    if (report == null) return -1;
    final key = questionIndex.toString();
    final markerList = report.markers[key];
    if (markerList != null) {
      for (var i = 0; i < markerList.length; i++) {
        if (markerList[i].rowId == rid) return i;
      }
    }
    final langMap = report.translations[key];
    if (langMap != null) {
      for (final answers in langMap.values) {
        for (var i = 0; i < answers.length; i++) {
          if (answers[i].rowId == rid) return i;
        }
      }
    }
    return -1;
  }

  /// После 409 ставим базу ячеек равной серверной версии, чтобы повторные
  /// ops несли корректный baseUpdatedAt/baseText/author и не конфликтовали
  /// повторно.
  void _rebaseBaseToServer(ConflictDetails details) {
    final base = _baseReportSnapshot;
    if (base == null) return;
    final canonicalAnswers = base['answers'];
    final legacyTranslations = base['translations'];

    for (final c in details.answerConflicts) {
      // Legacy-зеркало в базе (индексный путь).
      if (legacyTranslations is Map) {
        final perLang = legacyTranslations[c.questionIndex.toString()];
        if (perLang is Map) {
          final list = perLang[c.language];
          if (list is List && c.answerIndex < list.length) {
            final cell = (list[c.answerIndex] as Map);
            cell['text'] = c.serverText;
            cell['_empty'] = c.serverText.isEmpty;
            if (c.serverUpdatedAt != null) {
              cell['updatedAt'] = c.serverUpdatedAt;
            }
            if (c.serverAuthor != null) cell['authorId'] = c.serverAuthor;
          }
        }
      }
      // Canonical-часть базы (qid/rid).
      if (c.qid != null && c.rid != null && canonicalAnswers is Map) {
        final rows = canonicalAnswers[c.qid];
        if (rows is List) {
          for (final rowRaw in rows) {
            if (rowRaw is! Map) continue;
            if ((rowRaw['rid']?.toString() ?? '') != c.rid) continue;
            final cells = rowRaw['localizations'];
            if (cells is Map) {
              final cell = cells[c.language];
              if (cell is Map) {
                cell['text'] = c.serverText;
                cell['isEmpty'] = c.serverText.isEmpty;
                if (c.serverUpdatedAt != null) {
                  cell['updatedAt'] = c.serverUpdatedAt;
                }
                if (c.serverAuthor != null) {
                  cell['authorId'] = c.serverAuthor;
                }
              }
            }
          }
        }
      }
    }
  }

  /// Применить серверный `merged`-документ как новое состояние и новую базу.
  Future<void> _applyMergedSnapshot(
    Map<String, dynamic> merged,
    dynamic newVersion,
  ) async {
    final prevLanguage = _currentReport?.currentLanguage;
    final prevCounter = _currentReport?.mediaCounter;
    final folderPath = _currentReportPath ?? (_serverReportId?.toString());
    _currentReport = Report.fromJson(merged, folderPath: folderPath);
    // Счётчик имён медиа должен быть монотонным: если серверный документ
    // потерял mediaCounter (старый сервер / share-путь) — наследуем прежний,
    // иначе новое фото получит имя уже существующего файла и перезапишет его.
    _mergeMediaCounters(prevCounter, _currentReport!.mediaCounter);
    if (prevLanguage != null &&
        prevLanguage.isNotEmpty &&
        _currentReport?.availableLanguages.contains(prevLanguage) == true) {
      _currentReport!.currentLanguage = prevLanguage;
    }
    // Runtime-URL (webUrl/thumbnailUrl) в JSON не живут: после merged фото,
    // добавленные другими устройствами, остались бы «битыми» до перезагрузки.
    final shareToken = _shareToken;
    if (shareToken != null && shareToken.isNotEmpty) {
      _populateMediaWebUrlsForShare();
    } else if (_serverReportId != null) {
      await _populateMediaWebUrls(_serverReportId!);
    }
    if (newVersion != null) {
      _serverReportVersion = newVersion is int
          ? newVersion
          : int.tryParse(newVersion.toString());
    }
    _baseReportSnapshot = merged;
    notifyListeners();
  }

  /// По каждому ключу берём максимум из прежнего и нового счётчика
  /// (или прежнее значение, если в новом документе ключа нет).
  void _mergeMediaCounters(Map<String, int>? prev, Map<String, int> next) {
    if (prev == null) return;
    for (final entry in prev.entries) {
      final existing = next[entry.key];
      next[entry.key] = existing == null
          ? entry.value
          : (entry.value > existing ? entry.value : existing);
    }
  }

  /// ID отчёта на сервере (используется на web для обновления существующего отчёта).
  int? _serverReportId;

  /// Была ли при последнем сохранении отвязана локальная копия от сервера
  /// из-за истечения права (403/404/410). Проверяется UI для сообщения.
  bool _serverLinkDetachedOnDeny = false;

  /// Прочитать и сбросить флаг отвязки (одноразово, для показа сообщения).
  bool consumeServerLinkDetachedOnDeny() {
    final value = _serverLinkDetachedOnDeny;
    _serverLinkDetachedOnDeny = false;
    return value;
  }

  /// Публичный идентификатор отчёта для URL просмотра.
  String? _serverPublicId;

  /// Папка отчёта в KS3 (например, "reports/abc-123/").
  /// Заполняется после первого сохранения отчёта на сервер.
  /// Используется для загрузки медиафайлов в правильную папку.
  String? _ks3Folder;

  /// Токен share-ссылки. Если задан — отчёт работает в режиме
  /// публичной ссылки, без авторизации.
  String? _shareToken;

  /// ID текущего пользователя (авторизованного) для сравнения с authorId
  /// ячеек. Если null — значит анонимный режим (share-ссылка).
  int? _currentUserId;

  /// Тот же authorId, что сервер присваивает ячейкам текущего пользователя:
  /// `user:<id>` для авторизованного, `share:<token>:<anonymousId>` для
  /// share-режима (см. reportsService.patchReportOps / shareController).
  String? get _myAuthorId {
    if (_shareToken != null && _shareToken!.isNotEmpty) {
      final anon = _anonymousAuthorId;
      if (anon == null || anon.isEmpty) return null;
      return 'share:${_shareToken!}:$anon';
    }
    final id = _currentUserId;
    if (id == null) return null;
    return 'user:$id';
  }

  String? _anonymousAuthorId;

  /// Множество уже виденных на экране ключей ответов `qid:rid`.
  /// Используется, чтобы подсветить только впервые появившиеся ответы
  /// других пользователей.
  final Set<String> _seenAnswerKeys = {};

  /// Установить ID текущего пользователя (из AuthProvider).
  void setCurrentUserId(int? id) => _currentUserId = id;

  /// Установить anonymousId (share-режим) — из него собирается authorId
  /// `share:<token>:<anonymousId>`, под которым сервер штампует ячейки.
  void setAnonymousAuthorId(String? id) => _anonymousAuthorId = id;

  /// Вернуть true, если ответ с данным ключом впервые появился на экране
  /// и был создан другим пользователем (authorId != мой).
  ///
  /// [authorIsAnonymous] — признак ячейки-заглушки (пустая ячейка без автора:
  /// и клиент, и сервер помечают их `anon:<uuid>` + `authorIsAnonymous`).
  /// Такие ячейки «чужими ответами» не считаются.
  ///
  /// При первом вызове помечает ключ как «виденный», поэтому повторный
  /// вызов вернёт false — подсветка срабатывает ровно один раз.
  bool isForeignNewAnswer(
    String qid,
    String? rid,
    String? authorId, {
    bool authorIsAnonymous = false,
  }) {
    final myId = _myAuthorId;
    if (myId == null) return false;
    if (authorIsAnonymous) return false;
    if (authorId == null || authorId.isEmpty) return false;
    if (authorId == myId) return false;
    if (rid == null || rid.isEmpty) return false;
    final key = '$qid:$rid';
    if (_seenAnswerKeys.contains(key)) return false;
    _seenAnswerKeys.add(key);
    return true;
  }

  /// Callback для отображения диалога конфликта версий (409).
  /// Устанавливается из UI (например, FormFillScreen).
  Future<ConflictAction> Function(ConflictDetails)? onVersionConflict;

  /// Геттеры для внешнего доступа
  int? get serverReportId => _serverReportId;
  int? get serverReportVersion => _serverReportVersion;
  String? get serverPublicId => _serverPublicId;
  String? get ks3Folder => _ks3Folder;
  String? get shareToken => _shareToken;

  /// Причина последней неудачной операции сохранения/синхронизации.
  String? get lastSyncError => _lastSyncError;

  /// Сохранить отчёт на сервер (web-режим).
  ///
  /// Если активна share-ссылка — сохраняем через неё.
  /// Иначе если _serverReportId уже задан — обновляем существующий отчёт.
  /// Иначе — создаём новый и запоминаем ID.
  Future<bool> _saveReportToServer() async {
    try {
      final jsonData = _currentReport!.toJson();
      final title = _currentReport!.reportName.isNotEmpty
          ? _currentReport!.reportName
          : 'Report ${DateTime.now().millisecondsSinceEpoch}';

      ApiResult result;
      if (_shareToken != null && _shareToken!.isNotEmpty) {
        result = await _saveSharedReportToServer(title, jsonData);
      } else {
        result = await ApiService.saveReport(
          title: title,
          reportData: jsonData,
          reportId: _serverReportId,
          baseVersion: _serverReportVersion,
          baseSnapshot: _baseReportSnapshot,
        );
      }

      // Обработка конфликта версий (409).
      if (!result.success &&
          result.data?['code'] == 'VERSION_CONFLICT' &&
          onVersionConflict != null) {
        final currentVersion = result.data!['currentVersion'] as int? ?? 1;
        final conflicts = _parseAnswerConflicts(result.data!['conflicts']);
        final details = ConflictDetails(
          currentVersion: currentVersion,
          answerConflicts: conflicts,
        );
        final action = await onVersionConflict!(details);
        if (action == ConflictAction.reload) {
          // Перезагружаем отчёт с сервера — локальные изменения будут потеряны.
          if (_shareToken != null && _shareToken!.isNotEmpty) {
            return await loadSharedReport(_shareToken!);
          }
          if (_serverReportId != null) {
            return await _loadReportFromServer(_serverReportId!);
          }
          return false;
        }
        if (action == ConflictAction.overwrite) {
          // Пользователь решил сохранить поверх: повторяем без baseSnapshot/baseVersion.
          if (_shareToken != null && _shareToken!.isNotEmpty) {
            result = await _saveSharedReportToServer(
              title,
              jsonData,
              withLock: false,
            );
          } else {
            result = await ApiService.saveReport(
              title: title,
              reportData: jsonData,
              reportId: _serverReportId,
            );
          }
        }
        if (action == ConflictAction.resolved) {
          // UI уже разрешил конфликты ответов внутри провайдера.
          // Повторяем сохранение с актуальным baseSnapshot.
          if (_shareToken != null && _shareToken!.isNotEmpty) {
            result = await _saveSharedReportToServer(
              title,
              _currentReport!.toJson(),
            );
          } else {
            result = await ApiService.saveReport(
              title: title,
              reportData: _currentReport!.toJson(),
              reportId: _serverReportId,
              baseVersion: _serverReportVersion,
              baseSnapshot: _baseReportSnapshot,
            );
          }
        }
      }

      if (result.success && result.data?['report'] != null) {
        // Запоминаем ID отчёта на сервере (для будущих обновлений)
        final id = result.data!['report']['id'];
        _serverReportId = id is int ? id : int.tryParse(id.toString());
        // Запоминаем публичный идентификатор (для URL просмотра)
        final publicId = result.data!['report']['publicId'];
        if (publicId is String && publicId.isNotEmpty) {
          _serverPublicId = publicId;
        }
        // Запоминаем папку KS3 (для загрузки медиафайлов)
        final folder = result.data!['report']['ks3Folder'];
        if (folder is String && folder.isNotEmpty) {
          _ks3Folder = folder;
        }
        // Запоминаем версию отчёта (optimistic locking)
        final version = result.data!['report']['version'];
        _serverReportVersion = version is int
            ? version
            : int.tryParse(version.toString());
        // Обновляем baseSnapshot — теперь серверная версия является новой базой.
        _baseReportSnapshot = _currentReport?.toJson();
        if (kDebugMode) {
          debugPrint(
            'saveReport (web): saved as ID=$_serverReportId, pid=$_serverPublicId, folder=$_ks3Folder, version=$_serverReportVersion',
          );
        }

        // После сохранения отчёта — запускаем загрузку фото шапки, если оно
        // было добавлено через addHeaderImageFromBytes. Медиа ответов здесь
        // не трогаем: дозаливкой управляет saveReportToServer (см. его конец).
        if (_ks3Folder != null && _serverReportId != null) {
          if (_headerImageBytes != null && _headerImageFileName != null) {
            _uploadHeaderImageToServer().catchError((e) {
              if (kDebugMode) debugPrint('Header image upload error: $e');
            });
          }
        }

        // На native сохраняем привязку к серверу в папке отчёта, чтобы
        // после перезапуска приложение знало: отчёт уже есть в облаке.
        if (!kIsWeb && _currentReportPath != null) {
          try {
            final metaFile = File('$_currentReportPath/sync_meta.json');
            await metaFile.writeAsString(
              jsonEncode({
                'serverReportId': _serverReportId,
                'serverPublicId': _serverPublicId,
                'serverVersion': _serverReportVersion,
                'ks3Folder': _ks3Folder,
              }),
            );
          } catch (e) {
            if (kDebugMode) debugPrint('sync_meta write error: $e');
          }
        }

        return true;
      } else {
        if (result.isPermanentAccessDenied) {
          // Право на редактирование истекло (403/404/410) — локальная копия
          // больше не связана с сервером. Снимаем привязку, чтобы отчёт
          // остался обычным локальным и его можно было залить заново.
          if (await _detachServerLinkIfDenied()) {
            if (kDebugMode) {
              debugPrint('saveReport: server link detached on deny');
            }
          }
        }
        _lastSyncError = result.error != null && result.error!.isNotEmpty
            ? result.error
            : 'HTTP ${result.statusCode ?? 'error'}';
        if (kDebugMode) debugPrint('saveReport (web): $_lastSyncError');
        return false;
      }
    } catch (e) {
      _lastSyncError = e.toString();
      if (kDebugMode) debugPrint('saveReport (web) error: $e');
      return false;
    }
  }

  /// Сохранить отчёт через share-ссылку.
  /// [withLock] — если false, не передаёт baseVersion (для overwrite поверх конфликта).
  Future<ApiResult> _saveSharedReportToServer(
    String title,
    Map<String, dynamic> jsonData, {
    bool withLock = true,
  }) async {
    final anonymousId = await AnonymousIdService.getId();
    return ApiService.saveSharedReport(
      token: _shareToken!,
      reportData: jsonData,
      anonymousId: anonymousId,
      baseVersion: withLock ? _serverReportVersion : null,
    );
  }

  /// Разобрать список конфликтов ответов из тела 409-ответа сервера.
  List<AnswerConflict> _parseAnswerConflicts(dynamic raw) {
    final result = <AnswerConflict>[];
    if (raw is! List) return result;
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        result.add(
          AnswerConflict(
            questionIndex: item['questionIndex'] as int? ?? 0,
            answerIndex: item['answerIndex'] as int? ?? 0,
            language: item['language'] as String? ?? 'RU',
            serverText: item['serverText'] as String? ?? '',
            clientText: item['clientText'] as String? ?? '',
          ),
        );
      }
    }
    return result;
  }

  /// Обновить текст в baseSnapshot для разрешения конфликта ответа.
  /// Нужно, чтобы при повторном сохранении сервер не считал этот ответ
  /// изменённым другим пользователем.
  void _updateBaseAnswerText(
    int questionIndex,
    int answerIndex,
    String language,
    String text,
  ) {
    if (_baseReportSnapshot == null) return;
    final qid = questionIndex.toString();
    final translations =
        _baseReportSnapshot!['translations'] as Map<String, dynamic>?;
    final langMap = translations?[qid] as Map<String, dynamic>?;
    final answers = langMap?[language] as List<dynamic>?;
    if (answers != null && answerIndex < answers.length) {
      final answer = answers[answerIndex] as Map<String, dynamic>;
      answer['text'] = text;
      answer['_empty'] = text.isEmpty;
    }
  }

  /// Принять серверный ответ: заменить локальный текст на серверный.
  void useServerAnswerForConflict(
    int questionIndex,
    int answerIndex,
    String language,
    String serverText,
  ) {
    updateAnswerText(
      questionIndex,
      answerIndex,
      serverText,
      language: language,
    );
    _updateBaseAnswerText(questionIndex, answerIndex, language, serverText);
    notifyListeners();
  }

  /// Оставить свой ответ: baseSnapshot приводим к серверному,
  /// чтобы перезаписать серверный вариант своим (возможно отредактированным).
  void keepOwnAnswerForConflict(
    int questionIndex,
    int answerIndex,
    String language,
    String serverText,
    String ownText,
  ) {
    _updateBaseAnswerText(questionIndex, answerIndex, language, serverText);
    updateAnswerText(questionIndex, answerIndex, ownText, language: language);
    notifyListeners();
  }

  /// Сохранить свой ответ как второй ответ на тот же вопрос.
  /// Серверный вариант остаётся на месте, пользовательский добавляется в конец.
  void saveAsSecondAnswerForConflict(
    int questionIndex,
    int answerIndex,
    String language,
    String serverText,
    String ownText,
  ) {
    updateAnswerText(
      questionIndex,
      answerIndex,
      serverText,
      language: language,
    );
    _updateBaseAnswerText(questionIndex, answerIndex, language, serverText);
    addAnswer(questionIndex);
    final newIndex =
        (_currentReport
                ?.getAnswersForQuestion(
                  questionIndex,
                  _currentReport!.currentLanguage,
                )
                .length ??
            1) -
        1;
    updateAnswerText(questionIndex, newIndex, ownText, language: language);
    notifyListeners();
  }

  Future<bool> loadReport(String folderName) async {
    try {
      // ===== Web: загружаем с сервера =====
      // folderName на web = ID отчёта на сервере
      if (kIsWeb) {
        final reportId = int.tryParse(folderName) ?? 0;
        // Сначала пробуем загрузить как владельца
        final ok = await _loadReportFromServer(reportId);
        if (ok) return true;

        // Если не вышло (нет JWT) — пробуем через сохранённые share-токены
        final shareTokens = await ShareTokenStorage.getTokens();
        for (final token in shareTokens) {
          try {
            final anonymousId = await AnonymousIdService.getId();
            final shareResult = await ApiService.getShareInfo(
              token: token,
              anonymousId: anonymousId,
            );
            if (shareResult.success && shareResult.data != null) {
              final report = shareResult.data!['report'] ?? {};
              final id = report['id'];
              final idStr = id is int ? id.toString() : id.toString();
              if (idStr == folderName) {
                // Нашли share-токен для этого отчёта
                return await loadSharedReport(token);
              }
            } else if (shareResult.statusCode == 404 ||
                shareResult.statusCode == 410) {
              // Протухший токен — удаляем, чтобы не накапливался мусор.
              await ShareTokenStorage.removeToken(token);
            }
          } catch (_) {}
        }
        return false;
      }

      // ===== Mobile/Desktop: загружаем локально =====
      // Сбрасываем привязку к серверу от предыдущего открытого отчёта.
      _serverReportId = null;
      _serverReportVersion = null;
      _serverPublicId = null;
      _ks3Folder = null;
      _serverLinkDetachedOnDeny = false;

      final folder = Directory(folderName);
      if (!await folder.exists()) return false;
      final jsonFile = File('${folder.path}/$reportFilename');
      if (!await jsonFile.exists()) return false;
      final jsonString = await jsonFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final wasLegacy = jsonData['schemaVersion'] != 2;
      _currentReport = Report.fromJson(jsonData, folderPath: folderName);
      _currentReportPath = folderName;
      await _restoreServerLinkFromLocalFolder(folder.path);

      // Старый (schemaVersion 1) отчёт мигрирован в v2 (добавлены qid/rid,
      // авторская метадата). Сразу автосохраняем локально, чтобы id не
      // пересоздавались при каждом последующем открытии до первого save.
      if (wasLegacy) {
        try {
          await jsonFile.writeAsString(jsonEncode(_currentReport!.toJson()));
        } catch (e) {
          if (kDebugMode) debugPrint('Autosave migration (v1->v2) error: $e');
        }
      }

      // База для diff-движка (Фаза 2) — состояние на момент открытия.
      _baseReportSnapshot = _currentReport?.toJson();

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading report: $e');
      return false;
    }
  }

  /// Восстановить привязку локального отчёта к серверу (native).
  ///
  /// Связь с серверной копией хранится в папке отчёта: в файле
  /// sync_meta.json (после заливки/синхронизации) либо закодирована
  /// в имени папки со служебным префиксом server_ (после скачивания
  /// с сервера).
  /// Без этого приложение не знало бы, что отчёт уже есть в облаке, и
  /// кнопка «Залить на сервер» создавала бы дубликат.
  Future<void> _restoreServerLinkFromLocalFolder(String folderPath) async {
    final metaFile = File('$folderPath/sync_meta.json');
    if (await metaFile.exists()) {
      try {
        final meta =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        final id = meta['serverReportId'] ?? meta['id'];
        if (id != null) {
          _serverReportId = id is int ? id : int.tryParse(id.toString());
        }
        final publicId = meta['serverPublicId'] ?? meta['publicId'];
        if (publicId is String && publicId.isNotEmpty) {
          _serverPublicId = publicId;
        }
        final version = meta['serverVersion'] ?? meta['version'];
        if (version != null) {
          _serverReportVersion = version is int
              ? version
              : int.tryParse(version.toString());
        }
        final ks3 = meta['ks3Folder'];
        if (ks3 is String && ks3.isNotEmpty) {
          _ks3Folder = ks3;
        }
        return;
      } catch (_) {
        // Повреждённый sync_meta.json — пробуем определить по имени папки.
      }
    }
    final folderName = folderPath.split(Platform.pathSeparator).last;
    if (folderName.startsWith('server_')) {
      _serverReportId = int.tryParse(folderName.substring('server_'.length));
    }
  }

  /// Родительская папка для пути (строковая операция — не использует
  /// Directory.parent, которого нет в web-заглушке platform_io_web).
  static String _parentDirOf(String path) {
    final sep = Platform.pathSeparator;
    var p = path;
    if (p.endsWith(sep)) p = p.substring(0, p.length - 1);
    final idx = p.lastIndexOf(sep);
    if (idx <= 0) return p.isEmpty ? sep : p;
    return p.substring(0, idx);
  }

  /// Снять привязку текущего отчёта к серверу после истечения права.
  ///
  /// Удаляет sync_meta.json, переименовывает папку `server_<id>` →
  /// `report_<ts>_detached` (чтобы привязка не восстанавливалась),
  /// очищает серверные id и (для share) удаляет сохранённый токен.
  /// Папки скрытых рабочих копий (cloud_cache) переносятся в библиотеку
  /// «Мои отчёты», чтобы локальные правки не потерялись при очистке кэша.
  /// После этого отчёт — обычный локальный; его можно заново залить
  /// на сервер под новым ID.
  Future<void> _detachCurrentReportServerLink() async {
    final folderPath = _currentReportPath;
    try {
      if (folderPath != null) {
        final dir = Directory(folderPath);
        if (await dir.exists()) {
          final meta = File(
            '$folderPath${Platform.pathSeparator}sync_meta.json',
          );
          if (await meta.exists()) await meta.delete();
          final name = folderPath.split(Platform.pathSeparator).last;
          final parentDir = _parentDirOf(folderPath);
          final parentName = parentDir.split(Platform.pathSeparator).last;
          if (name.startsWith('server_')) {
            final newName =
                'report_${DateTime.now().millisecondsSinceEpoch}_detached';
            final String newPath;
            if (parentName == 'cloud_cache') {
              // Переносим скрытую рабочую копию в библиотеку отчётов.
              final libraryDir =
                  '${_parentDirOf(parentDir)}${Platform.pathSeparator}reports';
              await Directory(libraryDir).create(recursive: true);
              newPath = '$libraryDir${Platform.pathSeparator}$newName';
            } else {
              newPath = '$parentDir${Platform.pathSeparator}$newName';
            }
            await dir.rename(newPath);
            _currentReportPath = newPath;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('detach server link error: $e');
    }
    if (_shareToken != null && _shareToken!.isNotEmpty) {
      final t = _shareToken!;
      _shareToken = null;
      try {
        await ShareTokenStorage.removeToken(t);
      } catch (_) {}
    }
    _serverReportId = null;
    _serverReportVersion = null;
    _serverPublicId = null;
    _ks3Folder = null;
    _serverLinkDetachedOnDeny = true;
    notifyListeners();
  }

  /// Снять привязку к серверу, если сервер ответил постоянным отказом
  /// (403/404/410) и открыт локальный отчёт, ранее связанный с облаком.
  ///
  /// На web локальных копий нет (всё хранится на сервере), поэтому там
  /// отвязка не выполняется. Возвращает true, если привязка была снята —
  /// UI должен показать сообщение «отчёт теперь локальный».
  Future<bool> _detachServerLinkIfDenied() async {
    if (kIsWeb) return false;
    if (_currentReportPath == null) return false;
    final linked =
        _serverReportId != null ||
        (_serverPublicId?.isNotEmpty ?? false) ||
        (_shareToken?.isNotEmpty ?? false);
    if (!linked) return false;
    await _detachCurrentReportServerLink();
    return true;
  }

  /// Загрузить отчёт с сервера по его строковому/числовому ID.
  /// Используется при открытии прямой ссылки /#/fill?reportId=xxx.
  Future<bool> loadReportByServerId(String reportId) async {
    // На web loadReport уже умеет загружать по числовому ID.
    if (kIsWeb) {
      return loadReport(reportId);
    }
    return false;
  }

  /// Загрузить отчёт с сервера по ID (web-режим).
  Future<bool> _loadReportFromServer(int reportId) async {
    try {
      final result = await ApiService.getReport(reportId);
      if (!result.success || result.data?['report'] == null) {
        if (kDebugMode) debugPrint('loadReport (web): ${result.error}');
        return false;
      }

      final reportData =
          result.data!['report']['reportData'] as Map<String, dynamic>;
      final prevLanguage = _currentReport?.currentLanguage;
      final folderPath = await _resolveLocalFolderPath(
        'server_$reportId',
        reuseExisting: _serverReportId == reportId,
      );
      _currentReport = Report.fromJson(reportData, folderPath: folderPath);
      if (prevLanguage != null &&
          prevLanguage.isNotEmpty &&
          _currentReport?.availableLanguages.contains(prevLanguage) == true) {
        _currentReport!.currentLanguage = prevLanguage;
      }
      _currentReportPath = folderPath;
      _serverReportId = reportId; // запоминаем для будущих сохранений
      // Сохраняем снимок отчёта при открытии — база для PATCH/merge.
      _baseReportSnapshot = reportData;

      // Запоминаем публичный идентификатор (для URL просмотра)
      final publicId = result.data!['report']['publicId'];
      if (publicId is String && publicId.isNotEmpty) {
        _serverPublicId = publicId;
      } else {
        _serverPublicId = null;
      }

      // Запоминаем папку KS3 (для загрузки новых медиа в правильную папку)
      final folder = result.data!['report']['ks3Folder'];
      if (folder is String && folder.isNotEmpty) {
        _ks3Folder = folder;
      } else {
        _ks3Folder = null;
      }

      // Запоминаем версию отчёта (optimistic locking)
      final version = result.data!['report']['version'];
      _serverReportVersion = version is int
          ? version
          : int.tryParse(version.toString());

      // Заполняем webUrl для медиа — presigned URL с KS3.
      // Без этого на web фото/видео не отображаются (webBytes пустой,
      // localPath бесполезен т.к. ФС недоступна).
      await _populateMediaWebUrls(reportId);

      // Сбрасываем "застрявшие" флаги обработки, т.к. отчёт загружен
      // с сервера и все медиа уже на KS3.
      _sanitizeMediaState();

      if (kDebugMode) {
        debugPrint(
          'loadReport (web): ID=$_serverReportId, pid=$_serverPublicId, folder=$_ks3Folder',
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('loadReport (web) error: $e');
      return false;
    }
  }

  /// Загрузить отчёт, открытый по share-ссылке.
  Future<bool> loadSharedReport(String token) async {
    try {
      // Тот же токен, что уже открыт (перезагрузка при конфликте/синке) —
      // локальную папку нужно сохранить, иначе локальные фото «потеряются».
      final sameShare = _shareToken == token;
      _shareToken = token;
      final result = await ApiService.getShareInfo(token: token);
      if (!result.success || result.data?['report'] == null) {
        if (kDebugMode) debugPrint('loadSharedReport: ${result.error}');
        return false;
      }

      // Для получения полных данных отчёта используем тот же endpoint,
      // что и welcome-экран, но нас интересует только reportData.
      // Чтобы не дублировать endpoint, получаем HTML-версию? Нет —
      // лучше расширить getShareInfo, чтобы он возвращал reportData.
      // Пока обойдёмся: загрузим HTML не нужен, нам нужен JSON.
      // Добавим отдельный запрос к save endpoint? Нет, это save.
      //
      // Решение: расширяем getShareInfo, чтобы включать reportData.
      // TODO: добавить reportData в ответ getShareInfo.
      if (result.data!['report']['reportData'] == null) {
        if (kDebugMode) {
          debugPrint('loadSharedReport: reportData not in share info');
        }
        return false;
      }

      final reportData =
          result.data!['report']['reportData'] as Map<String, dynamic>;
      // На native отчёту нужна РЕАЛЬНАЯ локальная папка. Раньше здесь
      // оставалось относительное имя (сам токен), поэтому запись фото падала
      // с EROFS (errno 30): Directory('<token>/photos') разрешался от
      // рабочей директории процесса, на Android это «/» (read-only).
      final folderPath = await _resolveLocalFolderPath(
        'share_$token',
        reuseExisting: sameShare,
      );
      _currentReport = Report.fromJson(reportData, folderPath: folderPath);
      _currentReportPath = folderPath;
      _serverReportId = result.data!['report']['id'] is int
          ? result.data!['report']['id']
          : int.tryParse(result.data!['report']['id'].toString());
      _serverPublicId = result.data!['report']['publicId']?.toString();
      _ks3Folder = result.data!['report']['ks3Folder']?.toString();
      final version = result.data!['report']['version'];
      _serverReportVersion = version is int
          ? version
          : int.tryParse(version.toString());
      _baseReportSnapshot = reportData;

      await _populateMediaWebUrlsForShare();

      // Сбрасываем "застрявшие" флаги обработки, т.к. отчёт загружен с сервера.
      _sanitizeMediaState();

      if (kDebugMode) {
        debugPrint(
          'loadSharedReport: token=$token, ID=$_serverReportId, folder=$_ks3Folder',
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('loadSharedReport error: $e');
      return false;
    }
  }

  /// Заполнить MediaItem.webUrl proxy-ссылками через share-ссылку.
  ///
  /// Использует endpoint /view/report/:publicId/files/:path?share_token=...
  /// (тот же, что и для HTML-просмотра). Не требует serverFileId —
  /// доступ определяется по localPath и share-токену.
  Future<void> _populateMediaWebUrlsForShare() async {
    if (_currentReport == null || _shareToken == null) return;
    final publicId = _serverPublicId;
    if (publicId == null || publicId.isEmpty) return;

    _currentReport!.markers.forEach((qid, markersList) {
      for (final markers in markersList) {
        for (final media in markers.media) {
          if (media.localPath == null || media.localPath!.isEmpty) continue;
          final uri = ApiService.uri(
            '/view/report/$publicId/files/${media.localPath}',
            {'share_token': _shareToken},
          );
          media.webUrl = uri.toString();
          // Для фото — миниатюра через тот же прокси: сервер отдаёт
          // превью из KS3 (при отсутствии — генерирует через sharp).
          if (media.type.startsWith('image/')) {
            media.thumbnailUrl = ApiService.uri(
              '/view/report/$publicId/thumbnails/${media.localPath}',
              {'share_token': _shareToken},
            ).toString();
          }
        }
      }
    });
  }

  /// Создать share-ссылку на текущий отчёт.
  /// Требует, чтобы отчёт уже был сохранён на сервере (_serverReportId).
  Future<ApiResult> createShareLink({
    DateTime? expiresAt,
    String permissions = 'edit',
  }) async {
    if (_serverReportId == null) {
      return const ApiResult(
        success: false,
        error: 'Отчёт ещё не сохранён на сервере',
      );
    }
    return ApiService.createShare(
      reportId: _serverReportId!,
      expiresAt: expiresAt,
      permissions: permissions,
    );
  }

  /// Публичный share-URL для токена: `scheme://host/#/welcome?token=...`.
  String _buildSharePublicUrl(String token) =>
      '${ApiService.scheme}://${ApiService.host}/#/welcome?token=$token';

  /// Получить список активных share-ссылок отчёта (для владельца).
  ///
  /// Возвращает пустой список, если отчёт не сохранён на сервере или
  /// активных ссылок нет. URL для каждой ссылки строится клиентски из
  /// активного scheme/host (в проде — easytab.cloud, https).
  Future<List<ShareLinkInfo>> listShareLinks() async {
    final reportId = _serverReportId;
    if (reportId == null) return const [];

    final result = await ApiService.listShares(reportId: reportId);
    if (!result.success || result.data == null) return const [];

    final raw = result.data!['shares'] ?? result.data;
    if (raw is! List) return const [];

    final now = DateTime.now();
    final out = <ShareLinkInfo>[];
    for (final e in raw) {
      if (e is! Map) continue;
      if (e['isActive'] != true) continue; // в списке только активные
      final token = e['token']?.toString();
      if (token == null || token.isEmpty) continue;

      final expiresRaw = e['expiresAt'];
      DateTime? expiresAt;
      if (expiresRaw is String) {
        expiresAt = DateTime.tryParse(expiresRaw);
      } else if (expiresRaw is num) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresRaw.toInt());
      }

      out.add(
        ShareLinkInfo(
          token: token,
          url: _buildSharePublicUrl(token),
          expiresAt: expiresAt,
          isActive: true,
          permissions: e['permissions']?.toString() ?? 'edit',
          createdAt: now,
        ),
      );
    }
    return out;
  }

  /// Относительный путь миниатюры изображения. Правило совпадает с
  /// `thumbnailService.getThumbnailStorageKey` на сервере: расширение
  /// заменяется на суффикс `_thumb.jpg` (`photos/a.jpg` → `photos/a_thumb.jpg`).
  String _imageThumbRelPath(String relPath) {
    final slash = relPath.lastIndexOf('/');
    final dot = relPath.lastIndexOf('.');
    if (dot <= slash) return '${relPath}_thumb.jpg';
    return '${relPath.substring(0, dot)}_thumb.jpg';
  }

  /// Заполнить MediaItem.webUrl presigned-ссылками с KS3.
  /// Вызывается после загрузки отчёта с сервера на web.
  /// Молча игнорирует ошибки сети — отчёт всё равно откроется,
  /// просто медиа покажутся плейсхолдерами.
  Future<void> _populateMediaWebUrls(int reportId) async {
    try {
      final urlsResult = await ApiService.getReportFileUrls(reportId);
      if (!urlsResult.success || urlsResult.data?['urls'] == null) return;

      final urlsData = urlsResult.data!['urls'] as Map<String, dynamic>;
      if (urlsData.isEmpty) return;

      // Проходим по всем markers (Map<qid, List<AnswerMarkers>>),
      // заполняем webUrl для каждого медиа.
      // Ключ в urlsData — relativePath (например "photos/f1_1_001.jpg"),
      // совпадает с MediaItem.localPath (который после fromJson уже относительный).
      _currentReport!.markers.forEach((qid, markersList) {
        for (final markers in markersList) {
          for (final media in markers.media) {
            if (media.localPath == null || media.localPath!.isEmpty) continue;
            // Пробуем точное совпадение по localPath, затем по name
            final url = urlsData[media.localPath] ?? urlsData[media.name];
            if (url is String && url.isNotEmpty) {
              media.webUrl = url;
            }
            // Для фото — URL миниатюры (ключ с суффиксом _thumb.jpg).
            // Сетка грузит миниатюру, полный файл — только в просмотрщике.
            if (media.type.startsWith('image/')) {
              final baseName = media.localPath!.split('/').last;
              final thumbUrl =
                  urlsData[_imageThumbRelPath(media.localPath!)] ??
                  urlsData[_imageThumbRelPath(baseName)];
              if (thumbUrl is String && thumbUrl.isNotEmpty) {
                media.thumbnailUrl = thumbUrl;
              }
            }
            // Для видео — ищем URL превью по thumbnailServerFileId.
            if (media.type.startsWith('video/') &&
                media.thumbnailServerFileId != null) {
              // Ищем thumbnail по относительному пути: thumb_видеоимя.jpg
              final baseName = media.localPath!.split('/').last;
              final thumbName = 'thumb_${baseName.split('.').first}.jpg';
              final thumbRelPath = media.localPath!.replaceAll(
                baseName,
                thumbName,
              );
              final thumbUrl = urlsData[thumbRelPath] ?? urlsData[thumbName];
              if (thumbUrl is String && thumbUrl.isNotEmpty) {
                media.thumbnailUrl = thumbUrl;
              }
            }
          }
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('_populateMediaWebUrls error: $e');
    }
  }

  /// Сбросить runtime-флаги обработки медиа (isCompressing, isUploading и т.д.).
  ///
  /// Нужен при загрузке отчёта с сервера, т.к. в сохранённом JSON эти флаги
  /// могли остаться включёнными после прерванной обработки. Без сброса
  /// на уже загруженных видео может "залипать" надпись "Сжатие...".
  void _sanitizeMediaState() {
    if (_currentReport == null) return;

    _compressedVideoPaths.clear();

    for (final markersList in _currentReport!.markers.values) {
      for (final markers in markersList) {
        for (final media in markers.media) {
          media.isCompressing = false;
          media.compressProgress = 0.0;
          media.isUploading = false;
          media.uploadProgress = 0.0;
        }
      }
    }
  }

  /// Сжать все видео отчёта на нативной платформе (v_video_compressor).
  ///
  /// [qualityLevel]: 1 — высокое качество, 2 — среднее, 3 — низкое
  /// (максимальное сжатие). [onProgress] вызывается с (текущий, всего)
  /// при обработке каждого видео.
  ///
  /// Видео ≤ 5 МБ и уже сжатые в этой сессии пропускаются. Сжатый файл
  /// копируется поверх оригинала, а [MediaItem.compressedSize] обновляется
  /// (оригинальный [MediaItem.fileSize] сохраняется для индикатора в UI).
  ///
  /// Возвращает список relativePath успешно сжатых видео.
  /// На web возвращает пустой список — там видео сжимается ffmpeg.wasm
  /// автоматически при добавлении.
  Future<List<String>> compressVideosWithSettings({
    required int qualityLevel,
    required void Function(int current, int total) onProgress,
  }) async {
    if (kIsWeb) return [];
    if (_currentReport == null || _currentReportPath == null) return [];

    // Собираем уникальные пути видео.
    final videoPaths = <String>[];
    for (final markersList in _currentReport!.markers.values) {
      for (final markers in markersList) {
        for (final media in markers.media) {
          final localPath = media.localPath;
          if (media.type.startsWith('video/') &&
              localPath != null &&
              !videoPaths.contains(localPath)) {
            videoPaths.add(localPath);
          }
        }
      }
    }
    if (videoPaths.isEmpty) return [];

    // Deferred: плагин v_video_compressor подгружается при первом вызове.
    await native_compress.loadLibrary();
    final compressedVideos = <String>[];

    for (int i = 0; i < videoPaths.length; i++) {
      onProgress(i + 1, videoPaths.length);
      final relativePath = videoPaths[i];
      if (_compressedVideoPaths.contains(relativePath)) continue;

      final absolutePath = '$_currentReportPath/$relativePath';
      final result = await native_compress.compressNativeVideo(
        absolutePath: absolutePath,
        relativePath: relativePath,
        qualityLevel: qualityLevel,
      );
      if (result == null) continue;

      _compressedVideoPaths.add(relativePath);
      compressedVideos.add(relativePath);

      for (final markersList in _currentReport!.markers.values) {
        for (final markers in markersList) {
          for (final media in markers.media) {
            if (media.localPath == relativePath) {
              media.compressedSize = result.compressedSize;
            }
          }
        }
      }
    }

    if (compressedVideos.isNotEmpty) notifyListeners();
    return compressedVideos;
  }

  /// Получить список всех отчётов.
  ///
  /// На web — загружает с сервера (через API).
  /// На mobile/desktop — читает локальную папку.
  ///
  /// Возвращает список карт: { 'id': String, 'name': String, 'modified': DateTime }
  Future<List<Map<String, dynamic>>> getAllReports() async {
    if (kIsWeb) {
      return await _listReportsFromServer();
    }
    return await _listLocalReports();
  }

  /// Загрузить список отчётов с сервера (web-режим).
  Future<List<Map<String, dynamic>>> _listReportsFromServer() async {
    try {
      final result = await ApiService.listReports();
      if (!result.success || result.data?['reports'] == null) {
        return [];
      }

      final reports = result.data!['reports'] as List;
      return reports.map((r) {
        return {
          'id': r['id'].toString(),
          'name': r['title'] as String? ?? 'Untitled',
          'modified':
              DateTime.tryParse(r['createdAt'] as String? ?? '') ??
              DateTime.now(),
          'author': (r['author'] ?? r['authorName'])?.toString(),
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('listReports (web) error: $e');
      return [];
    }
  }

  /// Получить список локальных отчётов (mobile/desktop).
  Future<List<Map<String, dynamic>>> _listLocalReports() async {
    try {
      final reportsDir = await _getReportsDir();
      final dir = Directory(reportsDir);
      if (!await dir.exists()) return [];

      final List<Map<String, dynamic>> reports = [];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final jsonFile = File('${entity.path}/$reportFilename');
          if (await jsonFile.exists()) {
            try {
              final jsonString = await jsonFile.readAsString();
              final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
              reports.add({
                'id': entity.path,
                'name': jsonData['name'] as String? ?? 'Untitled',
                'modified': await jsonFile.lastModified(),
              });
            } catch (_) {
              // Пропускаем повреждённые отчёты
            }
          }
        }
      }
      return reports;
    } catch (e) {
      if (kDebugMode) debugPrint('listLocalReports error: $e');
      return [];
    }
  }

  Future<bool> needsSyncAfterLoad() async {
    if (_currentReport == null) return false;
    final languages = _currentReport!.availableLanguages;
    if (languages.isEmpty) return false;

    // Если текущий язык - первый язык (по умолчанию), синхронизация не нужна
    if (_currentReport!.currentLanguage == languages.first) {
      return false;
    }

    return (await getUnsyncQuestionIndices()).isNotEmpty;
  }

  Future<String?> importProjectFromZip(String zipPath) async {
    try {
      final reportsDir = await _getReportsDir();
      final folderName = 'imported_${DateTime.now().millisecondsSinceEpoch}';
      final targetPath = '$reportsDir/$folderName';

      // Deferred: пакет archive подгружается при первом импорте.
      // Распаковка внутри сервиса защищена от path traversal (H-23).
      await zip_service.loadLibrary();
      final extracted = await zip_service.extractProjectZip(
        zipPath,
        targetPath,
      );
      if (!extracted) return null;

      final jsonFile = File('$targetPath/report.json');
      if (!await jsonFile.exists()) {
        await Directory(targetPath).delete(recursive: true);
        if (kDebugMode) debugPrint('report.json not found in ZIP');
        return null;
      }

      if (kDebugMode) debugPrint('Project imported successfully: $targetPath');
      return targetPath;
    } catch (e) {
      if (kDebugMode) debugPrint('Error importing project: $e');
      return null;
    }
  }

  Future<List<ReportInfo>> loadReportList() async {
    // ===== Web: загружаем список с сервера =====
    if (kIsWeb) {
      return await _loadReportListFromServer();
    }

    // ===== Mobile/Desktop: читаем локальную папку =====
    final reportsDir = await _getReportsDir();
    final dir = Directory(reportsDir);
    if (!await dir.exists()) return [];
    final List<ReportInfo> reports = [];
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final jsonFile = File('${entity.path}/$reportFilename');
          if (await jsonFile.exists()) {
            try {
              final jsonString = await jsonFile.readAsString();
              final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
              final name = jsonData['reportName'] as String? ?? 'Без названия';
              final timestamp = jsonData['timestamp'] as int?;
              final dateTime = timestamp != null
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                  : DateTime.now();
              final headerImagePath = jsonData['headerImagePath'] as String?;
              reports.add(
                ReportInfo(
                  folderName: entity.path,
                  name: name,
                  dateTime: dateTime,
                  thumbnailPath: headerImagePath,
                  publicId: null,
                ),
              );
            } catch (e) {
              continue;
            }
          }
        }
      }
      reports.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading report list: $e');
    }
    return reports;
  }

  /// Загрузить список отчётов с сервера (web-режим).
  ///
  /// Возвращает список ReportInfo, где folderName = ID отчёта на сервере.
  Future<List<ReportInfo>> _loadReportListFromServer() async {
    try {
      final List<ReportInfo> reportInfos = [];

      // 1. Загружаем отчёты пользователя (если авторизован)
      final result = await ApiService.listReports();
      if (result.success && result.data?['reports'] != null) {
        final reports = result.data!['reports'] as List;
        for (final r in reports) {
          final id = r['id'];
          final idStr = id is int ? id.toString() : id.toString();
          final publicId = r['publicId'] as String?;
          final title = r['title'] as String? ?? 'Untitled';
          final createdAt =
              DateTime.tryParse(r['createdAt'] as String? ?? '') ??
              DateTime.now();

          reportInfos.add(
            ReportInfo(
              folderName: idStr,
              name: title,
              dateTime: createdAt,
              thumbnailPath: null,
              publicId: publicId,
            ),
          );
        }
      }

      // 2. Загружаем расшаренные отчёты (по сохранённым share-токенам)
      final shareTokens = await ShareTokenStorage.getTokens();
      for (final token in shareTokens) {
        try {
          final anonymousId = await AnonymousIdService.getId();
          final shareResult = await ApiService.getShareInfo(
            token: token,
            anonymousId: anonymousId,
          );
          if (shareResult.success && shareResult.data != null) {
            final report = shareResult.data!['report'] ?? {};
            final reportData = report['reportData'] ?? {};
            final id = report['id'];
            final idStr = id is int ? id.toString() : id.toString();
            final publicId = report['publicId'] as String?;
            final title =
                (reportData['reportName'] ?? report['title'] ?? 'Отчёт')
                    .toString();
            final createdAt =
                DateTime.tryParse(report['createdAt'] as String? ?? '') ??
                DateTime.now();

            // Не дублируем, если отчёт уже есть в списке
            if (!reportInfos.any((r) => r.folderName == idStr)) {
              reportInfos.add(
                ReportInfo(
                  folderName: idStr,
                  name: title,
                  dateTime: createdAt,
                  thumbnailPath: null,
                  publicId: publicId,
                ),
              );
            }
          } else if (shareResult.statusCode == 404 ||
              shareResult.statusCode == 410) {
            // Токен протух/отозван/несуществует — удаляем его из хранилища,
            // чтобы чужие/устаревшие отчёты не подтягивались в список.
            // При сетевой ошибке (statusCode == null) токен сохраняем.
            await ShareTokenStorage.removeToken(token);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('loadReportList: share token $token error: $e');
          }
        }
      }

      // Сортируем по дате (новые первыми)
      reportInfos.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return reportInfos;
    } catch (e) {
      if (kDebugMode) debugPrint('loadReportList (web) error: $e');
      return [];
    }
  }

  /// Удалить локальную копию отчёта с устройства.
  ///
  /// Принимает абсолютный путь к папке [localFolderPath] (а не имя отчёта).
  /// Возвращает честный статус: `false`, если папки не существует или удаление
  /// не удалось. Это устраняет баг «пишет удалено, но запись остаётся», когда
  /// в метод передавался `report.id` (серверный id / относительное имя), папка
  /// не находилась и метод безусловно возвращал `true`.
  Future<bool> deleteReportLocal(String localFolderPath) async {
    try {
      if (kIsWeb) return false;
      // ===== Mobile/Desktop: удаляем локальную папку =====
      final folder = Directory(localFolderPath);
      if (!await folder.exists()) return false;
      await folder.delete(recursive: true);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error deleting local report: $e');
      return false;
    }
  }

  /// Удалить отчёт на сервере по его серверному [reportId].
  /// Локальная копия (если есть) при этом НЕ трогается — её удаляет отдельный
  /// вызов [deleteReportLocal].
  ///
  /// Возвращает: 0 — успех; 403 — не является автором (нельзя удалить чужой);
  /// -1 — ошибка запроса/сеть. Позволяет UI показать понятное сообщение
  /// (например, «не автор») вместо общего «ошибка удаления».
  Future<int> deleteReportOnServer(String reportIdStr) async {
    try {
      final rId = int.tryParse(reportIdStr);
      if (rId == null) return -1;
      final result = await ApiService.deleteReport(rId);
      if (result.success) return 0;
      if (result.statusCode == 403) return 403;
      return -1;
    } catch (e) {
      if (kDebugMode) debugPrint('Error deleting server report: $e');
      return -1;
    }
  }

  /// Сгенерировать Excel-файл как массив байтов.
  /// Используется при загрузке отчёта на сервер.
  /// Deferred: excel-сервис подгружается при первом вызове.
  Future<Uint8List> generateExcelBytes() async {
    if (_currentReport == null) return Uint8List(0);
    await excel_service.loadLibrary();
    return excel_service.generateExcelBytes(_currentReport!);
  }

  /// Сгенерировать упрощённую HTML-таблицу отчёта для вставки в Excel
  /// через буфер обмена. Работает офлайн, без сервера.
  Future<String> generateExcelHtmlContent() async {
    if (_currentReport == null) return '<html><body>Нет отчёта</body></html>';
    await excel_service.loadLibrary();
    return excel_service.generateExcelHtmlContent(_currentReport!);
  }

  Future<String?> exportZip({
    String? customSavePath,
    String? customFileName,
  }) async {
    if (_currentReport == null || _currentReportPath == null) return null;
    try {
      await saveReport();

      // Сохраняем Excel
      final excelBytes = await generateExcelBytes();
      final excelFile = File('$_currentReportPath/report.xlsx');
      await excelFile.writeAsBytes(excelBytes);
      if (kDebugMode) {
        debugPrint(
          'Excel saved to: ${excelFile.path}, bytes: ${excelBytes.length}',
        );
      }

      // Сохраняем HTML-версию отчёта (офлайн-генерация, медиа по
      // относительным путям — отчёт открывается из распакованного архива).
      await html_service.loadLibrary();
      final htmlContent = html_service.generateReportHtml(_currentReport!);
      final htmlFile = File('$_currentReportPath/report.html');
      await htmlFile.writeAsString(htmlContent);
      if (kDebugMode) {
        debugPrint('HTML saved to: ${htmlFile.path}');
      }

      final folderPath = _currentReportPath!;
      final safeName = _currentReport!.reportName
          .replaceAll(
            RegExp(r'[^\w\sа-яА-ЯёЁ\u4e00-\u9fff-]'),
            '',
          ) // Allow Russian, Chinese, and alphanumeric
          .replaceAll(' ', '_');

      String zipPath;
      if (customSavePath != null && customSavePath.isNotEmpty) {
        if (customFileName != null && customFileName.isNotEmpty) {
          zipPath = '$customSavePath/$customFileName';
        } else {
          zipPath = '$customSavePath/$safeName.zip';
        }
      } else {
        final reportsDir = await _getReportsDir();
        zipPath = '$reportsDir/$safeName.zip';
      }

      final Set<String> neededFiles = {};

      neededFiles.add('report.json');
      neededFiles.add('report.html');
      neededFiles.add('report.xlsx');

      if (_currentReport != null) {
        if (_currentReport!.headerImagePath != null) {
          neededFiles.add(_currentReport!.headerImagePath!);
        }
        for (final markerEntry in _currentReport!.markers.entries) {
          for (final answerMarker in markerEntry.value) {
            for (final media in answerMarker.media) {
              if (media.localPath != null) {
                neededFiles.add(media.localPath!);
              }
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('Files to add to zip: $neededFiles');
      }

      // Deferred: пакет archive подгружается при первом экспорте.
      // Валидация путей (P2-39) выполняется внутри сервиса.
      await zip_service.loadLibrary();
      await zip_service.createProjectZip(zipPath, folderPath, neededFiles);

      return zipPath;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error exporting zip: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return null;
    }
  }

  Future<void> shareZip(String zipPath) async {
    if (kIsWeb) return;
    try {
      await share_plus.loadLibrary();
      await share_plus.Share.shareXFiles([
        share_plus.XFile(zipPath),
      ], text: 'EasyTab Report');
    } catch (e) {
      if (kDebugMode) debugPrint('Error sharing zip: $e');
    }
  }

  Future<List<int>> getUnsyncQuestionIndices() async {
    if (_currentReport == null) return [];
    await sync_service.loadLibrary();
    return sync_service.getUnsyncQuestionIndices(_currentReport!);
  }

  Future<String> generateSyncJson() async {
    if (_currentReport == null) return '{}';
    await sync_service.loadLibrary();
    return sync_service.generateSyncJson(_currentReport!);
  }

  Future<Map<String, dynamic>?> validateSyncJson(String jsonStr) async {
    await sync_service.loadLibrary();
    return sync_service.validateSyncJson(jsonStr);
  }

  Future<void> clearAnswersInLanguage(String langCode) async {
    if (_currentReport == null) return;
    await sync_service.loadLibrary();
    sync_service.clearAnswersInLanguage(_currentReport!, langCode);
    notifyListeners();
  }

  Future<void> applySyncAnswers(String jsonStr) async {
    if (_currentReport == null) return;
    await sync_service.loadLibrary();
    if (sync_service.applySyncAnswers(_currentReport!, jsonStr)) {
      notifyListeners();
      // Автосохранение после успешной синхронизации переводов:
      // гарантирует, что пользователь не потеряет загруженные переводы.
      await saveReport();
    }
  }

  @override
  void dispose() {
    _videoProgressSub?.cancel();
    _pendingDeletion.clear();
    _videoQueue?.dispose();
    super.dispose();
  }
}
