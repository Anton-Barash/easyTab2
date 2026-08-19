import 'dart:convert';
import 'package:easy_tab/services/template_parser_service.dart';
import 'package:easy_tab/utils/app_colors.dart';
import 'package:easy_tab/utils/platform_io.dart'
    if (dart.library.html) 'package:easy_tab/utils/platform_io_web.dart';
import 'package:easy_tab/utils/file_image.dart'
    if (dart.library.html) 'package:easy_tab/utils/file_image_web.dart';
import 'package:easy_tab/widgets/dotted_background.dart';
import 'package:easy_tab/widgets/easy_tab_button.dart';
import 'package:easy_tab/widgets/form_fill/picker_item.dart';
import 'package:easy_tab/widgets/form_fill/section_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/report_provider.dart';
import '../models/report_models.dart';
import '../l10n/app_localizations.dart';

class TemplateSelectScreen extends StatefulWidget {
  const TemplateSelectScreen({super.key});

  @override
  State<TemplateSelectScreen> createState() => _TemplateSelectScreenState();
}

class _TemplateSelectScreenState extends State<TemplateSelectScreen> {
  final _reportNameController = TextEditingController();
  final _productTypeController = TextEditingController();
  final _factoryController = TextEditingController();
  final _modelController = TextEditingController();
  Report? _selectedReport;
  String? _headerImagePath;
  bool _isPickingPhoto = false;

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
    _productTypeController.dispose();
    _factoryController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.createReportTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const DottedBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.productType,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _productTypeController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(color: AppColors.textPrimary),
                        onChanged: (_) => _updateReportName(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.factory,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _factoryController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(color: AppColors.textPrimary),
                        onChanged: (_) => _updateReportName(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.model,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 2.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(color: AppColors.textPrimary),
                        onChanged: (_) => _updateReportName(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.photo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isPickingPhoto)
                        Container(
                          width: double.infinity,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.border,
                              width: 2,
                            ),
                            color: AppColors.grey100,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.border,
                            ),
                          ),
                        )
                      else if (_headerImagePath != null) ...[
                        Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 150,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 2,
                                ),
                                image: DecorationImage(
                                  image: fileImageProvider(_headerImagePath!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _headerImagePath = null;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pickHeaderImage,
                          icon: const Icon(Icons.photo_library),
                          label: Text(loc.changePhoto),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ] else ...[
                        InkWell(
                          onTap: _pickHeaderImage,
                          child: Container(
                            width: double.infinity,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.border,
                                width: 2,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.add_a_photo,
                                  size: 40,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  loc.addPhoto,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  loc.selectTemplate,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 15),
                _buildTemplateItem(
                  context,
                  '📊',
                  loc.builtInTemplate,
                  loc.builtInTemplateDesc,
                  isBuiltIn: true,
                  onTap: _loadBuiltInTemplate,
                ),
                const SizedBox(height: 15),
                _buildUploadTemplate(context),
                const SizedBox(height: 20),
                if (_selectedReport != null)
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.preview,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
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
                                      color: AppColors.border,
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
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: '_add_translation',
                                    child: Text(
                                      loc.addTranslationButton,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w500,
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
                          final questionLoc = entry.value.getLocalization(lang);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${entry.key + 1}. ${questionLoc?.name ?? entry.value.getDisplayName(lang) ?? loc.noName}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 18),
                        EasyTabButton(
                          label: loc.useTemplate,
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

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildTemplateItem(
    BuildContext context,
    String icon,
    String title,
    String subtitle, {
    bool isBuiltIn = false,
    VoidCallback? onTap,
  }) {
    final loc = AppLocalizations.of(context)!;
    final isSelected = _selectedReport != null && isBuiltIn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          width: isSelected ? 2.5 : 2,
          color: isSelected ? AppColors.primary : AppColors.border,
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
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.textLight),
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
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(width: 1.5, color: AppColors.border),
                    ),
                    child: Text(
                      loc.selected,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadTemplate(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📁', style: TextStyle(fontSize: 40)),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    loc.uploadYourTemplate,
                    style: const TextStyle(color: AppColors.textLight),
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
    // Показываем диалог выбора типа шаблона
    final action = await _showTemplateSourceDialog();
    if (action == null || !mounted) return;

    switch (action) {
      case 'file':
        await _pickTemplateFile();
        break;
      case 'json_text':
        await _showJsonTextDialog();
        break;
      case 'download_sample':
        await _downloadSampleJson();
        break;
    }
  }

  /// Диалог выбора источника шаблона (в стиле выбора фото/видео)
  Future<String?> _showTemplateSourceDialog() async {
    final loc = AppLocalizations.of(context)!;
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.selectTemplate,
                  style: const TextStyle(
                    color: AppColors.border,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle(title: loc.createSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.upload_file,
                  label: loc.templateSourceFile,
                  onTap: () => Navigator.pop(ctx, 'file'),
                ),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.code,
                  label: loc.templateSourceJson,
                  onTap: () => Navigator.pop(ctx, 'json_text'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: AppColors.grey300,
                    thickness: 1.5,
                    height: 1.5,
                  ),
                ),
                SectionTitle(title: loc.selectSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.download,
                  label: loc.templateDownloadSample,
                  onTap: () => Navigator.pop(ctx, 'download_sample'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Выбор файла шаблона (Excel, JSON, ZIP)
  Future<void> _pickTemplateFile() async {
    final loc = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'json', 'zip'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final parseResult = await TemplateParserService.parseFromFile(path);

    if (!mounted) return;

    if (!parseResult.isValid || parseResult.report == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parseResult.error ?? loc.templateLoadError),
        ),
      );
      return;
    }

    setState(() {
      _selectedReport = parseResult.report!;
    });
  }

  /// Диалог вставки JSON-кода
  Future<void> _showJsonTextDialog() async {
    final jsonController = TextEditingController();
    final loc = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.jsonTemplateTitle,
                  style: const TextStyle(
                    color: AppColors.border,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: jsonController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: loc.jsonTemplateHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        loc.cancel,
                        style: const TextStyle(color: AppColors.textLight),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: Text(loc.loadJsonButton),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true || !mounted) return;

    final jsonText = jsonController.text.trim();
    if (jsonText.isEmpty) return;

    final parseResult = TemplateParserService.parseJsonString(jsonText);

    if (!mounted) return;

    if (!parseResult.isValid || parseResult.report == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parseResult.error ?? loc.jsonParseError),
        ),
      );
      return;
    }

    setState(() {
      _selectedReport = parseResult.report!;
    });
  }

  /// Скачивание примера JSON-шаблона
  Future<void> _downloadSampleJson() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final sample = TemplateParserService.generateSampleJson();
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return;

      final file = File('$directory/template_sample.json');
      await file.writeAsString(sample);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.templateSampleSaved(file.path))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.templateSaveError(e.toString()))),
      );
    }
  }

  Future<void> _useTemplate(BuildContext context) async {
    final state = Provider.of<ReportState>(context, listen: false);
    final navigator = Navigator.of(context);
    final loc = AppLocalizations.of(context)!;
    final productType = _productTypeController.text.trim();
    final factory = _factoryController.text.trim();
    final model = _modelController.text.trim();

    if (productType.isEmpty ||
        factory.isEmpty ||
        model.isEmpty ||
        _selectedReport == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.fillAllFields)));
      return;
    }

    final reportName = '$factory ($productType) $model';

    state.newReport(
      reportName,
      _selectedReport!.questions,
      _selectedReport!.availableLanguages,
      productType: productType,
      factory: factory,
      model: model,
      headerImagePath: _headerImagePath,
    );

    if (_headerImagePath != null) {
      await state.addHeaderImage(File(_headerImagePath!));
    }

    await state.saveReport();
    if (!mounted) return;
    navigator.pushReplacementNamed('/fill');
  }

  void _updateReportName() {
    final productType = _productTypeController.text.trim();
    final factory = _factoryController.text.trim();
    final model = _modelController.text.trim();
    _reportNameController.text = '$factory ($productType) $model';
  }

  Future<void> _pickHeaderImage() async {
    final loc = AppLocalizations.of(context)!;
    // Диалог выбора фото — точно такой же как в карточке 0
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.addMediaTitle,
                  style: const TextStyle(
                    color: AppColors.border,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle(title: loc.createSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.camera_alt,
                  label: loc.takePhoto,
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: AppColors.grey300,
                    thickness: 1.5,
                    height: 1.5,
                  ),
                ),
                SectionTitle(title: loc.selectSection),
                const SizedBox(height: 8),
                PickerItem(
                  icon: Icons.photo_library,
                  label: loc.photoFromGallery,
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (action == null) return;

    setState(() {
      _isPickingPhoto = true;
    });

    try {
      final picker = ImagePicker();
      XFile? image;

      if (action == 'camera') {
        image = await picker.pickImage(source: ImageSource.camera);
      } else if (action == 'gallery') {
        image = await picker.pickImage(source: ImageSource.gallery);
      }

      if (image != null) {
        setState(() {
          _headerImagePath = image!.path;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingPhoto = false;
        });
      }
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
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.templateCopiedClipboard)));
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
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.templateSaved(file.path))));
      }
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.saveError(e.toString()))));
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
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.readError(e.toString()))));
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
    final loc = AppLocalizations.of(context)!;
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.enterTranslatedTemplate)));
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.translationAdded(langCode))));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.templateError(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width <= 800;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.copyTemplateInstructions,
          style: const TextStyle(color: AppColors.textLight),
        ),
        const SizedBox(height: 16),
        Text(
          loc.selectSourceLanguage,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedSourceLang,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 2),
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
                    style: const TextStyle(color: AppColors.textPrimary),
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
                label: Text(loc.copyTemplateButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveTemplateToFile,
                icon: const Icon(Icons.download),
                label: Text(loc.downloadButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Text(
          loc.pasteTranslatedTemplateLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _jsonController,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: loc.pasteTranslatedTemplateHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 2),
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
                label: Text(loc.loadFromFileButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.addTranslationTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: content,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        loc.cancel,
                        style: const TextStyle(color: AppColors.textLight),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _importTemplate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: Text(loc.addTranslationButton),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      return AlertDialog(
        insetPadding: const EdgeInsets.all(40),
        contentPadding: const EdgeInsets.all(24),
        title: Text(loc.addTranslationTitle),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              loc.cancel,
              style: const TextStyle(color: AppColors.textLight),
            ),
          ),
          ElevatedButton(
            onPressed: _importTemplate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border, width: 2),
            ),
            child: Text(loc.addTranslationButton),
          ),
        ],
      );
    }
  }
}

/// Виджет элемента выбора источника шаблона (в стиле PickerItem)
class _TemplateSourceItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _TemplateSourceItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: AppColors.border),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
