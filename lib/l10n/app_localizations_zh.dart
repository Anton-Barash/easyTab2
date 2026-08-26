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
  String get createSection => '创建';

  @override
  String get selectSection => '选择';

  @override
  String get takePhoto => '拍照';

  @override
  String get takeVideo => '拍视频';

  @override
  String get chooseFromGallery => '从图库选择';

  @override
  String get photoFromGallery => '从图库选择照片';

  @override
  String get chooseVideoFromGallery => '从图库选择视频';

  @override
  String get videoFromGallery => '从图库选择视频';

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
  String get syncTranslations => '同步翻译';

  @override
  String get exportExcel => '导出Excel';

  @override
  String get exit => '返回';

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
  String get reportDeleteError => '删除报告错误';

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
  String get saveZipMobileHint => '使用\"分享\"保存ZIP文件';

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
  String get hideAnswered => '隐藏已答';

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
  String get htmlRequiresSync => '要查看HTML，请先将报告保存到服务器';

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
  String get processingMedia => '正在添加文件，请稍候...';

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

  @override
  String get videoCompressionFailed => '视频压缩失败';

  @override
  String get videoCompressionIneffective => '压缩未减小视频大小';

  @override
  String get videoUploadFailed => '视频上传失败';

  @override
  String get ffmpegTrafficWarning => '视频正在浏览器中压缩。首次使用将下载约25MB。';

  @override
  String get importProject => '导入项目';

  @override
  String get newReportTooltip => '新报告';

  @override
  String get noSavedReports => '没有保存的报告';

  @override
  String get loginButton => '登录/注册';

  @override
  String get loginTitle => '登录';

  @override
  String get usernameLabel => '用户名';

  @override
  String get emailLabel => '邮箱（可选）';

  @override
  String get passwordLabel => '密码';

  @override
  String get serverSettings => '服务器';

  @override
  String get serverLabel => '服务器地址（主机:端口）';

  @override
  String get connectionOk => '连接成功';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get loginAction => '登录';

  @override
  String get registerAction => '注册';

  @override
  String get cancelAction => '取消';

  @override
  String get loginSuccess => '登录成功';

  @override
  String get loginError => '登录失败';

  @override
  String get registerTitle => '注册';

  @override
  String get logoutAction => '退出登录';

  @override
  String get syncToCloud => '同步到云端';

  @override
  String get syncingProgress => '正在同步...';

  @override
  String get syncCompleteMessage => '同步完成';

  @override
  String get syncErrorMessage => '同步失败';

  @override
  String get settingsTitle => '设置';

  @override
  String get accountSection => '账户';

  @override
  String get mediaQualitySection => '媒体质量';

  @override
  String get mediaImageQuality => '照片质量';

  @override
  String get mediaImageQualityHigh => '高 — 2000px / Q85';

  @override
  String get mediaImageQualityMedium => '中 — 1500px / Q85';

  @override
  String get mediaImageQualityLow => '低 — 1080px / Q80';

  @override
  String get mediaVideoQuality => '视频质量';

  @override
  String get mediaVideoQualityHigh => '高 — Full HD（低压缩）';

  @override
  String get mediaVideoQualityMedium => '中 — HD（均衡）';

  @override
  String get mediaVideoQualityLow => '低 — 480p（最大压缩，默认）';

  @override
  String get attachmentsTitle => '已附加文件';

  @override
  String get attachmentsEmpty => '未上传文件';

  @override
  String get attachmentsAddNew => '添加新文件';

  @override
  String get attachmentsAddHint => '选择文件（不超过 55 MB）';

  @override
  String get attachmentsTooLarge => '文件超过 55 MB — 请选择更小的文件';

  @override
  String get attachmentsUploadFailed => '文件上传到服务器失败';

  @override
  String get attachmentsDeleted => '文件已删除';

  @override
  String get attachmentsOpenFailed => '无法打开文件';

  @override
  String get attachmentsNote =>
      '上传照片或视频时，它们将在服务器上未经压缩保存。最大文件大小为 55 MB。对于照片和视频，建议使用替代的添加方法。';

  @override
  String get attachmentsForQuestion => '问题文件';

  @override
  String get deleteAttachmentTooltip => '删除文件';

  @override
  String get fileMenuDelete => '删除';

  @override
  String get mediaQualityMenuItem => '媒体质量选择';

  @override
  String get starsBackground => '星空背景';

  @override
  String get uploadToServer => '上传到服务器';

  @override
  String get uploadingFiles => '正在上传文件...';

  @override
  String get uploadCompleteAll => '所有文件上传成功';

  @override
  String uploadCompletePartial(int count, int total) {
    return '上传完成：$count/$total 个文件';
  }

  @override
  String get uploadError => '上传错误';

  @override
  String get noFilesToUpload => '没有可上传的文件';

  @override
  String get loginRequired => '请先登录';

  @override
  String get createShareLink => '创建分享链接';

  @override
  String get shareLinkCreated => '链接已创建';

  @override
  String get shareLinkLabel => '链接';

  @override
  String get shareLinkExpiresIn => '有效期';

  @override
  String get sharePermissionEdit => '编辑';

  @override
  String get sharePermissionView => '仅查看';

  @override
  String get shareLinkCopy => '复制';

  @override
  String get shareLinkClose => '关闭';

  @override
  String get shareLinkDays => '天';

  @override
  String get shareLinkSaveFirst => '请先保存报告到服务器';

  @override
  String get shareLinkError => '创建链接失败';

  @override
  String get shareAccess => '访问权限';

  @override
  String get shareLinkCopied => '已复制';

  @override
  String get templateSourceFile => 'Excel (.xlsx), JSON, ZIP';

  @override
  String get templateSourceFileDesc => '上传模板文件';

  @override
  String get templateSourceJson => '粘贴 JSON';

  @override
  String get templateSourceJsonDesc => '手动粘贴JSON代码';

  @override
  String get templateDownloadSample => '下载示例';

  @override
  String get templateDownloadSampleDesc => 'JSON模板示例';

  @override
  String get jsonTemplateTitle => '粘贴JSON模板';

  @override
  String get jsonTemplateHint => 'questions: [...], availableLanguages: [...]';

  @override
  String get loadJsonButton => '加载';

  @override
  String get jsonParseError => 'JSON解析错误';

  @override
  String templateSampleSaved(String path) {
    return '示例已保存: $path';
  }

  @override
  String templateSaveError(String error) {
    return '保存错误: $error';
  }

  @override
  String get takePhotoCamera => '拍照';

  @override
  String get takePhotoCameraDesc => '使用相机拍照';

  @override
  String get photoFromGalleryHeader => '从图库选择';

  @override
  String get photoFromGalleryHeaderDesc => '加载现有照片';

  @override
  String get compressVideoTitle => '压缩视频';

  @override
  String get highQuality => '高质量';

  @override
  String get highQualityDesc => '较少压缩，更好质量';

  @override
  String get mediumQuality => '中等质量';

  @override
  String get mediumQualityDesc => '平衡压缩';

  @override
  String get lowQuality => '低质量';

  @override
  String get lowQualityDesc => '最大压缩';

  @override
  String get compressingVideo => '正在压缩视频...';

  @override
  String get noVideoToCompress => '没有视频可压缩或已全部压缩';

  @override
  String get compressionComplete => '压缩完成';

  @override
  String compressedVideoCount(int count) {
    return '已压缩视频：$count';
  }

  @override
  String compressionError(String error) {
    return '压缩错误：$error';
  }

  @override
  String get reportIdMissing => '缺少报告ID';

  @override
  String get shareTokenMissing => '缺少分享链接令牌';

  @override
  String reportNumber(String id) {
    return '报告 #$id';
  }

  @override
  String get refresh => '刷新';

  @override
  String get retry => '重试';

  @override
  String get htmlWebOnly => 'HTML查看仅在网页版中可用。';

  @override
  String get loadReportFailed => '无法加载报告';

  @override
  String get loadLinkFailed => '无法加载链接';

  @override
  String get reportFromLinkLoadFailed => '无法从链接加载报告';

  @override
  String get htmlOpenedInNewTab => 'HTML报告已在新标签页中打开';

  @override
  String get invalidFileFormat => '文件格式无效';

  @override
  String get fileTooLarge => '文件太大（最大10MB）';

  @override
  String get photoAdded => '照片已添加';

  @override
  String errorWithDetail(String error) {
    return '错误：$error';
  }

  @override
  String get openHtmlTooltip => '打开HTML';

  @override
  String get deleteMediaTitle => '删除？';

  @override
  String get deleteMediaConfirm => '文件将被永久删除。';

  @override
  String get compressing => '正在压缩...';

  @override
  String get finalizing => '正在完成...';

  @override
  String get uploading => '正在上传...';

  @override
  String get enterCredentials => '请输入用户名和密码';

  @override
  String get registerFailed => '注册失败';

  @override
  String get langCodeRequired => 'language_code 字段必须是非空字符串';

  @override
  String get questionsMustBeArray => 'questions 字段必须是数组';

  @override
  String questionsCountMismatch(int expected, int actual) {
    return '应为 $expected 个问题，实际收到 $actual';
  }

  @override
  String questionMustBeObject(int index) {
    return '问题 $index 必须是对象';
  }

  @override
  String questionIdMustBeNumber(int index) {
    return '问题 $index：id 字段必须是数字';
  }

  @override
  String questionNameRequired(int index) {
    return '问题 $index：name 字段必须是非空字符串';
  }

  @override
  String questionDescriptionRequired(int index) {
    return '问题 $index：description 字段必须是非空字符串';
  }

  @override
  String unsupportedFormat(String ext) {
    return '不支持的文件格式：.$ext\n支持：.xlsx, .json, .zip';
  }

  @override
  String get excelMinRows => 'Excel 文件必须至少包含3行：标题、语言代码和问题';

  @override
  String get excelNoQuestions => '在 Excel 文件中未找到问题。请确保问题从第3行开始。';

  @override
  String excelReadError(String error) {
    return '读取 Excel 文件错误：$error';
  }

  @override
  String jsonReadError(String error) {
    return '读取 JSON 文件错误：$error';
  }

  @override
  String invalidJsonDetail(String message) {
    return 'JSON 无效：$message';
  }

  @override
  String jsonParseDetail(String error) {
    return 'JSON 解析错误：$error';
  }

  @override
  String get jsonNoQuestions => 'JSON 不包含问题（\"questions\" 字段缺失或为空）';

  @override
  String get jsonNoValidQuestions =>
      '在 JSON 中未找到有效问题。每个问题必须包含 \"localizations\"';

  @override
  String jsonStructureError(String error) {
    return 'JSON 结构错误：$error';
  }

  @override
  String get zipNoJson => '在 ZIP 存档中未找到报告 JSON 文件。应为 report.json 或其他 .json 文件';

  @override
  String zipReadError(String error) {
    return '读取 ZIP 存档错误：$error';
  }

  @override
  String get sharedReport => '共享报告';

  @override
  String get editAccess => '编辑权限';

  @override
  String get viewOnlyAccess => '仅查看权限';

  @override
  String get linkValidUntil => '链接有效期至';

  @override
  String get downloadApp => '下载应用';

  @override
  String get downloadAppDesc => '适用于 Android 或 Windows';

  @override
  String get openWebEditor => '编辑';

  @override
  String get openWebEditorDesc => '编辑报告';

  @override
  String get openHtmlDesc => '在浏览器中查看';

  @override
  String get downloadZipDesc => '包含媒体的离线报告';

  @override
  String get appLinksStub => '应用下载链接将在此处';

  @override
  String get viewOnlyWarning => '仅可查看。如需编辑，请向报告所有者申请权限。';

  @override
  String get downloadZip => '下载 ZIP';

  @override
  String get unknownError => '未知错误';

  @override
  String statusError(int statusCode) {
    return '错误 $statusCode';
  }

  @override
  String invalidServerResponse(int statusCode) {
    return '服务器响应无效：$statusCode';
  }

  @override
  String get noServerConnection => '无法连接服务器';

  @override
  String networkError(String error) {
    return '网络错误：$error';
  }

  @override
  String uploadErrorDetail(String error) {
    return '上传错误：$error';
  }

  @override
  String get uploadNoneFailed => '未能上传任何文件';

  @override
  String uploadFailedStatus(int status) {
    return '上传失败（$status）';
  }

  @override
  String get uploadFailedGeneric => '上传错误';

  @override
  String get uploadTimeout => '上传超时';

  @override
  String get presignFailed => '无法创建上传链接';

  @override
  String get confirmFailed => '无法确认上传';
}
