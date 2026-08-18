import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';
import '../models/report_models.dart';

/// Результат валидации шаблона
class TemplateValidationResult {
  final bool isValid;
  final String? error;
  final Report? report;

  const TemplateValidationResult({
    required this.isValid,
    this.error,
    this.report,
  });

  const TemplateValidationResult.success(Report report)
      : this(isValid: true, report: report);

  const TemplateValidationResult.failure(String error)
      : this(isValid: false, error: error);
}

/// Сервис для парсинга шаблонов разных форматов:
/// - Excel (.xlsx)
/// - JSON-файл (.json)
/// - ZIP-архив с JSON внутри (.zip)
/// - Сохранённый отчёт (JSON из reports/)
class TemplateParserService {
  /// Парсит шаблон из файла любого поддерживаемого формата.
  /// Автоматически определяет формат по расширению.
  static Future<TemplateValidationResult> parseFromFile(
    String filePath, {
    AppLocalizations? loc,
  }) async {
    final ext = filePath.toLowerCase().split('.').last;

    switch (ext) {
      case 'xlsx':
        return parseExcel(filePath, loc: loc);
      case 'json':
        return parseJsonFile(filePath, loc: loc);
      case 'zip':
        return parseZip(filePath, loc: loc);
      default:
        return TemplateValidationResult.failure(
          loc?.unsupportedFormat(ext) ?? 'Unsupported file format: .$ext',
        );
    }
  }

  /// Парсит шаблон из Excel файла (.xlsx).
  /// Формат: первая строка — заголовки, вторая — коды языков,
  /// остальные — вопросы (название, пример, описание для каждого языка).
  static Future<TemplateValidationResult> parseExcel(
    String filePath, {
    AppLocalizations? loc,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.sheets.values.first;

      final rows = sheet.rows;
      if (rows.length < 3) {
        return TemplateValidationResult.failure(
          loc?.excelMinRows ?? 'Excel file must contain at least 3 rows',
        );
      }

      // Парсим строку с кодами языков
      final langRow = rows[1];
      final languages = <String>[];
      final langColumns = <String, int>{};

      for (int col = 0; col < langRow.length; col++) {
        final cell = langRow[col];
        if (cell != null && cell.value != null) {
          final lang = cell.value.toString().trim().toUpperCase();
          if (lang.isNotEmpty && !languages.contains(lang)) {
            languages.add(lang);
            langColumns[lang] = col;
          }
        }
      }

      if (languages.isEmpty) {
        languages.add('RU');
      }

      // Парсим вопросы
      final questions = <Question>[];
      for (int rowIdx = 2; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        final question = Question(
          id: DateTime.now().millisecondsSinceEpoch + rowIdx,
          localizations: {},
        );

        bool hasData = false;

        for (final lang in languages) {
          final startCol = langColumns[lang];
          if (startCol == null) continue;

          final name = (startCol < row.length && row[startCol]?.value != null)
              ? row[startCol]!.value.toString().trim()
              : '';
          final example =
              (startCol + 1 < row.length && row[startCol + 1]?.value != null)
                  ? row[startCol + 1]!.value.toString().trim()
                  : '';
          final desc =
              (startCol + 2 < row.length && row[startCol + 2]?.value != null)
                  ? row[startCol + 2]!.value.toString().trim()
                  : '';

          question.localizations[lang] = QuestionLocalization(
            name: name.isEmpty ? null : name,
            description: desc.isEmpty ? null : desc,
            example: example.isEmpty ? null : example,
          );

          if (name.isNotEmpty || desc.isNotEmpty) {
            hasData = true;
          }
        }

        if (hasData) {
          questions.add(question);
        }
      }

      if (questions.isEmpty) {
        return TemplateValidationResult.failure(
          loc?.excelNoQuestions ??
              'No questions found in Excel file',
        );
      }

      final report = Report(
        reportName: loc?.newReport ?? 'New Report',
        availableLanguages: languages,
        currentLanguage: languages[0],
        questions: questions,
        translations: {},
        markers: {},
        mediaCounter: {'photos': 1, 'X': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      _initializeReportMetadata(report, questions, languages);

      return TemplateValidationResult.success(report);
    } catch (e) {
      debugPrint('Error parsing Excel template: $e');
      return TemplateValidationResult.failure(
        loc?.excelReadError(e.toString()) ?? 'Error reading Excel file: $e',
      );
    }
  }

  /// Парсит шаблон из JSON-файла.
  /// Поддерживает два формата:
  /// 1. Полный отчёт (с translations, markers) — извлекает только questions
  /// 2. Простой шаблон вопросов (только questions + availableLanguages)
  static Future<TemplateValidationResult> parseJsonFile(
    String filePath, {
    AppLocalizations? loc,
  }) async {
    try {
      final content = await File(filePath).readAsString();
      return parseJsonString(content);
    } catch (e) {
      debugPrint('Error reading JSON file: $e');
      return TemplateValidationResult.failure(
        loc?.jsonReadError(e.toString()) ?? 'Error reading JSON file: $e',
      );
    }
  }

  /// Парсит шаблон из JSON-строки.
  static TemplateValidationResult parseJsonString(
    String jsonText, {
    AppLocalizations? loc,
  }) {
    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      return parseJsonData(data, loc: loc);
    } on FormatException catch (e) {
      return TemplateValidationResult.failure(
        loc?.invalidJsonDetail(e.message) ?? 'Invalid JSON: ${e.message}',
      );
    } catch (e) {
      return TemplateValidationResult.failure(
        loc?.jsonParseDetail(e.toString()) ?? 'JSON parsing error: $e',
      );
    }
  }

  /// Парсит шаблон из распарсенного JSON (Map).
  /// Поддерживает форматы:
  /// - Полный отчёт (с translations, markers, mediaCounter)
  /// - Простой шаблон (только questions + availableLanguages)
  static TemplateValidationResult parseJsonData(
    Map<String, dynamic> data, {
    AppLocalizations? loc,
  }) {
    try {
      // Проверяем наличие вопросов
      final questionsJson = data['questions'] as List<dynamic>?;
      if (questionsJson == null || questionsJson.isEmpty) {
        return TemplateValidationResult.failure(
          loc?.jsonNoQuestions ?? 'JSON contains no questions',
        );
      }

      // Определяем доступные языки
      List<String> availableLanguages;
      final langsJson = data['availableLanguages'] as List<dynamic>?;
      if (langsJson != null && langsJson.isNotEmpty) {
        availableLanguages = langsJson.cast<String>();
      } else {
        // Пробуем извлечь языки из локализаций вопросов
        final langsSet = <String>{};
        for (final qJson in questionsJson) {
          if (qJson is Map<String, dynamic>) {
            final localizations =
                qJson['localizations'] as Map<String, dynamic>?;
            if (localizations != null) {
              langsSet.addAll(localizations.keys);
            }
          }
        }
        availableLanguages = langsSet.toList();
        if (availableLanguages.isEmpty) {
          availableLanguages = ['RU'];
        }
      }

      // Парсим вопросы
      final questions = <Question>[];
      for (int i = 0; i < questionsJson.length; i++) {
        final qJson = questionsJson[i] as Map<String, dynamic>?;
        if (qJson == null) continue;

        final id = qJson['id'] as int? ?? i + 1;
        final localizationsJson =
            qJson['localizations'] as Map<String, dynamic>? ?? {};

        final localizations = <String, QuestionLocalization>{};
        localizationsJson.forEach((lang, locJson) {
          if (locJson is Map<String, dynamic>) {
            localizations[lang] = QuestionLocalization(
              name: locJson['name'] as String?,
              description: locJson['description'] as String?,
              example: locJson['example'] as String?,
            );
          }
        });

        // Пропускаем вопросы без локализаций
        if (localizations.isNotEmpty) {
          questions.add(Question(id: id, localizations: localizations));
        }
      }

      if (questions.isEmpty) {
        return TemplateValidationResult.failure(
          loc?.jsonNoValidQuestions ?? 'No valid questions found in JSON',
        );
      }

      final report = Report(
        reportName: data['reportName'] as String? ?? loc?.newReport ?? 'New Report',
        availableLanguages: availableLanguages,
        currentLanguage: availableLanguages[0],
        questions: questions,
        translations: {},
        markers: {},
        mediaCounter: {'photos': 1, 'X': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        productType: data['productType'] as String? ?? '',
        factory: data['factory'] as String? ?? '',
        model: data['model'] as String? ?? '',
      );

      _initializeReportMetadata(report, questions, availableLanguages);

      return TemplateValidationResult.success(report);
    } catch (e) {
      debugPrint('Error parsing JSON template: $e');
      return TemplateValidationResult.failure(
        loc?.jsonStructureError(e.toString()) ?? 'JSON structure error: $e',
      );
    }
  }

  /// Парсит шаблон из ZIP-архива.
  /// Ищет JSON-файл с отчётом внутри архива (report.json или любой .json).
  static Future<TemplateValidationResult> parseZip(
    String filePath, {
    AppLocalizations? loc,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Ищем JSON-файл с отчётом
      ArchiveFile? jsonFile;
      for (final file in archive.files) {
        if (file.isFile && file.name.toLowerCase().endsWith('.json')) {
          // Предпочитаем report.json, но берём любой JSON
          if (file.name.toLowerCase() == 'report.json') {
            jsonFile = file;
            break;
          }
          jsonFile ??= file;
        }
      }

      if (jsonFile == null) {
        return TemplateValidationResult.failure(
          loc?.zipNoJson ?? 'No JSON file found in ZIP archive',
        );
      }

      final content = utf8.decode(jsonFile.content as List<int>);
      return parseJsonString(content, loc: loc);
    } catch (e) {
      debugPrint('Error parsing ZIP template: $e');
      return TemplateValidationResult.failure(
        loc?.zipReadError(e.toString()) ?? 'Error reading ZIP archive: $e',
      );
    }
  }

  /// Генерирует пример JSON-шаблона для скачивания.
  static String generateSampleJson() {
    final sample = {
      'reportName': 'Пример отчёта',
      'availableLanguages': ['RU', 'EN', 'ZH'],
      'currentLanguage': 'RU',
      'productType': 'Аэрогриль',
      'factory': 'Пример фабрики',
      'model': 'Модель X1',
      'questions': [
        {
          'id': 1,
          'localizations': {
            'RU': {
              'name': 'Название объекта',
              'description': 'Введите полное название объекта',
              'example': 'ООО "ПромСтрой"',
            },
            'EN': {
              'name': 'Object name',
              'description': 'Enter full object name',
              'example': 'ABC Construction LLC',
            },
            'ZH': {
              'name': '对象名称',
              'description': '输入对象的全名',
              'example': 'ABC建筑有限公司',
            },
          },
        },
        {
          'id': 2,
          'localizations': {
            'RU': {
              'name': 'Дата осмотра',
              'description': 'Введите дату и время осмотра',
              'example': '01.01.2025 14:00',
            },
            'EN': {
              'name': 'Inspection date',
              'description': 'Enter inspection date and time',
              'example': '01/01/2025 14:00',
            },
          },
        },
        {
          'id': 3,
          'localizations': {
            'RU': {
              'name': 'Статус оборудования',
              'description': 'Опишите состояние оборудования',
              'example': 'Исправно / Требует ремонта / Неисправно',
            },
          },
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(sample);
  }

  /// Инициализирует translations и markers для нового отчёта.
  static void _initializeReportMetadata(
    Report report,
    List<Question> questions,
    List<String> languages,
  ) {
    for (int i = 0; i < questions.length; i++) {
      report.translations[i.toString()] = {};
      report.markers[i.toString()] = [AnswerMarkers()];
      for (final lang in languages) {
        report.translations[i.toString()]![lang] = [TranslationAnswer()];
      }
    }
  }
}
