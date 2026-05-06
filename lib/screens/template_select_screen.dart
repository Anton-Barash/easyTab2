import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/report_provider.dart';
import '../models/report_models.dart';

class TemplateSelectScreen extends StatefulWidget {
  const TemplateSelectScreen({super.key});

  @override
  State<TemplateSelectScreen> createState() => _TemplateSelectScreenState();
}

class _TemplateSelectScreenState extends State<TemplateSelectScreen> {
  final _reportNameController = TextEditingController();
  Report? _selectedReport;

  final List<Question> _defaultTemplate = [
    Question(
      id: 1,
      localizations: {
        'RU': QuestionLocalization(
          name: 'Название объекта',
          description: 'Введите полное название объекта',
          example: 'ООО "ПромСтрой"',
        ),
        'EN': QuestionLocalization(
          name: 'Object name',
          description: 'Enter full object name',
          example: 'ABC Construction LLC',
        ),
      },
    ),
    Question(
      id: 2,
      localizations: {
        'RU': QuestionLocalization(
          name: 'Дата осмотра',
          description: 'Введите дату и время осмотра',
          example: '01.01.2025 14:00',
        ),
        'EN': QuestionLocalization(
          name: 'Inspection date',
          description: 'Enter inspection date and time',
          example: '01/01/2025 14:00',
        ),
      },
    ),
    Question(
      id: 3,
      localizations: {
        'RU': QuestionLocalization(
          name: 'Статус оборудования',
          description: 'Опишите состояние оборудования',
          example: 'Исправно / Требует ремонта / Неисправно',
        ),
        'EN': QuestionLocalization(
          name: 'Equipment status',
          description: 'Describe equipment condition',
          example: 'Operational / Needs repair / Faulty',
        ),
      },
    ),
    Question(
      id: 4,
      localizations: {
        'RU': QuestionLocalization(
          name: 'Комментарии',
          description: 'Любые дополнительные сведения',
          example: 'Замечаний нет',
        ),
        'EN': QuestionLocalization(
          name: 'Comments',
          description: 'Any additional information',
          example: 'No remarks',
        ),
      },
    ),
  ];

  @override
  void dispose() {
    _reportNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать отчёт'),
        backgroundColor: const Color(0xFFe0e0e0),
        foregroundColor: const Color(0xFF424242),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFf8f7f2),
              child: CustomPaint(painter: DottedPatternPainter()),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Название отчёта',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF424242),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reportNameController,
                        decoration: InputDecoration(
                          hintText: 'Введите название...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                              width: 2.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(color: Color(0xFF424242)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Выберите шаблон',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF424242),
                  ),
                ),
                const SizedBox(height: 15),
                _buildTemplateItem(
                  '📊',
                  'Встроенный шаблон',
                  '4 вопроса, RU+EN',
                  isBuiltIn: true,
                  onTap: _loadBuiltInTemplate,
                ),
                const SizedBox(height: 15),
                _buildUploadTemplate(),
                const SizedBox(height: 20),
                if (_selectedReport != null)
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Предпросмотр',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF424242),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.language, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedReport!.currentLanguage,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF333333),
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: [
                                  ..._selectedReport!.availableLanguages.map(
                                    (lang) => DropdownMenuItem(
                                      value: lang,
                                      child: Text(
                                        lang,
                                        style: const TextStyle(
                                          color: Color(0xFF424242),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: '_add_translation',
                                    child: Text(
                                      '➕ Добавить перевод',
                                      style: TextStyle(
                                        color: Color(0xFF2563eb),
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == '_add_translation') {
                                    _showAddTranslationDialog();
                                  } else if (value != null) {
                                    setState(() {
                                      _selectedReport = _selectedReport!
                                          .copyWith(currentLanguage: value);
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._selectedReport!.questions.asMap().entries.map((
                          entry,
                        ) {
                          final lang = _selectedReport!.currentLanguage;
                          final loc = entry.value.getLocalization(lang);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${entry.key + 1}. ${loc?.name ?? entry.value.getDisplayName(lang) ?? 'Без названия'}',
                              style: const TextStyle(color: Color(0xFF424242)),
                            ),
                          );
                        }),
                        const SizedBox(height: 18),
                        _buildButton(
                          label: 'Использовать шаблон',
                          onTap: _reportNameController.text.trim().isEmpty
                              ? null
                              : () => _useTemplate(context),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _loadBuiltInTemplate() {
    setState(() {
      _selectedReport = Report(
        reportName: '',
        availableLanguages: ['RU', 'EN'],
        currentLanguage: 'RU',
        questions: _defaultTemplate,
        translations: {},
        markers: {},
        mediaCounter: {'photos': 1, 'X': 1},
      );
    });
  }

  Widget _buildButton({required String label, required VoidCallback? onTap}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: onTap == null
            ? const Color(0xFFcccccc)
            : const Color(0xFFe0e0e0),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(11),
        ),
        border: Border.all(width: 2.5, color: const Color(0xFF333333)),
        boxShadow: [
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
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: onTap == null
                    ? const Color(0xFF999)
                    : const Color(0xFF424242),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: const Color(0xFF333333)),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildTemplateItem(
    String icon,
    String title,
    String subtitle, {
    bool isBuiltIn = false,
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedReport != null && isBuiltIn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          width: isSelected ? 2.5 : 2,
          color: isSelected ? const Color(0xFF2563eb) : const Color(0xFF333333),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF424242),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Color(0xFF64748b)),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563eb),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        width: 1.5,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    child: const Text(
                      'Выбран',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadTemplate() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: const Color(0xFF333333)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📁', style: TextStyle(fontSize: 40)),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    'Загрузить свой шаблон (.xlsx)',
                    style: TextStyle(color: Color(0xFF64748b)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final state = context.read<ReportState>();
    final report = await state.parseTemplate(path);

    if (report == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при загрузке шаблона')),
      );
      return;
    }

    setState(() {
      _selectedReport = report;
    });
  }

  Future<void> _useTemplate(BuildContext context) async {
    final state = context.read<ReportState>();
    final name = _reportNameController.text.trim();
    if (name.isEmpty || _selectedReport == null) return;

    state.newReport(
      name,
      _selectedReport!.questions,
      _selectedReport!.availableLanguages,
    );
    await state.saveReport();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/fill');
    }
  }

  void _showAddTranslationDialog() {
    if (_selectedReport == null) return;

    showDialog(
      context: context,
      builder: (context) => _AddTranslationDialog(
        report: _selectedReport!,
        onTranslationAdded: (newLang, translations) {
          setState(() {
            // Обновляем каждый вопрос новой локализацией
            final updatedQuestions = _selectedReport!.questions.map((question) {
              final translation = translations[question.id];
              if (translation != null) {
                final newLocalizations = Map<String, QuestionLocalization>.from(
                  question.localizations,
                );
                newLocalizations[newLang] = translation;
                return question.copyWith(localizations: newLocalizations);
              }
              return question;
            }).toList();

            // Обновляем список доступных языков
            final newAvailableLanguages = List<String>.from(
              _selectedReport!.availableLanguages,
            );
            if (!newAvailableLanguages.contains(newLang)) {
              newAvailableLanguages.add(newLang);
            }

            _selectedReport = _selectedReport!.copyWith(
              questions: updatedQuestions,
              availableLanguages: newAvailableLanguages,
              currentLanguage: newLang,
            );
          });
        },
      ),
    );
  }
}

class _AddTranslationDialog extends StatefulWidget {
  final Report report;
  final Function(String newLang, Map<int, QuestionLocalization> translations)
  onTranslationAdded;

  const _AddTranslationDialog({
    required this.report,
    required this.onTranslationAdded,
  });

  @override
  State<_AddTranslationDialog> createState() => _AddTranslationDialogState();
}

class _AddTranslationDialogState extends State<_AddTranslationDialog> {
  String _selectedSourceLang = 'RU';
  final TextEditingController _jsonController = TextEditingController();

  String _exportTemplate() {
    final data = <String, dynamic>{
      'language_code': '',
      'questions': widget.report.questions.map((q) {
        final loc = q.getLocalization(_selectedSourceLang);
        return {
          'id': q.id,
          'name': loc?.name ?? '',
          'description': loc?.description ?? '',
          'example': loc?.example ?? '',
        };
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> _copyTemplate() async {
    final template = _exportTemplate();
    await Clipboard.setData(ClipboardData(text: template));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шаблон скопирован в буфер обмена')),
      );
    }
  }

  Future<void> _saveTemplateToFile() async {
    try {
      final template = _exportTemplate();
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/template_$_selectedSourceLang.json');
      await file.writeAsString(template);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Шаблон сохранен в ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  Future<void> _loadFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _jsonController.text = content;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка чтения файла: $e')));
      }
    }
  }

  Map<String, dynamic>? _validateAndParse(String jsonText) {
    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;

      // Проверка наличия language_code
      final langCode = data['language_code'];
      if (langCode is! String || langCode.isEmpty) {
        throw Exception('Поле language_code должно быть непустой строкой');
      }

      // Проверка наличия questions
      final questionsJson = data['questions'];
      if (questionsJson is! List) {
        throw Exception('Поле questions должно быть массивом');
      }

      // Проверка количества вопросов
      if (questionsJson.length != widget.report.questions.length) {
        throw Exception(
          'Должно быть ${widget.report.questions.length} вопросов, получено ${questionsJson.length}',
        );
      }

      // Проверка каждого вопроса
      for (int i = 0; i < questionsJson.length; i++) {
        final q = questionsJson[i];
        if (q is! Map) {
          throw Exception('Вопрос $i должен быть объектом');
        }
        if (q['id'] is! int) {
          throw Exception('Вопрос $i: поле id должно быть числом');
        }
        if (q['name'] is! String || q['name'].isEmpty) {
          throw Exception('Вопрос $i: поле name должно быть непустой строкой');
        }
        if (q['description'] is! String || q['description'].isEmpty) {
          throw Exception(
            'Вопрос $i: поле description должно быть непустой строкой',
          );
        }
        // example - не обязательное поле
      }

      return data;
    } catch (e) {
      rethrow;
    }
  }

  void _importTemplate() {
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите переведенный шаблон')),
      );
      return;
    }

    try {
      final data = _validateAndParse(jsonText);
      if (data == null) return;

      final langCode = data['language_code'] as String;
      final questionsJson = data['questions'] as List;

      final translations = <int, QuestionLocalization>{};
      for (final qJson in questionsJson) {
        final q = qJson as Map<String, dynamic>;
        translations[q['id'] as int] = QuestionLocalization(
          name: q['name'] as String,
          description: q['description'] as String,
          example: q['example'] as String?,
        );
      }

      widget.onTranslationAdded(langCode, translations);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Перевод на $langCode успешно добавлен!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка в шаблоне: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить перевод'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Скопируйте шаблон, переведите его на нужный язык с использованием любого ИИ и вставьте результат.',
                style: TextStyle(color: Color(0xFF64748b)),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Выберите исходный язык:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedSourceLang,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF333333),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: widget.report.availableLanguages
                    .map(
                      (lang) => DropdownMenuItem(
                        value: lang,
                        child: Text(
                          lang,
                          style: const TextStyle(color: Color(0xFF424242)),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedSourceLang = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.copy),
                      label: const Text('Копировать шаблон'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveTemplateToFile,
                      icon: const Icon(Icons.download),
                      label: const Text('Сохранить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
              const Text(
                '2. Вставьте переведенный шаблон:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: 'Вставьте JSON сюда...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF333333),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loadFromFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Загрузить из файла'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe0e0e0),
                        foregroundColor: const Color(0xFF424242),
                        side: const BorderSide(
                          color: Color(0xFF333333),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Отмена',
            style: TextStyle(color: Color(0xFF64748b)),
          ),
        ),
        ElevatedButton(
          onPressed: _importTemplate,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563eb),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF333333), width: 2),
          ),
          child: const Text('Добавить перевод'),
        ),
      ],
    );
  }
}

class DottedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFcbc7bc)
      ..style = PaintingStyle.fill;

    const dotSize = 1.0;
    const spacing = 20.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
