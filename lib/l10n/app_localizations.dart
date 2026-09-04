import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'EasyTab'**
  String get appTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get saveAs;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addAbove.
  ///
  /// In en, this message translates to:
  /// **'Add Above'**
  String get addAbove;

  /// No description provided for @addBelow.
  ///
  /// In en, this message translates to:
  /// **'Add Below'**
  String get addBelow;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter name...'**
  String get enterName;

  /// No description provided for @enterDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter description...'**
  String get enterDescription;

  /// No description provided for @enterAnswer.
  ///
  /// In en, this message translates to:
  /// **'Enter answer...'**
  String get enterAnswer;

  /// No description provided for @question.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get question;

  /// No description provided for @answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// No description provided for @addAnswer.
  ///
  /// In en, this message translates to:
  /// **'Add Answer'**
  String get addAnswer;

  /// No description provided for @addMedia.
  ///
  /// In en, this message translates to:
  /// **'Add Media'**
  String get addMedia;

  /// No description provided for @createSection.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createSection;

  /// No description provided for @selectSection.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectSection;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @takeVideo.
  ///
  /// In en, this message translates to:
  /// **'Take Video'**
  String get takeVideo;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @photoFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo from Gallery'**
  String get photoFromGallery;

  /// No description provided for @chooseVideoFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose video from gallery'**
  String get chooseVideoFromGallery;

  /// No description provided for @videoFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Video from Gallery'**
  String get videoFromGallery;

  /// No description provided for @chooseFromFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose from files'**
  String get chooseFromFiles;

  /// No description provided for @attention.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get attention;

  /// No description provided for @needsWork.
  ///
  /// In en, this message translates to:
  /// **'Needs Work'**
  String get needsWork;

  /// No description provided for @viewHtml.
  ///
  /// In en, this message translates to:
  /// **'View HTML'**
  String get viewHtml;

  /// No description provided for @saveZip.
  ///
  /// In en, this message translates to:
  /// **'Save ZIP'**
  String get saveZip;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @syncTranslations.
  ///
  /// In en, this message translates to:
  /// **'Sync Translations'**
  String get syncTranslations;

  /// No description provided for @exportExcel.
  ///
  /// In en, this message translates to:
  /// **'Export Excel'**
  String get exportExcel;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get exit;

  /// No description provided for @showSidePanel.
  ///
  /// In en, this message translates to:
  /// **'Show Side Panel'**
  String get showSidePanel;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get appLanguage;

  /// No description provided for @noQuestions.
  ///
  /// In en, this message translates to:
  /// **'No Questions'**
  String get noQuestions;

  /// No description provided for @myReports.
  ///
  /// In en, this message translates to:
  /// **'My Reports'**
  String get myReports;

  /// No description provided for @newReport.
  ///
  /// In en, this message translates to:
  /// **'New Report'**
  String get newReport;

  /// No description provided for @fromTemplate.
  ///
  /// In en, this message translates to:
  /// **'From Template'**
  String get fromTemplate;

  /// No description provided for @templateManager.
  ///
  /// In en, this message translates to:
  /// **'Template Manager'**
  String get templateManager;

  /// No description provided for @newTemplate.
  ///
  /// In en, this message translates to:
  /// **'New Template'**
  String get newTemplate;

  /// No description provided for @importTemplate.
  ///
  /// In en, this message translates to:
  /// **'Import Template'**
  String get importTemplate;

  /// No description provided for @deleteReport.
  ///
  /// In en, this message translates to:
  /// **'Delete this report?'**
  String get deleteReport;

  /// No description provided for @deleteReportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this report?'**
  String get deleteReportConfirm;

  /// No description provided for @cannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone'**
  String get cannotUndo;

  /// No description provided for @reportDeleted.
  ///
  /// In en, this message translates to:
  /// **'Report deleted'**
  String get reportDeleted;

  /// No description provided for @reportDeleteError.
  ///
  /// In en, this message translates to:
  /// **'Error deleting report'**
  String get reportDeleteError;

  /// No description provided for @createNewReport.
  ///
  /// In en, this message translates to:
  /// **'+ Create New Report'**
  String get createNewReport;

  /// No description provided for @continueReport.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueReport;

  /// No description provided for @openExistingReport.
  ///
  /// In en, this message translates to:
  /// **'Open Existing Report'**
  String get openExistingReport;

  /// No description provided for @yourReports.
  ///
  /// In en, this message translates to:
  /// **'Your Reports'**
  String get yourReports;

  /// No description provided for @instructionsText.
  ///
  /// In en, this message translates to:
  /// **'Instructions: create a report, select a template,\nfill in the data and export!'**
  String get instructionsText;

  /// No description provided for @htmlCopied.
  ///
  /// In en, this message translates to:
  /// **'HTML copied to clipboard'**
  String get htmlCopied;

  /// No description provided for @excelHtmlCopied.
  ///
  /// In en, this message translates to:
  /// **'Excel HTML copied to clipboard'**
  String get excelHtmlCopied;

  /// No description provided for @saveZipWeb.
  ///
  /// In en, this message translates to:
  /// **'Saving ZIP is not available on web'**
  String get saveZipWeb;

  /// No description provided for @saveZipMobileHint.
  ///
  /// In en, this message translates to:
  /// **'Use \"Share\" to save ZIP file'**
  String get saveZipMobileHint;

  /// No description provided for @shareWeb.
  ///
  /// In en, this message translates to:
  /// **'Share is not available on web'**
  String get shareWeb;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Loading existing reports — coming soon!'**
  String get comingSoon;

  /// No description provided for @toggleView.
  ///
  /// In en, this message translates to:
  /// **'Toggle View'**
  String get toggleView;

  /// No description provided for @newQuestionAbove.
  ///
  /// In en, this message translates to:
  /// **'New Question Above'**
  String get newQuestionAbove;

  /// No description provided for @newQuestionBelow.
  ///
  /// In en, this message translates to:
  /// **'New Question Below'**
  String get newQuestionBelow;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @russian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get russian;

  /// No description provided for @chinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get noDescription;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @confirmExit.
  ///
  /// In en, this message translates to:
  /// **'Exit without saving?'**
  String get confirmExit;

  /// No description provided for @createReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Report'**
  String get createReportTitle;

  /// No description provided for @deleteAnswerTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete answer?'**
  String get deleteAnswerTitle;

  /// No description provided for @changeAnswerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Answer'**
  String get changeAnswerTitle;

  /// No description provided for @enterNewAnswerText.
  ///
  /// In en, this message translates to:
  /// **'Enter new answer text'**
  String get enterNewAnswerText;

  /// No description provided for @enterNewAnswerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter text for new answer'**
  String get enterNewAnswerPlaceholder;

  /// No description provided for @deleteQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete question?'**
  String get deleteQuestionTitle;

  /// No description provided for @addMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Media'**
  String get addMediaTitle;

  /// No description provided for @addMediaWebSoon.
  ///
  /// In en, this message translates to:
  /// **'Adding media on web — coming soon!'**
  String get addMediaWebSoon;

  /// No description provided for @addAnswerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add answer'**
  String get addAnswerTooltip;

  /// No description provided for @deleteAnswerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete answer'**
  String get deleteAnswerTooltip;

  /// No description provided for @jsonCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'JSON copied to clipboard'**
  String get jsonCopiedToClipboard;

  /// No description provided for @pasteTranslatedJson.
  ///
  /// In en, this message translates to:
  /// **'Paste translated JSON'**
  String get pasteTranslatedJson;

  /// No description provided for @syncComplete.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get syncComplete;

  /// No description provided for @syncAnswersTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync Answers ({lang})'**
  String syncAnswersTitle(Object lang);

  /// No description provided for @copyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButton;

  /// No description provided for @downloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadButton;

  /// No description provided for @loadFromFileButton.
  ///
  /// In en, this message translates to:
  /// **'Load from file'**
  String get loadFromFileButton;

  /// No description provided for @syncButton.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncButton;

  /// No description provided for @copyJsonButton.
  ///
  /// In en, this message translates to:
  /// **'Copy JSON'**
  String get copyJsonButton;

  /// No description provided for @syncMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync Translations'**
  String get syncMenuTitle;

  /// No description provided for @syncStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Copy or download JSON with current answers'**
  String get syncStep1;

  /// No description provided for @syncStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Send to AI for translating empty fields'**
  String get syncStep2;

  /// No description provided for @syncStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Paste the result or upload the file'**
  String get syncStep3;

  /// No description provided for @syncStep4.
  ///
  /// In en, this message translates to:
  /// **'4. Press \"Sync\"'**
  String get syncStep4;

  /// No description provided for @pasteJsonHere.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON here...'**
  String get pasteJsonHere;

  /// No description provided for @copyError.
  ///
  /// In en, this message translates to:
  /// **'Copy error: {error}'**
  String copyError(String error);

  /// No description provided for @fileSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved: {path}'**
  String fileSaved(String path);

  /// No description provided for @saveError.
  ///
  /// In en, this message translates to:
  /// **'Save error: {error}'**
  String saveError(String error);

  /// No description provided for @readError.
  ///
  /// In en, this message translates to:
  /// **'Read error: {error}'**
  String readError(String error);

  /// No description provided for @invalidJsonError.
  ///
  /// In en, this message translates to:
  /// **'Error: invalid JSON format - {error}'**
  String invalidJsonError(String error);

  /// No description provided for @loadError.
  ///
  /// In en, this message translates to:
  /// **'Load error: {error}'**
  String loadError(String error);

  /// No description provided for @templateLoadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading template'**
  String get templateLoadError;

  /// No description provided for @templateCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Template copied to clipboard'**
  String get templateCopiedClipboard;

  /// No description provided for @templateSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved to {path}'**
  String templateSaved(String path);

  /// No description provided for @pasteTranslatedTemplate.
  ///
  /// In en, this message translates to:
  /// **'Paste translated template'**
  String get pasteTranslatedTemplate;

  /// No description provided for @translationAdded.
  ///
  /// In en, this message translates to:
  /// **'Translation for {lang} successfully added!'**
  String translationAdded(String lang);

  /// No description provided for @templateError.
  ///
  /// In en, this message translates to:
  /// **'Template error: {error}'**
  String templateError(String error);

  /// No description provided for @copyTemplateButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Template'**
  String get copyTemplateButton;

  /// No description provided for @addTranslationButton.
  ///
  /// In en, this message translates to:
  /// **'Add Translation'**
  String get addTranslationButton;

  /// No description provided for @addTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Translation'**
  String get addTranslationTitle;

  /// No description provided for @deleteAnswerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this answer?\n\nThis action cannot be undone.'**
  String get deleteAnswerConfirm;

  /// No description provided for @deleteQuestionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this question?'**
  String get deleteQuestionConfirm;

  /// No description provided for @lockWarningText.
  ///
  /// In en, this message translates to:
  /// **'Warning! Changing this answer will delete the text in other localizations.'**
  String get lockWarningText;

  /// No description provided for @replaceExistingAnswer.
  ///
  /// In en, this message translates to:
  /// **'Replace existing answer:'**
  String get replaceExistingAnswer;

  /// No description provided for @orAddNewAnswer.
  ///
  /// In en, this message translates to:
  /// **'Or add a new answer:'**
  String get orAddNewAnswer;

  /// No description provided for @deleteThisQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete this question'**
  String get deleteThisQuestion;

  /// No description provided for @useAnyAi.
  ///
  /// In en, this message translates to:
  /// **'Use any available AI.'**
  String get useAnyAi;

  /// No description provided for @aiPromptExample.
  ///
  /// In en, this message translates to:
  /// **'Prompt example: Study the json, if some localization has no answer but it exists in another localization, translate and insert the translation; if no answers exist anywhere, leave the field empty.'**
  String get aiPromptExample;

  /// No description provided for @aiPromptExample2.
  ///
  /// In en, this message translates to:
  /// **'AI prompt example: \"This json contains answers in different languages. Fill in empty answers with translations of existing answers.\"'**
  String get aiPromptExample2;

  /// No description provided for @unsyncedQuestionsCount.
  ///
  /// In en, this message translates to:
  /// **'Unsynced questions: {count}'**
  String unsyncedQuestionsCount(int count);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @aiPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'AI prompt example:'**
  String get aiPromptLabel;

  /// No description provided for @aiPromptContent.
  ///
  /// In en, this message translates to:
  /// **'\"This json contains answers in different languages. Fill in empty answers with translations of existing answers.\"'**
  String get aiPromptContent;

  /// No description provided for @enterDecryption.
  ///
  /// In en, this message translates to:
  /// **'Enter transcription...'**
  String get enterDecryption;

  /// No description provided for @transcription.
  ///
  /// In en, this message translates to:
  /// **'Transcription'**
  String get transcription;

  /// No description provided for @editTranscription.
  ///
  /// In en, this message translates to:
  /// **'Edit transcription'**
  String get editTranscription;

  /// No description provided for @questions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get questions;

  /// No description provided for @hideAnswered.
  ///
  /// In en, this message translates to:
  /// **'Hide answered'**
  String get hideAnswered;

  /// No description provided for @reportNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Report name'**
  String get reportNameLabel;

  /// No description provided for @selectTemplate.
  ///
  /// In en, this message translates to:
  /// **'Select template'**
  String get selectTemplate;

  /// No description provided for @builtInTemplate.
  ///
  /// In en, this message translates to:
  /// **'Built-in template'**
  String get builtInTemplate;

  /// No description provided for @builtInTemplateDesc.
  ///
  /// In en, this message translates to:
  /// **'4 questions, RU+EN'**
  String get builtInTemplateDesc;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @noName.
  ///
  /// In en, this message translates to:
  /// **'No name'**
  String get noName;

  /// No description provided for @useTemplate.
  ///
  /// In en, this message translates to:
  /// **'Use template'**
  String get useTemplate;

  /// No description provided for @uploadYourTemplate.
  ///
  /// In en, this message translates to:
  /// **'Upload your template (.xlsx)'**
  String get uploadYourTemplate;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @enterTranslatedTemplate.
  ///
  /// In en, this message translates to:
  /// **'Enter translated template'**
  String get enterTranslatedTemplate;

  /// No description provided for @noAppToOpenHtml.
  ///
  /// In en, this message translates to:
  /// **'Install a browser or app to view HTML'**
  String get noAppToOpenHtml;

  /// No description provided for @htmlRequiresSync.
  ///
  /// In en, this message translates to:
  /// **'To view HTML, save the report to the server first'**
  String get htmlRequiresSync;

  /// No description provided for @needsWorkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Question needs work...'**
  String get needsWorkTooltip;

  /// No description provided for @removeAttentionMark.
  ///
  /// In en, this message translates to:
  /// **'Remove \"Attention\" mark'**
  String get removeAttentionMark;

  /// No description provided for @addAttentionMark.
  ///
  /// In en, this message translates to:
  /// **'Mark \"Attention\"'**
  String get addAttentionMark;

  /// No description provided for @searchReports.
  ///
  /// In en, this message translates to:
  /// **'Search reports...'**
  String get searchReports;

  /// No description provided for @noReportsYet.
  ///
  /// In en, this message translates to:
  /// **'You have no reports yet'**
  String get noReportsYet;

  /// No description provided for @reportsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Reports not found'**
  String get reportsNotFound;

  /// No description provided for @allAnswersSynced.
  ///
  /// In en, this message translates to:
  /// **'All answers synced!'**
  String get allAnswersSynced;

  /// No description provided for @instructionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Instructions:'**
  String get instructionsLabel;

  /// No description provided for @copyTemplateInstructions.
  ///
  /// In en, this message translates to:
  /// **'Copy the template, translate it using any AI and paste the result.'**
  String get copyTemplateInstructions;

  /// No description provided for @selectSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'1. Select source language:'**
  String get selectSourceLanguage;

  /// No description provided for @pasteTranslatedTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'2. Paste translated template:'**
  String get pasteTranslatedTemplateLabel;

  /// No description provided for @uploadTranslatedJsonLabel.
  ///
  /// In en, this message translates to:
  /// **'Upload translated JSON:'**
  String get uploadTranslatedJsonLabel;

  /// No description provided for @pasteTranslatedTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Paste translated template here...'**
  String get pasteTranslatedTemplateHint;

  /// No description provided for @switchLanguage.
  ///
  /// In en, this message translates to:
  /// **'Switch language'**
  String get switchLanguage;

  /// No description provided for @editName.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get editName;

  /// No description provided for @editDescription.
  ///
  /// In en, this message translates to:
  /// **'Transcription'**
  String get editDescription;

  /// No description provided for @zipSaved.
  ///
  /// In en, this message translates to:
  /// **'ZIP saved to {path}'**
  String zipSaved(Object path);

  /// No description provided for @saveZipError.
  ///
  /// In en, this message translates to:
  /// **'Save ZIP error: {error}'**
  String saveZipError(Object error);

  /// No description provided for @lockAnswerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Lock answer'**
  String get lockAnswerTooltip;

  /// No description provided for @unlockAnswerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unlock answer'**
  String get unlockAnswerTooltip;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @processingZip.
  ///
  /// In en, this message translates to:
  /// **'Processing ZIP...'**
  String get processingZip;

  /// No description provided for @processingMedia.
  ///
  /// In en, this message translates to:
  /// **'Adding files, please wait...'**
  String get processingMedia;

  /// No description provided for @importingProject.
  ///
  /// In en, this message translates to:
  /// **'Importing project...'**
  String get importingProject;

  /// No description provided for @projectImported.
  ///
  /// In en, this message translates to:
  /// **'Project imported!'**
  String get projectImported;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Import error'**
  String get importError;

  /// No description provided for @headerInfo.
  ///
  /// In en, this message translates to:
  /// **'Report information'**
  String get headerInfo;

  /// No description provided for @productType.
  ///
  /// In en, this message translates to:
  /// **'Product type'**
  String get productType;

  /// No description provided for @factory.
  ///
  /// In en, this message translates to:
  /// **'Factory'**
  String get factory;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @editHeader.
  ///
  /// In en, this message translates to:
  /// **'Edit header'**
  String get editHeader;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get deletePhoto;

  /// No description provided for @noPhoto.
  ///
  /// In en, this message translates to:
  /// **'No photo'**
  String get noPhoto;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @fillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get fillAllFields;

  /// No description provided for @videoCompressionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to compress video'**
  String get videoCompressionFailed;

  /// No description provided for @videoCompressionIneffective.
  ///
  /// In en, this message translates to:
  /// **'Compression did not reduce video size'**
  String get videoCompressionIneffective;

  /// No description provided for @videoUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload video'**
  String get videoUploadFailed;

  /// No description provided for @ffmpegTrafficWarning.
  ///
  /// In en, this message translates to:
  /// **'Video is being compressed in the browser. First use downloads ~25 MB.'**
  String get ffmpegTrafficWarning;

  /// No description provided for @importProject.
  ///
  /// In en, this message translates to:
  /// **'Import project'**
  String get importProject;

  /// No description provided for @newReportTooltip.
  ///
  /// In en, this message translates to:
  /// **'New report'**
  String get newReportTooltip;

  /// No description provided for @noSavedReports.
  ///
  /// In en, this message translates to:
  /// **'No saved reports'**
  String get noSavedReports;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login/Register'**
  String get loginButton;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginTitle;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @serverSettings.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverSettings;

  /// No description provided for @serverLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address (host:port)'**
  String get serverLabel;

  /// No description provided for @connectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get connectionOk;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionFailed;

  /// No description provided for @loginAction.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginAction;

  /// No description provided for @registerAction.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerAction;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @loginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Login successful'**
  String get loginSuccess;

  /// No description provided for @loginError.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginError;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerTitle;

  /// No description provided for @logoutAction.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutAction;

  /// No description provided for @syncToCloud.
  ///
  /// In en, this message translates to:
  /// **'Sync to cloud'**
  String get syncToCloud;

  /// No description provided for @syncingProgress.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncingProgress;

  /// No description provided for @syncCompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get syncCompleteMessage;

  /// No description provided for @syncErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncErrorMessage;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @mediaQualitySection.
  ///
  /// In en, this message translates to:
  /// **'Media quality'**
  String get mediaQualitySection;

  /// No description provided for @mediaImageQuality.
  ///
  /// In en, this message translates to:
  /// **'Image quality'**
  String get mediaImageQuality;

  /// No description provided for @mediaImageQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High — 2000px / Q85'**
  String get mediaImageQualityHigh;

  /// No description provided for @mediaImageQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium — 1500px / Q85'**
  String get mediaImageQualityMedium;

  /// No description provided for @mediaImageQualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low — 1080px / Q80'**
  String get mediaImageQualityLow;

  /// No description provided for @mediaVideoQuality.
  ///
  /// In en, this message translates to:
  /// **'Video quality'**
  String get mediaVideoQuality;

  /// No description provided for @mediaVideoQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High — Full HD (less compression)'**
  String get mediaVideoQualityHigh;

  /// No description provided for @mediaVideoQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium — HD (balanced)'**
  String get mediaVideoQualityMedium;

  /// No description provided for @mediaVideoQualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low — 480p (max compression, default)'**
  String get mediaVideoQualityLow;

  /// No description provided for @attachmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Attached files'**
  String get attachmentsTitle;

  /// No description provided for @attachmentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files uploaded'**
  String get attachmentsEmpty;

  /// No description provided for @attachmentsAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add new file'**
  String get attachmentsAddNew;

  /// No description provided for @attachmentsAddHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a file (up to 55 MB)'**
  String get attachmentsAddHint;

  /// No description provided for @attachmentsTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File is larger than 55 MB — please choose a smaller file'**
  String get attachmentsTooLarge;

  /// No description provided for @attachmentsUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload file to server'**
  String get attachmentsUploadFailed;

  /// No description provided for @attachmentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get attachmentsDeleted;

  /// No description provided for @attachmentsOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open file'**
  String get attachmentsOpenFailed;

  /// No description provided for @attachmentsNote.
  ///
  /// In en, this message translates to:
  /// **'When uploading photos or videos, they are saved on the server without compression. Maximum file size is 55 MB. For photos and videos, it is recommended to use the alternative method of adding.'**
  String get attachmentsNote;

  /// No description provided for @attachmentsForQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question files'**
  String get attachmentsForQuestion;

  /// No description provided for @deleteAttachmentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get deleteAttachmentTooltip;

  /// No description provided for @fileMenuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get fileMenuDelete;

  /// No description provided for @mediaQualityMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Media quality selection'**
  String get mediaQualityMenuItem;

  /// No description provided for @starsBackground.
  ///
  /// In en, this message translates to:
  /// **'Stars background'**
  String get starsBackground;

  /// No description provided for @uploadToServer.
  ///
  /// In en, this message translates to:
  /// **'Upload to server'**
  String get uploadToServer;

  /// No description provided for @uploadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Uploading files...'**
  String get uploadingFiles;

  /// No description provided for @uploadCompleteAll.
  ///
  /// In en, this message translates to:
  /// **'All files uploaded successfully'**
  String get uploadCompleteAll;

  /// No description provided for @uploadCompletePartial.
  ///
  /// In en, this message translates to:
  /// **'Upload complete: {count}/{total} files'**
  String uploadCompletePartial(int count, int total);

  /// No description provided for @uploadError.
  ///
  /// In en, this message translates to:
  /// **'Upload error'**
  String get uploadError;

  /// No description provided for @noFilesToUpload.
  ///
  /// In en, this message translates to:
  /// **'No files to upload'**
  String get noFilesToUpload;

  /// No description provided for @loginRequired.
  ///
  /// In en, this message translates to:
  /// **'Please login first'**
  String get loginRequired;

  /// No description provided for @createShareLink.
  ///
  /// In en, this message translates to:
  /// **'Create share link'**
  String get createShareLink;

  /// No description provided for @shareLinkCreated.
  ///
  /// In en, this message translates to:
  /// **'Share link created'**
  String get shareLinkCreated;

  /// No description provided for @shareLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get shareLinkLabel;

  /// No description provided for @shareLinkExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in'**
  String get shareLinkExpiresIn;

  /// No description provided for @sharePermissionEdit.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get sharePermissionEdit;

  /// No description provided for @sharePermissionView.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get sharePermissionView;

  /// No description provided for @shareLinkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shareLinkCopy;

  /// No description provided for @shareLinkClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get shareLinkClose;

  /// No description provided for @shareLinkDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get shareLinkDays;

  /// No description provided for @shareLinkSaveFirst.
  ///
  /// In en, this message translates to:
  /// **'Save the report to the server first'**
  String get shareLinkSaveFirst;

  /// No description provided for @shareLinkError.
  ///
  /// In en, this message translates to:
  /// **'Failed to create share link'**
  String get shareLinkError;

  /// No description provided for @shareAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get shareAccess;

  /// No description provided for @shareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get shareLinkCopied;

  /// No description provided for @templateSourceFile.
  ///
  /// In en, this message translates to:
  /// **'Excel (.xlsx), JSON, ZIP'**
  String get templateSourceFile;

  /// No description provided for @templateSourceFileDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload template file'**
  String get templateSourceFileDesc;

  /// No description provided for @templateSourceJson.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON'**
  String get templateSourceJson;

  /// No description provided for @templateSourceJsonDesc.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON code manually'**
  String get templateSourceJsonDesc;

  /// No description provided for @templateDownloadSample.
  ///
  /// In en, this message translates to:
  /// **'Download sample'**
  String get templateDownloadSample;

  /// No description provided for @templateDownloadSampleDesc.
  ///
  /// In en, this message translates to:
  /// **'Sample JSON template'**
  String get templateDownloadSampleDesc;

  /// No description provided for @jsonTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON template'**
  String get jsonTemplateTitle;

  /// No description provided for @jsonTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'questions: [...], availableLanguages: [...]'**
  String get jsonTemplateHint;

  /// No description provided for @loadJsonButton.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get loadJsonButton;

  /// No description provided for @jsonParseError.
  ///
  /// In en, this message translates to:
  /// **'JSON parse error'**
  String get jsonParseError;

  /// No description provided for @templateSampleSaved.
  ///
  /// In en, this message translates to:
  /// **'Sample saved: {path}'**
  String templateSampleSaved(String path);

  /// No description provided for @templateSaveError.
  ///
  /// In en, this message translates to:
  /// **'Save error: {error}'**
  String templateSaveError(String error);

  /// No description provided for @takePhotoCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhotoCamera;

  /// No description provided for @takePhotoCameraDesc.
  ///
  /// In en, this message translates to:
  /// **'Take photo with camera'**
  String get takePhotoCameraDesc;

  /// No description provided for @photoFromGalleryHeader.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get photoFromGalleryHeader;

  /// No description provided for @photoFromGalleryHeaderDesc.
  ///
  /// In en, this message translates to:
  /// **'Load existing photo'**
  String get photoFromGalleryHeaderDesc;

  /// No description provided for @compressVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Compress Video'**
  String get compressVideoTitle;

  /// No description provided for @highQuality.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get highQuality;

  /// No description provided for @highQualityDesc.
  ///
  /// In en, this message translates to:
  /// **'Less compression, better quality'**
  String get highQualityDesc;

  /// No description provided for @mediumQuality.
  ///
  /// In en, this message translates to:
  /// **'Medium quality'**
  String get mediumQuality;

  /// No description provided for @mediumQualityDesc.
  ///
  /// In en, this message translates to:
  /// **'Balanced compression'**
  String get mediumQualityDesc;

  /// No description provided for @lowQuality.
  ///
  /// In en, this message translates to:
  /// **'Low quality'**
  String get lowQuality;

  /// No description provided for @lowQualityDesc.
  ///
  /// In en, this message translates to:
  /// **'Maximum compression'**
  String get lowQualityDesc;

  /// No description provided for @compressingVideo.
  ///
  /// In en, this message translates to:
  /// **'Compressing video...'**
  String get compressingVideo;

  /// No description provided for @noVideoToCompress.
  ///
  /// In en, this message translates to:
  /// **'No video to compress or all already compressed'**
  String get noVideoToCompress;

  /// No description provided for @compressionComplete.
  ///
  /// In en, this message translates to:
  /// **'Compression complete'**
  String get compressionComplete;

  /// No description provided for @compressedVideoCount.
  ///
  /// In en, this message translates to:
  /// **'Compressed videos: {count}'**
  String compressedVideoCount(int count);

  /// No description provided for @compressionError.
  ///
  /// In en, this message translates to:
  /// **'Compression error: {error}'**
  String compressionError(String error);

  /// No description provided for @reportIdMissing.
  ///
  /// In en, this message translates to:
  /// **'Report ID is missing'**
  String get reportIdMissing;

  /// No description provided for @shareTokenMissing.
  ///
  /// In en, this message translates to:
  /// **'Share link token is missing'**
  String get shareTokenMissing;

  /// No description provided for @reportNumber.
  ///
  /// In en, this message translates to:
  /// **'Report #{id}'**
  String reportNumber(String id);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @htmlWebOnly.
  ///
  /// In en, this message translates to:
  /// **'HTML viewing is only available in the web version.'**
  String get htmlWebOnly;

  /// No description provided for @loadReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load report'**
  String get loadReportFailed;

  /// No description provided for @loadLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load link'**
  String get loadLinkFailed;

  /// No description provided for @reportFromLinkLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load report from link'**
  String get reportFromLinkLoadFailed;

  /// No description provided for @htmlOpenedInNewTab.
  ///
  /// In en, this message translates to:
  /// **'HTML report opened in a new tab'**
  String get htmlOpenedInNewTab;

  /// No description provided for @invalidFileFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format'**
  String get invalidFileFormat;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File is too large (max 10MB)'**
  String get fileTooLarge;

  /// No description provided for @photoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo added'**
  String get photoAdded;

  /// No description provided for @errorWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetail(String error);

  /// No description provided for @openHtmlTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open HTML'**
  String get openHtmlTooltip;

  /// No description provided for @deleteMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get deleteMediaTitle;

  /// No description provided for @deleteMediaConfirm.
  ///
  /// In en, this message translates to:
  /// **'The file will be deleted permanently.'**
  String get deleteMediaConfirm;

  /// No description provided for @compressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing...'**
  String get compressing;

  /// No description provided for @finalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing...'**
  String get finalizing;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploading;

  /// No description provided for @enterCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter username and password'**
  String get enterCredentials;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get registerFailed;

  /// No description provided for @langCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'The language_code field must be a non-empty string'**
  String get langCodeRequired;

  /// No description provided for @questionsMustBeArray.
  ///
  /// In en, this message translates to:
  /// **'The questions field must be an array'**
  String get questionsMustBeArray;

  /// No description provided for @questionsCountMismatch.
  ///
  /// In en, this message translates to:
  /// **'Must be {expected} questions, got {actual}'**
  String questionsCountMismatch(int expected, int actual);

  /// No description provided for @questionMustBeObject.
  ///
  /// In en, this message translates to:
  /// **'Question {index} must be an object'**
  String questionMustBeObject(int index);

  /// No description provided for @questionIdMustBeNumber.
  ///
  /// In en, this message translates to:
  /// **'Question {index}: id field must be a number'**
  String questionIdMustBeNumber(int index);

  /// No description provided for @questionNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Question {index}: name field must be a non-empty string'**
  String questionNameRequired(int index);

  /// No description provided for @questionDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Question {index}: description field must be a non-empty string'**
  String questionDescriptionRequired(int index);

  /// No description provided for @unsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file format: .{ext}\nSupported: .xlsx, .json, .zip'**
  String unsupportedFormat(String ext);

  /// No description provided for @excelMinRows.
  ///
  /// In en, this message translates to:
  /// **'Excel file must contain at least 3 rows: header, language codes and questions'**
  String get excelMinRows;

  /// No description provided for @excelNoQuestions.
  ///
  /// In en, this message translates to:
  /// **'No questions found in Excel file. Make sure questions start from row 3.'**
  String get excelNoQuestions;

  /// No description provided for @excelReadError.
  ///
  /// In en, this message translates to:
  /// **'Error reading Excel file: {error}'**
  String excelReadError(String error);

  /// No description provided for @jsonReadError.
  ///
  /// In en, this message translates to:
  /// **'Error reading JSON file: {error}'**
  String jsonReadError(String error);

  /// No description provided for @invalidJsonDetail.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON: {message}'**
  String invalidJsonDetail(String message);

  /// No description provided for @jsonParseDetail.
  ///
  /// In en, this message translates to:
  /// **'JSON parsing error: {error}'**
  String jsonParseDetail(String error);

  /// No description provided for @jsonNoQuestions.
  ///
  /// In en, this message translates to:
  /// **'JSON does not contain questions (the \"questions\" field is missing or empty)'**
  String get jsonNoQuestions;

  /// No description provided for @jsonNoValidQuestions.
  ///
  /// In en, this message translates to:
  /// **'No valid questions found in JSON. Each question must contain \"localizations\"'**
  String get jsonNoValidQuestions;

  /// No description provided for @jsonStructureError.
  ///
  /// In en, this message translates to:
  /// **'JSON structure error: {error}'**
  String jsonStructureError(String error);

  /// No description provided for @zipNoJson.
  ///
  /// In en, this message translates to:
  /// **'No JSON file with the report found in the ZIP archive. Expected report.json or another .json file'**
  String get zipNoJson;

  /// No description provided for @zipReadError.
  ///
  /// In en, this message translates to:
  /// **'Error reading ZIP archive: {error}'**
  String zipReadError(String error);

  /// No description provided for @sharedReport.
  ///
  /// In en, this message translates to:
  /// **'Shared Report'**
  String get sharedReport;

  /// No description provided for @editAccess.
  ///
  /// In en, this message translates to:
  /// **'Edit access'**
  String get editAccess;

  /// No description provided for @viewOnlyAccess.
  ///
  /// In en, this message translates to:
  /// **'View only access'**
  String get viewOnlyAccess;

  /// No description provided for @linkValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Link valid until'**
  String get linkValidUntil;

  /// No description provided for @downloadApp.
  ///
  /// In en, this message translates to:
  /// **'Download App'**
  String get downloadApp;

  /// No description provided for @downloadAppDesc.
  ///
  /// In en, this message translates to:
  /// **'For Android or Windows'**
  String get downloadAppDesc;

  /// No description provided for @openWebEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get openWebEditor;

  /// No description provided for @openWebEditorDesc.
  ///
  /// In en, this message translates to:
  /// **'To edit the report'**
  String get openWebEditorDesc;

  /// No description provided for @openHtmlDesc.
  ///
  /// In en, this message translates to:
  /// **'To view in browser'**
  String get openHtmlDesc;

  /// No description provided for @downloadZipDesc.
  ///
  /// In en, this message translates to:
  /// **'Report with media for offline use'**
  String get downloadZipDesc;

  /// No description provided for @appLinksStub.
  ///
  /// In en, this message translates to:
  /// **'App download links will be here'**
  String get appLinksStub;

  /// No description provided for @viewOnlyWarning.
  ///
  /// In en, this message translates to:
  /// **'View only access. To edit, request access from the report owner.'**
  String get viewOnlyWarning;

  /// No description provided for @downloadZip.
  ///
  /// In en, this message translates to:
  /// **'Download ZIP'**
  String get downloadZip;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @statusError.
  ///
  /// In en, this message translates to:
  /// **'Error {statusCode}'**
  String statusError(int statusCode);

  /// No description provided for @invalidServerResponse.
  ///
  /// In en, this message translates to:
  /// **'Invalid server response: {statusCode}'**
  String invalidServerResponse(int statusCode);

  /// No description provided for @noServerConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection to server'**
  String get noServerConnection;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error: {error}'**
  String networkError(String error);

  /// No description provided for @uploadErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Upload error: {error}'**
  String uploadErrorDetail(String error);

  /// No description provided for @uploadNoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload any file'**
  String get uploadNoneFailed;

  /// No description provided for @uploadFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Upload failed ({status})'**
  String uploadFailedStatus(int status);

  /// No description provided for @uploadFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Upload error'**
  String get uploadFailedGeneric;

  /// No description provided for @uploadTimeout.
  ///
  /// In en, this message translates to:
  /// **'Upload timeout'**
  String get uploadTimeout;

  /// No description provided for @presignFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create upload link'**
  String get presignFailed;

  /// No description provided for @confirmFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to confirm upload'**
  String get confirmFailed;

  /// No description provided for @versionConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Report changed'**
  String get versionConflictTitle;

  /// No description provided for @versionConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'The report was modified on another device (version {version}). Reload to see the latest version, or overwrite with your changes.'**
  String versionConflictMessage(String version);

  /// No description provided for @versionConflictReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get versionConflictReload;

  /// No description provided for @versionConflictOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get versionConflictOverwrite;

  /// No description provided for @answerConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Answer conflict'**
  String get answerConflictTitle;

  /// No description provided for @answerConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'Another user has changed this same answer. Choose what to do: accept their version, replace it with yours, or keep both answers.'**
  String get answerConflictMessage;

  /// No description provided for @answerConflictServerAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer on server'**
  String get answerConflictServerAnswer;

  /// No description provided for @answerConflictYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get answerConflictYourAnswer;

  /// No description provided for @answerConflictUseServer.
  ///
  /// In en, this message translates to:
  /// **'Use server answer'**
  String get answerConflictUseServer;

  /// No description provided for @answerConflictReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace with mine'**
  String get answerConflictReplace;

  /// No description provided for @answerConflictSaveAsSecond.
  ///
  /// In en, this message translates to:
  /// **'Save as second answer'**
  String get answerConflictSaveAsSecond;

  /// No description provided for @downloadReport.
  ///
  /// In en, this message translates to:
  /// **'Download Report'**
  String get downloadReport;

  /// No description provided for @downloadReportPrompt.
  ///
  /// In en, this message translates to:
  /// **'Do you want to download this report?'**
  String get downloadReportPrompt;

  /// No description provided for @openReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open report'**
  String get openReportFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
