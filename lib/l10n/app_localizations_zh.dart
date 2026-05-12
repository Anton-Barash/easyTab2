// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'EasyTab';

  @override
  String get back => '返回';

  @override
  String get save => '保存';

  @override
  String get saveAs => '另存为...';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get ok => '确定';

  @override
  String get add => '添加';

  @override
  String get addAbove => '在上方添加';

  @override
  String get addBelow => '在下方添加';

  @override
  String get edit => '编辑';

  @override
  String get name => '名称';

  @override
  String get description => '描述';

  @override
  String get enterName => '输入名称...';

  @override
  String get enterDescription => '输入描述...';

  @override
  String get enterAnswer => '输入答案...';

  @override
  String get question => '问题';

  @override
  String get answer => '答案';

  @override
  String get addAnswer => '添加答案';

  @override
  String get addMedia => '添加媒体';

  @override
  String get takePhoto => '拍照';

  @override
  String get takeVideo => '拍视频';

  @override
  String get chooseFromGallery => '从图库选择';

  @override
  String get chooseVideoFromGallery => 'Choose video from gallery';

  @override
  String get chooseFromFiles => '从文件选择';

  @override
  String get attention => '注意';

  @override
  String get needsWork => '需要修改';

  @override
  String get viewHtml => '查看HTML';

  @override
  String get saveZip => '保存ZIP';

  @override
  String get share => '分享';

  @override
  String get compressVideo => '压缩视频';

  @override
  String get syncTranslations => '同步翻译';

  @override
  String get exportExcel => '导出Excel';

  @override
  String get exit => '退出';

  @override
  String get showSidePanel => '显示侧边栏';

  @override
  String get language => '语言';

  @override
  String get appLanguage => '应用语言';

  @override
  String get noQuestions => '没有问题';

  @override
  String get myReports => '我的报告';

  @override
  String get newReport => '新报告';

  @override
  String get fromTemplate => '从模板';

  @override
  String get templateManager => '模板管理器';

  @override
  String get newTemplate => '新模板';

  @override
  String get importTemplate => '导入模板';

  @override
  String get deleteReport => '删除此报告?';

  @override
  String get deleteReportConfirm => '您确定要删除此报告吗?';

  @override
  String get cannotUndo => '此操作无法撤消';

  @override
  String get reportDeleted => '报告已删除';

  @override
  String get createNewReport => '+ 创建新报告';

  @override
  String get continueReport => '继续';

  @override
  String get openExistingReport => '打开现有报告';

  @override
  String get yourReports => '您的报告';

  @override
  String get instructionsText => '说明：创建报告，选择模板，\n填写数据并导出！';

  @override
  String get htmlCopied => 'HTML已复制到剪贴板';

  @override
  String get excelHtmlCopied => 'Excel HTML已复制到剪贴板';

  @override
  String get saveZipWeb => '在Web上无法保存ZIP';

  @override
  String get shareWeb => '在Web上无法分享';

  @override
  String get comingSoon => '加载现有报告 — 即将推出！';

  @override
  String get toggleView => '切换视图';

  @override
  String get newQuestionAbove => '在上方添加新问题';

  @override
  String get newQuestionBelow => '在下方添加新问题';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get chinese => '中文';

  @override
  String get noDescription => '没有描述';

  @override
  String get unsavedChanges => '未保存的更改';

  @override
  String get confirmExit => '不保存就退出？';

  @override
  String get createReportTitle => '创建报告';

  @override
  String get deleteAnswerTitle => '删除答案?';

  @override
  String get changeAnswerTitle => '编辑答案';

  @override
  String get enterNewAnswerText => '输入新的答案文本';

  @override
  String get enterNewAnswerPlaceholder => '输入新答案文本';

  @override
  String get deleteQuestionTitle => '删除问题?';

  @override
  String get addMediaTitle => '添加媒体';

  @override
  String get addMediaWebSoon => '网页添加媒体 — 即将推出！';

  @override
  String get addAnswerTooltip => '添加答案';

  @override
  String get deleteAnswerTooltip => '删除答案';

  @override
  String get jsonCopiedToClipboard => 'JSON已复制到剪贴板';

  @override
  String get pasteTranslatedJson => '请粘贴翻译后的JSON';

  @override
  String get syncComplete => '同步完成';

  @override
  String syncAnswersTitle(Object lang) {
    return '同步答案 ($lang)';
  }

  @override
  String get copyButton => '复制';

  @override
  String get downloadButton => '下载';

  @override
  String get loadFromFileButton => '从文件加载';

  @override
  String get syncButton => '同步';

  @override
  String get copyJsonButton => '复制JSON';

  @override
  String get syncMenuTitle => '同步翻译';

  @override
  String get syncStep1 => '1. 复制或下载包含当前答案的JSON';

  @override
  String get syncStep2 => '2. 发送给AI翻译空白字段';

  @override
  String get syncStep3 => '3. 粘贴结果或上传文件';

  @override
  String get syncStep4 => '4. 点击\"同步\"';

  @override
  String get pasteJsonHere => '在此粘贴JSON...';

  @override
  String copyError(String error) {
    return '复制错误：$error';
  }

  @override
  String fileSaved(String path) {
    return '文件已保存：$path';
  }

  @override
  String saveError(String error) {
    return '保存错误：$error';
  }

  @override
  String readError(String error) {
    return '读取文件错误：$error';
  }

  @override
  String invalidJsonError(String error) {
    return '错误：JSON格式无效 - $error';
  }

  @override
  String loadError(String error) {
    return '加载错误：$error';
  }

  @override
  String get templateLoadError => '加载模板错误';

  @override
  String get templateCopiedClipboard => '模板已复制到剪贴板';

  @override
  String templateSaved(String path) {
    return '模板已保存到 $path';
  }

  @override
  String get pasteTranslatedTemplate => '请粘贴翻译后的模板';

  @override
  String translationAdded(String lang) {
    return '$lang翻译已成功添加！';
  }

  @override
  String templateError(String error) {
    return '模板错误：$error';
  }

  @override
  String get copyTemplateButton => '复制模板';

  @override
  String get addTranslationButton => '添加翻译';

  @override
  String get addTranslationTitle => '添加翻译';

  @override
  String get deleteAnswerConfirm => '您确定要删除此答案吗？\n\n此操作无法撤消。';

  @override
  String get deleteQuestionConfirm => '您确定要删除此问题吗？';

  @override
  String get lockWarningText => '警告！更改此答案将删除其他语言版本中的文本。';

  @override
  String get replaceExistingAnswer => '替换现有答案：';

  @override
  String get orAddNewAnswer => '或添加新答案：';

  @override
  String get deleteThisQuestion => '删除此问题';

  @override
  String get useAnyAi => '使用任何可用的AI。';

  @override
  String get aiPromptExample =>
      '提示示例：研究json，如果某个语言版本没有答案但其他语言版本有，请翻译并插入译文；如果所有地方都没有答案，请留空。';

  @override
  String get aiPromptExample2 => 'AI提示示例：\"此json包含不同语言的答案。用现有答案的翻译填写空白答案。\"';

  @override
  String unsyncedQuestionsCount(int count) {
    return '未同步的问题：$count';
  }

  @override
  String get close => '关闭';

  @override
  String get aiPromptLabel => 'AI提示示例：';

  @override
  String get aiPromptContent => '\"此json包含不同语言的答案。用现有答案的翻译填写空白答案。\"';

  @override
  String get enterDecryption => '输入描述...';

  @override
  String get questions => '问题';

  @override
  String get reportNameLabel => '报告名称';

  @override
  String get selectTemplate => '选择模板';

  @override
  String get builtInTemplate => '内置模板';

  @override
  String get builtInTemplateDesc => '4个问题，RU+EN';

  @override
  String get preview => '预览';

  @override
  String get noName => '无名称';

  @override
  String get useTemplate => '使用模板';

  @override
  String get uploadYourTemplate => '上传您的模板 (.xlsx)';

  @override
  String get selected => '已选择';

  @override
  String get enterTranslatedTemplate => '输入翻译后的模板';

  @override
  String get noAppToOpenHtml => '请安装浏览器或应用程序查看HTML';

  @override
  String get needsWorkTooltip => '问题需要修改...';

  @override
  String get removeAttentionMark => '取消\"注意\"标记';

  @override
  String get addAttentionMark => '标记\"注意\"';

  @override
  String get searchReports => '搜索报告...';

  @override
  String get noReportsYet => '您还没有报告';

  @override
  String get reportsNotFound => '未找到报告';

  @override
  String get allAnswersSynced => '所有答案已同步！';

  @override
  String get instructionsLabel => '说明：';

  @override
  String get copyTemplateInstructions => '复制模板，使用AI翻译成所需语言，然后粘贴结果。';

  @override
  String get selectSourceLanguage => '1. 选择源语言：';

  @override
  String get pasteTranslatedTemplateLabel => '2. 粘贴翻译后的模板：';

  @override
  String get uploadTranslatedJsonLabel => '上传翻译后的JSON：';

  @override
  String get pasteTranslatedTemplateHint => '在此粘贴翻译后的模板...';

  @override
  String get switchLanguage => '切换语言';

  @override
  String get editName => '编辑名称';

  @override
  String get editDescription => '编辑描述';

  @override
  String zipSaved(Object path) {
    return 'ZIP已保存到 $path';
  }

  @override
  String saveZipError(Object error) {
    return '保存ZIP错误：$error';
  }

  @override
  String get lockAnswerTooltip => '锁定答案';

  @override
  String get unlockAnswerTooltip => '解锁答案';

  @override
  String get saved => '已保存';

  @override
  String get processingZip => '正在处理ZIP...';

  @override
  String get importingProject => '正在导入项目...';

  @override
  String get projectImported => '项目导入成功！';

  @override
  String get importError => '导入错误';

  @override
  String get headerInfo => '报告信息';

  @override
  String get productType => '产品类型';

  @override
  String get factory => '工厂';

  @override
  String get model => '型号';

  @override
  String get date => '日期';

  @override
  String get editHeader => '编辑标题';

  @override
  String get changePhoto => '更改照片';

  @override
  String get deletePhoto => '删除照片';

  @override
  String get noPhoto => '无照片';

  @override
  String get photo => '照片';

  @override
  String get addPhoto => '添加照片';

  @override
  String get fillAllFields => '请填写所有字段';
}
