import 'dart:async';
import 'dart:convert';

import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// share_plus (~50-80 KB) нужен только при экспорте ZIP — deferred.
import 'package:share_plus/share_plus.dart' deferred as share_plus;
import '../models/report_models.dart';
import '../services/api_service.dart';
// Тяжёлые сервисы (Excel/Sync/HTML/ZIP, видео-очередь, сжатие видео,
// генерация превью) загружаются лениво (deferred) — они нужны только
// на экране заполнения отчёта (form_fill), а не на старте.
// Каждый станет отдельным чанком, подгружаемым при первом использовании.
import '../services/report_excel_service.dart'
    deferred as excel_service;
import '../services/report_html_service.dart'
    deferred as html_service;
import '../services/report_sync_service.dart'
    deferred as sync_service;
import '../services/project_zip_service.dart'
    deferred as zip_service;
import '../services/native_video_compress_service.dart'
    deferred as native_compress;
import '../services/share_token_storage.dart';
import '../services/api_result.dart';
import '../services/anonymous_id_service.dart';
import '../services/mime_utils.dart';
import '../services/upload_helper.dart';
// Пакет image (~0.5 MB) нужен только при добавлении фото — deferred.
import '../utils/image_compressor.dart' deferred as image_compressor;
import '../services/video_upload_queue.dart'
    deferred as video_upload_queue;
import '../utils/video_thumbnail_generator.dart'
    deferred as thumbnail_gen;

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

class ReportState extends ChangeNotifier {
  Report? _currentReport;
  String? _currentReportPath;

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

    final id = 'att_${DateTime.now().millisecondsSinceEpoch}_'
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

    final id = 'att_${DateTime.now().millisecondsSinceEpoch}_'
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
      _currentReport!.translations[i.toString()] = {};
      _currentReport!.markers[i.toString()] = [AnswerMarkers()];
      for (final lang in languages) {
        _currentReport!.translations[i.toString()]![lang] = [
          TranslationAnswer(),
        ];
      }
    }
    _currentReportPath = null;
    // Сбрасываем ID отчёта на сервере — это новый отчёт
    _serverReportId = null;
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

  void updateAnswerText(int questionIndex, int answerIndex, String text) {
    if (_currentReport == null) return;
    final qid = questionIndex.toString();
    final lang = _currentReport!.currentLanguage;

    if (_currentReport!.translations.containsKey(qid) &&
        _currentReport!.translations[qid]!.containsKey(lang) &&
        answerIndex < _currentReport!.translations[qid]![lang]!.length) {
      _currentReport!.translations[qid]![lang]![answerIndex].text = text;
      _currentReport!.translations[qid]![lang]![answerIndex].isEmpty =
          text.isEmpty;

      for (final otherLang in _currentReport!.availableLanguages) {
        if (otherLang != lang &&
            _currentReport!.translations[qid]!.containsKey(otherLang) &&
            answerIndex <
                _currentReport!.translations[qid]![otherLang]!.length) {
          _currentReport!.translations[qid]![otherLang]![answerIndex].text = '';
          _currentReport!.translations[qid]![otherLang]![answerIndex].isEmpty =
              true;
        }
      }
    }
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
    final counter = _currentReport!.mediaCounter[counterKey]!;
    final ext = file.path.split('.').last;
    final mimeType = mimeTypeFromFilename(file.path);
    final typePrefix = mimeType.startsWith('video/') ? 'v' : 'f';
    final fileName =
        '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${counter.toString().padLeft(3, '0')}.$ext';

    final folderName = isAttention ? 'X' : 'photos';
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

    _currentReport!.mediaCounter[counterKey] = counter + 1;

    notifyListeners();
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
    final counter = _currentReport!.mediaCounter[counterKey]!;

    // Генерируем имя файла: f/v + вопрос + ответ + номер
    // f = photo, v = video
    final typePrefix = mimeType.startsWith('video/') ? 'v' : 'f';
    final ext = fileName.split('.').last;
    final generatedName =
        '$typePrefix${questionIndex + 1}_${answerIndex + 1}_${counter.toString().padLeft(3, '0')}.$ext';

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
    _currentReport!.mediaCounter[counterKey] = counter + 1;

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
      _uploadMediaToServer(
        mediaItem,
        finalBytes,
        generatedName,
        relativePath,
        mimeType,
        onUploadProgress,
      ).catchError((e) {
        if (kDebugMode) debugPrint('Background upload failed: $e');
      });
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

      // Web: прямая загрузка в KS3 через presigned URL (быстрее в 2 раза).
      // Native: серверная загрузка через multipart (fallback).
      ApiResult result;
      if (kIsWeb) {
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
  /// Вызывается после saveReport(), когда _serverReportId и _ks3Folder
  /// уже установлены. Проходит по всем медиа отчёта и загружает те,
  /// у которых serverFileId == null и есть webBytes.
  Future<void> _uploadPendingMedia() async {
    if (_currentReport == null ||
        _ks3Folder == null ||
        _serverReportId == null) {
      return;
    }

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

          // Пропускаем медиа без байтов (не web).
          if (media.webBytes == null) continue;

          // Загружаем на сервер
          if (kDebugMode) {
            debugPrint('_uploadPendingMedia: uploading ${media.name}...');
          }

          await _uploadMediaToServer(
            media,
            media.webBytes!,
            media.name,
            media.localPath ?? media.name,
            media.type,
            null,
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

  Future<String> _generateFolderName() async {
    final now = DateTime.now();
    final baseName = 'report_${now.millisecondsSinceEpoch}';
    final reportsDir = await _getReportsDir();
    return '$reportsDir/$baseName';
  }

  Future<bool> saveReport() async {
    if (_currentReport == null) return false;
    try {
      // ===== Web: сохраняем на сервер =====
      // На web нет локальной файловой системы (path_provider не работает),
      // поэтому отчёт сохраняется напрямую на сервер через API.
      if (kIsWeb) {
        return await _saveReportToServer();
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

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving report: $e');
      return false;
    }
  }

  /// Сохранить отчёт на сервер (создать/обновить запись в БД).
  ///
  /// Возвращает true при успехе. Заполняет [serverReportId], [ks3Folder],
  /// [serverPublicId]. Используется кнопкой «Залить на сервер» на нативных
  /// платформах, а также вызывается из [saveReport] на web.
  Future<bool> saveReportToServer() async {
    if (_currentReport == null) return false;
    return await _saveReportToServer();
  }

  /// ID отчёта на сервере (используется на web для обновления существующего отчёта).
  int? _serverReportId;

  /// Публичный идентификатор отчёта для URL просмотра.
  String? _serverPublicId;

  /// Папка отчёта в KS3 (например, "reports/abc-123/").
  /// Заполняется после первого сохранения отчёта на сервер.
  /// Используется для загрузки медиафайлов в правильную папку.
  String? _ks3Folder;

  /// Токен share-ссылки. Если задан — отчёт работает в режиме
  /// публичной ссылки, без авторизации.
  String? _shareToken;

  /// Геттеры для внешнего доступа
  int? get serverReportId => _serverReportId;
  String? get serverPublicId => _serverPublicId;
  String? get ks3Folder => _ks3Folder;
  String? get shareToken => _shareToken;

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
        );
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
        if (kDebugMode) {
          debugPrint(
            'saveReport (web): saved as ID $_serverReportId, pid=$_serverPublicId, folder=$_ks3Folder',
          );
        }

        // После сохранения отчёта — запускаем загрузку всех медиа,
        // у которых ещё нет serverFileId, в фоне (не блокируем UI).
        if (_ks3Folder != null && _serverReportId != null) {
          // Загружаем фото шапки, если оно было добавлено через addHeaderImageFromBytes
          if (_headerImageBytes != null && _headerImageFileName != null) {
            _uploadHeaderImageToServer().catchError((e) {
              if (kDebugMode) debugPrint('Header image upload error: $e');
            });
          }
          _uploadPendingMedia().catchError((e) {
            if (kDebugMode) debugPrint('Pending media upload error: $e');
          });
        }

        return true;
      } else {
        if (kDebugMode) debugPrint('saveReport (web): ${result.error}');
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('saveReport (web) error: $e');
      return false;
    }
  }

  /// Сохранить отчёт через share-ссылку.
  Future<ApiResult> _saveSharedReportToServer(
    String title,
    Map<String, dynamic> jsonData,
  ) async {
    final anonymousId = await AnonymousIdService.getId();
    return ApiService.saveSharedReport(
      token: _shareToken!,
      reportData: jsonData,
      anonymousId: anonymousId,
    );
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
      final folder = Directory(folderName);
      if (!await folder.exists()) return false;
      final jsonFile = File('${folder.path}/$reportFilename');
      if (!await jsonFile.exists()) return false;
      final jsonString = await jsonFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      _currentReport = Report.fromJson(jsonData, folderPath: folderName);
      _currentReportPath = folderName;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading report: $e');
      return false;
    }
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
      _currentReport = Report.fromJson(
        reportData,
        folderPath: reportId.toString(),
      );
      _currentReportPath = reportId.toString();
      _serverReportId = reportId; // запоминаем для будущих сохранений

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
      _currentReport = Report.fromJson(reportData, folderPath: token);
      _currentReportPath = token;
      _serverReportId = result.data!['report']['id'] is int
          ? result.data!['report']['id']
          : int.tryParse(result.data!['report']['id'].toString());
      _serverPublicId = result.data!['report']['publicId']?.toString();
      _ks3Folder = result.data!['report']['ks3Folder']?.toString();

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
          final uri = Uri.http(
            ApiService.baseUrl,
            '/view/report/$publicId/files/${media.localPath}',
            {'share_token': _shareToken},
          );
          media.webUrl = uri.toString();
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

  Future<bool> deleteReport(String folderName) async {
    try {
      // ===== Web: удаляем на сервере =====
      if (kIsWeb) {
        final reportId = int.tryParse(folderName);
        if (reportId == null) return false;
        final result = await ApiService.deleteReport(reportId);
        return result.success;
      }

      // ===== Mobile/Desktop: удаляем локально =====
      final folder = Directory(folderName);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error deleting report: $e');
      return false;
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
      await share_plus.Share.shareXFiles(
        [share_plus.XFile(zipPath)],
        text: 'EasyTab Report',
      );
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
