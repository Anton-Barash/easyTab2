// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EasyTab';

  @override
  String get back => 'Back';

  @override
  String get save => 'Save';

  @override
  String get saveAs => 'Save As...';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get ok => 'OK';

  @override
  String get add => 'Add';

  @override
  String get addAbove => 'Add Above';

  @override
  String get addBelow => 'Add Below';

  @override
  String get edit => 'Edit';

  @override
  String get name => 'Name';

  @override
  String get description => 'Description';

  @override
  String get enterName => 'Enter name...';

  @override
  String get enterDescription => 'Enter description...';

  @override
  String get enterAnswer => 'Enter answer...';

  @override
  String get question => 'Question';

  @override
  String get answer => 'Answer';

  @override
  String get addAnswer => 'Add Answer';

  @override
  String get addMedia => 'Add Media';

  @override
  String get takePhoto => 'Take Photo';

  @override
  String get takeVideo => 'Take Video';

  @override
  String get chooseFromGallery => 'Choose from Gallery';

  @override
  String get chooseVideoFromGallery => 'Choose video from gallery';

  @override
  String get chooseFromFiles => 'Choose from files';

  @override
  String get attention => 'Attention';

  @override
  String get needsWork => 'Needs Work';

  @override
  String get viewHtml => 'View HTML';

  @override
  String get saveZip => 'Save ZIP';

  @override
  String get share => 'Share';

  @override
  String get compressVideo => 'Compress Video';

  @override
  String get syncTranslations => 'Sync Translations';

  @override
  String get exportExcel => 'Export Excel';

  @override
  String get exit => 'Exit';

  @override
  String get showSidePanel => 'Show Side Panel';

  @override
  String get language => 'Language';

  @override
  String get appLanguage => 'App Language';

  @override
  String get noQuestions => 'No Questions';

  @override
  String get myReports => 'My Reports';

  @override
  String get newReport => 'New Report';

  @override
  String get fromTemplate => 'From Template';

  @override
  String get templateManager => 'Template Manager';

  @override
  String get newTemplate => 'New Template';

  @override
  String get importTemplate => 'Import Template';

  @override
  String get deleteReport => 'Delete this report?';

  @override
  String get deleteReportConfirm =>
      'Are you sure you want to delete this report?';

  @override
  String get cannotUndo => 'This action cannot be undone';

  @override
  String get reportDeleted => 'Report deleted';

  @override
  String get reportDeleteError => 'Error deleting report';

  @override
  String get createNewReport => '+ Create New Report';

  @override
  String get continueReport => 'Continue';

  @override
  String get openExistingReport => 'Open Existing Report';

  @override
  String get yourReports => 'Your Reports';

  @override
  String get instructionsText =>
      'Instructions: create a report, select a template,\nfill in the data and export!';

  @override
  String get htmlCopied => 'HTML copied to clipboard';

  @override
  String get excelHtmlCopied => 'Excel HTML copied to clipboard';

  @override
  String get saveZipWeb => 'Saving ZIP is not available on web';

  @override
  String get saveZipMobileHint => 'Use \"Share\" to save ZIP file';

  @override
  String get shareWeb => 'Share is not available on web';

  @override
  String get comingSoon => 'Loading existing reports — coming soon!';

  @override
  String get toggleView => 'Toggle View';

  @override
  String get newQuestionAbove => 'New Question Above';

  @override
  String get newQuestionBelow => 'New Question Below';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get chinese => '中文';

  @override
  String get noDescription => 'No description';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get confirmExit => 'Exit without saving?';

  @override
  String get createReportTitle => 'Create Report';

  @override
  String get deleteAnswerTitle => 'Delete answer?';

  @override
  String get changeAnswerTitle => 'Edit Answer';

  @override
  String get enterNewAnswerText => 'Enter new answer text';

  @override
  String get enterNewAnswerPlaceholder => 'Enter text for new answer';

  @override
  String get deleteQuestionTitle => 'Delete question?';

  @override
  String get addMediaTitle => 'Add Media';

  @override
  String get addMediaWebSoon => 'Adding media on web — coming soon!';

  @override
  String get addAnswerTooltip => 'Add answer';

  @override
  String get deleteAnswerTooltip => 'Delete answer';

  @override
  String get jsonCopiedToClipboard => 'JSON copied to clipboard';

  @override
  String get pasteTranslatedJson => 'Paste translated JSON';

  @override
  String get syncComplete => 'Sync complete';

  @override
  String syncAnswersTitle(Object lang) {
    return 'Sync Answers ($lang)';
  }

  @override
  String get copyButton => 'Copy';

  @override
  String get downloadButton => 'Download';

  @override
  String get loadFromFileButton => 'Load from file';

  @override
  String get syncButton => 'Sync';

  @override
  String get copyJsonButton => 'Copy JSON';

  @override
  String get syncMenuTitle => 'Sync Translations';

  @override
  String get syncStep1 => '1. Copy or download JSON with current answers';

  @override
  String get syncStep2 => '2. Send to AI for translating empty fields';

  @override
  String get syncStep3 => '3. Paste the result or upload the file';

  @override
  String get syncStep4 => '4. Press \"Sync\"';

  @override
  String get pasteJsonHere => 'Paste JSON here...';

  @override
  String copyError(String error) {
    return 'Copy error: $error';
  }

  @override
  String fileSaved(String path) {
    return 'File saved: $path';
  }

  @override
  String saveError(String error) {
    return 'Save error: $error';
  }

  @override
  String readError(String error) {
    return 'Read error: $error';
  }

  @override
  String invalidJsonError(String error) {
    return 'Error: invalid JSON format - $error';
  }

  @override
  String loadError(String error) {
    return 'Load error: $error';
  }

  @override
  String get templateLoadError => 'Error loading template';

  @override
  String get templateCopiedClipboard => 'Template copied to clipboard';

  @override
  String templateSaved(String path) {
    return 'Template saved to $path';
  }

  @override
  String get pasteTranslatedTemplate => 'Paste translated template';

  @override
  String translationAdded(String lang) {
    return 'Translation for $lang successfully added!';
  }

  @override
  String templateError(String error) {
    return 'Template error: $error';
  }

  @override
  String get copyTemplateButton => 'Copy Template';

  @override
  String get addTranslationButton => 'Add Translation';

  @override
  String get addTranslationTitle => 'Add Translation';

  @override
  String get deleteAnswerConfirm =>
      'Are you sure you want to delete this answer?\n\nThis action cannot be undone.';

  @override
  String get deleteQuestionConfirm =>
      'Are you sure you want to delete this question?';

  @override
  String get lockWarningText =>
      'Warning! Changing this answer will delete the text in other localizations.';

  @override
  String get replaceExistingAnswer => 'Replace existing answer:';

  @override
  String get orAddNewAnswer => 'Or add a new answer:';

  @override
  String get deleteThisQuestion => 'Delete this question';

  @override
  String get useAnyAi => 'Use any available AI.';

  @override
  String get aiPromptExample =>
      'Prompt example: Study the json, if some localization has no answer but it exists in another localization, translate and insert the translation; if no answers exist anywhere, leave the field empty.';

  @override
  String get aiPromptExample2 =>
      'AI prompt example: \"This json contains answers in different languages. Fill in empty answers with translations of existing answers.\"';

  @override
  String unsyncedQuestionsCount(int count) {
    return 'Unsynced questions: $count';
  }

  @override
  String get close => 'Close';

  @override
  String get aiPromptLabel => 'AI prompt example:';

  @override
  String get aiPromptContent =>
      '\"This json contains answers in different languages. Fill in empty answers with translations of existing answers.\"';

  @override
  String get enterDecryption => 'Enter description...';

  @override
  String get questions => 'Questions';

  @override
  String get hideAnswered => 'Hide answered';

  @override
  String get reportNameLabel => 'Report name';

  @override
  String get selectTemplate => 'Select template';

  @override
  String get builtInTemplate => 'Built-in template';

  @override
  String get builtInTemplateDesc => '4 questions, RU+EN';

  @override
  String get preview => 'Preview';

  @override
  String get noName => 'No name';

  @override
  String get useTemplate => 'Use template';

  @override
  String get uploadYourTemplate => 'Upload your template (.xlsx)';

  @override
  String get selected => 'Selected';

  @override
  String get enterTranslatedTemplate => 'Enter translated template';

  @override
  String get noAppToOpenHtml => 'Install a browser or app to view HTML';

  @override
  String get needsWorkTooltip => 'Question needs work...';

  @override
  String get removeAttentionMark => 'Remove \"Attention\" mark';

  @override
  String get addAttentionMark => 'Mark \"Attention\"';

  @override
  String get searchReports => 'Search reports...';

  @override
  String get noReportsYet => 'You have no reports yet';

  @override
  String get reportsNotFound => 'Reports not found';

  @override
  String get allAnswersSynced => 'All answers synced!';

  @override
  String get instructionsLabel => 'Instructions:';

  @override
  String get copyTemplateInstructions =>
      'Copy the template, translate it using any AI and paste the result.';

  @override
  String get selectSourceLanguage => '1. Select source language:';

  @override
  String get pasteTranslatedTemplateLabel => '2. Paste translated template:';

  @override
  String get uploadTranslatedJsonLabel => 'Upload translated JSON:';

  @override
  String get pasteTranslatedTemplateHint => 'Paste translated template here...';

  @override
  String get switchLanguage => 'Switch language';

  @override
  String get editName => 'Edit name';

  @override
  String get editDescription => 'Edit description';

  @override
  String zipSaved(Object path) {
    return 'ZIP saved to $path';
  }

  @override
  String saveZipError(Object error) {
    return 'Save ZIP error: $error';
  }

  @override
  String get lockAnswerTooltip => 'Lock answer';

  @override
  String get unlockAnswerTooltip => 'Unlock answer';

  @override
  String get saved => 'Saved';

  @override
  String get processingZip => 'Processing ZIP...';

  @override
  String get processingMedia => 'Adding files, please wait...';

  @override
  String get importingProject => 'Importing project...';

  @override
  String get projectImported => 'Project imported!';

  @override
  String get importError => 'Import error';

  @override
  String get headerInfo => 'Report information';

  @override
  String get productType => 'Product type';

  @override
  String get factory => 'Factory';

  @override
  String get model => 'Model';

  @override
  String get date => 'Date';

  @override
  String get editHeader => 'Edit header';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get deletePhoto => 'Delete photo';

  @override
  String get noPhoto => 'No photo';

  @override
  String get photo => 'Photo';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get fillAllFields => 'Please fill in all fields';

  @override
  String get compressVideoTitle => 'Compress Video';

  @override
  String get highQuality => 'High quality';

  @override
  String get highQualityDesc => 'Less compression, better quality';

  @override
  String get mediumQuality => 'Medium quality';

  @override
  String get mediumQualityDesc => 'Balanced compression';

  @override
  String get lowQuality => 'Low quality';

  @override
  String get lowQualityDesc => 'Maximum compression';

  @override
  String get compressingVideo => 'Compressing video...';

  @override
  String get noVideoToCompress =>
      'No video to compress or all already compressed';

  @override
  String get compressionComplete => 'Compression complete';

  @override
  String compressedVideoCount(int count) {
    return 'Compressed videos: $count';
  }

  @override
  String compressionError(String error) {
    return 'Compression error: $error';
  }

  @override
  String get importProject => 'Import project';

  @override
  String get newReportTooltip => 'New report';

  @override
  String get noSavedReports => 'No saved reports';

  @override
  String get loginButton => 'Login/Register';

  @override
  String get loginTitle => 'Login';

  @override
  String get usernameLabel => 'Username';

  @override
  String get emailLabel => 'Email (optional)';

  @override
  String get passwordLabel => 'Password';

  @override
  String get serverSettings => 'Server';

  @override
  String get serverLabel => 'Server address (host:port)';

  @override
  String get connectionOk => 'Connection successful';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get loginAction => 'Login';

  @override
  String get registerAction => 'Register';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get loginSuccess => 'Login successful';

  @override
  String get loginError => 'Login failed';

  @override
  String get registerTitle => 'Register';

  @override
  String get logoutAction => 'Logout';

  @override
  String get syncToCloud => 'Sync to cloud';

  @override
  String get syncingProgress => 'Syncing...';

  @override
  String get syncCompleteMessage => 'Sync complete';

  @override
  String get syncErrorMessage => 'Sync failed';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get accountSection => 'Account';

  @override
  String get uploadToServer => 'Upload to server';

  @override
  String get uploadingFiles => 'Uploading files...';

  @override
  String get uploadCompleteAll => 'All files uploaded successfully';

  @override
  String uploadCompletePartial(int count, int total) {
    return 'Upload complete: $count/$total files';
  }

  @override
  String get uploadError => 'Upload error';

  @override
  String get noFilesToUpload => 'No files to upload';

  @override
  String get loginRequired => 'Please login first';
}
