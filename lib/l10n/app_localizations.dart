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
  /// **'Exit'**
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

  /// No description provided for @createNewReport.
  ///
  /// In en, this message translates to:
  /// **'+ Create New Report'**
  String get createNewReport;

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
  /// **'Enter description...'**
  String get enterDecryption;

  /// No description provided for @questions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get questions;

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
  /// **'Edit description'**
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
