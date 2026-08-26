import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import './providers/report_provider.dart';
import './providers/settings_provider.dart';
import './providers/locale_provider.dart';
import './utils/app_colors.dart';
import './providers/auth_provider.dart';
import './l10n/app_localizations.dart';
import './l10n/app_localizations_en.dart';
import './l10n/app_localizations_ru.dart';
import './l10n/app_localizations_zh.dart';
import './services/share_token_storage.dart';
import './screens/login_screen.dart' show showLoginDialog, showSettingsDialog;
import './widgets/dotted_background.dart';
import './widgets/easy_tab_button.dart';
// Тяжёлые экраны загружаются лениво (deferred) — они не нужны на стартовой
// странице и тянут Excel/Sync/Video-сервисы в бандл. Каждый экран станет
// отдельным чанком, загружаемым при первом переходе на него.
import './screens/template_select_screen.dart'
    deferred as template_select_screen;
import './screens/form_fill_screen.dart' deferred as form_fill_screen;
import './screens/reports_screen.dart' deferred as reports_screen;
import './screens/view_report_html_screen.dart'
    deferred as view_report_html_screen;
import './screens/share_welcome_screen.dart'
    deferred as share_welcome_screen;

/// Универсальный экран загрузки для deferred-частей приложения.
Widget _deferredLoading(BuildContext context) {
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void main() async {
  // P3: runZonedGuarded перехватывает необработанные async-ошибки,
  // предотвращая тихое падение приложения.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Явно создаём экземпляры всех локализаций, чтобы dart2js при сборке
      // web не tree-shake'нул классы AppLocalizationsEn/Ru/Zh. Без этого
      // переключение языка на en/zh в рантайме показывает русский текст,
      // т.к. нерусские локализации вырезаются как "мёртвый код".
      // ignore: unused_local_variable
      final l10nKeepAlive = <AppLocalizations>[
        AppLocalizationsEn(),
        AppLocalizationsRu(),
        AppLocalizationsZh(),
      ];

      // Перехват ошибок Flutter-фреймворка (build, layout и т.д.)
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exception}\n${details.stack}');
      };

      final localeProvider = LocaleProvider();
      await localeProvider.init();
      final authProvider = AuthProvider();
      await authProvider.init();
      final settingsProvider = SettingsState();
      await settingsProvider.init();
      runApp(
        EasyTabApp(
          localeProvider: localeProvider,
          authProvider: authProvider,
          settingsProvider: settingsProvider,
        ),
      );
    },
    (error, stackTrace) {
      debugPrint('Unhandled async error: $error\n$stackTrace');
    },
  );
}

class EasyTabApp extends StatelessWidget {
  final LocaleProvider localeProvider;
  final AuthProvider authProvider;
  final SettingsState settingsProvider;
  const EasyTabApp({
    super.key,
    required this.localeProvider,
    required this.authProvider,
    required this.settingsProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReportState()),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: authProvider),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
            title: 'EasyTab',
            debugShowCheckedModeBanner: false,
            locale: localeProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ru'), Locale('zh')],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
              useMaterial3: true,
            ),
            initialRoute: '/',
            routes: {
              '/': (context) => const StartScreen(),
              '/template': (context) => FutureBuilder<void>(
                    future: template_select_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return template_select_screen.TemplateSelectScreen();
                    },
                  ),

              '/reports': (context) => FutureBuilder<void>(
                    future: reports_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return reports_screen.ReportsScreen();
                    },
                  ),
            },
            // /view-report — открывается в новой вкладке браузера с
            // query-параметрами: /view-report?pid=abc123&token=xxx
            // /welcome — приветственный экран share-ссылки: /welcome?token=abc123
            // Используем onGenerateRoute, т.к. routes не парсит query.
            onGenerateRoute: (settings) {
              if (settings.name == null) return null;
              final uri = Uri.parse(settings.name!);
              if (uri.path == '/view-report') {
                final publicId = uri.queryParameters['pid'];
                final token = uri.queryParameters['token'];
                if (publicId == null || publicId.isEmpty) {
                  return MaterialPageRoute(
                    builder: (ctx) => Scaffold(
                      body: Center(
                        child: Text(AppLocalizations.of(ctx)!.reportIdMissing),
                      ),
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => FutureBuilder<void>(
                    future: view_report_html_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return view_report_html_screen.ViewReportHtmlScreen(
                        publicId: publicId,
                        token: token,
                      );
                    },
                  ),
                );
              }
              // /fill — редактор отчёта. Поддерживает query-параметр reportId,
              // чтобы при перезагрузке страницы открывался тот же отчёт:
              // /#/fill?reportId=123
              if (uri.path == '/fill') {
                final reportId = uri.queryParameters['reportId'];
                return MaterialPageRoute(
                  builder: (_) => FutureBuilder<void>(
                    future: form_fill_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return form_fill_screen.FormFillScreen(
                        reportId: reportId,
                      );
                    },
                  ),
                );
              }
              // /share-edit — переход во Flutter-редактор с HTML-welcome
              // страницы (кнопка «Открыть веб-версию»): /share-edit?token=abc.
              // Сразу открывает редактор отчёта, минуя welcome-экран с кнопками.
              if (uri.path == '/share-edit') {
                final token = uri.queryParameters['token'];
                if (token == null || token.isEmpty) {
                  return MaterialPageRoute(
                    builder: (ctx) => Scaffold(
                      body: Center(
                        child: Text(AppLocalizations.of(ctx)!.shareTokenMissing),
                      ),
                    ),
                  );
                }
                // Сохраняем токен, чтобы расшаренный отчёт появился в списке.
                ShareTokenStorage.addToken(token);
                return MaterialPageRoute(
                  builder: (_) => FutureBuilder<void>(
                    future: form_fill_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return form_fill_screen.FormFillScreen(shareToken: token);
                    },
                  ),
                );
              }
              if (uri.path == '/welcome') {
                final token = uri.queryParameters['token'];
                if (token == null || token.isEmpty) {
                  return MaterialPageRoute(
                    builder: (ctx) => Scaffold(
                      body: Center(
                        child:
                            Text(AppLocalizations.of(ctx)!.shareTokenMissing),
                      ),
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => FutureBuilder<void>(
                    future: share_welcome_screen.loadLibrary(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return _deferredLoading(context);
                      }
                      return share_welcome_screen.ShareWelcomeScreen(
                        token: token,
                      );
                    },
                  ),
                );
              }
              return null;
            },
          );
        },
      ),
    );
  }
}

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late Future<String?> _versionFuture;

  @override
  void initState() {
    super.initState();
    _versionFuture = _loadVersion();
  }

  /// Загружает версию приложения.
  /// Web: из version.json (cache-busting для браузера).
  /// Native: из PackageInfo (Android/iOS).
  Future<String?> _loadVersion() async {
    if (!kIsWeb) {
      // Android / iOS / Desktop
      try {
        final info = await PackageInfo.fromPlatform();
        return info.version;
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to load native version: $e');
      }
      return null;
    }

    // Web only
    try {
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.base.resolve('version.json?v=$cacheBuster');
      final response = await http.get(
        uri,
        headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['version'] as String?;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load version: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    // Адаптивность под узкий экран (мобильный телефон): уменьшаем отступы,
    // чтобы карточка не вылезала за границы видимой области.
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    final cardMargin = isNarrow ? 12.0 : 20.0;
    final cardPadding = isNarrow ? 24.0 : 40.0;
    final btnVertical = isNarrow ? 14.0 : 18.0;
    final btnHorizontal = isNarrow ? 16.0 : 20.0;
    return Scaffold(
      body: Stack(
        children: [
          const DottedBackground(),
          SafeArea(
            // SingleChildScrollView: на низких экранах карточка скроллится
            // вместо переполнения (BOTTOM OVERFLOWED).
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: EdgeInsets.all(cardMargin),
                  padding: EdgeInsets.all(cardPadding),
                  constraints: const BoxConstraints(maxWidth: 500),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(width: 2, color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Language switcher + settings gear at top right
                      Align(
                        alignment: Alignment.topRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (authProvider.isLoggedIn)
                              IconButton(
                                icon: const Icon(Icons.settings, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => showSettingsDialog(context),
                                tooltip: loc.settingsTitle,
                              ),
                            if (authProvider.isLoggedIn) const SizedBox(width: 8),
                            _buildLanguageSwitcher(context, localeProvider, loc),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'easyTab',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 30),
                      EasyTabButton(
                        label: loc.createNewReport,
                        onTap: () => Navigator.pushNamed(context, '/template'),
                        fontSize: 18,
                        verticalPadding: btnVertical,
                        horizontalPadding: btnHorizontal,
                      ),
                      const SizedBox(height: 15),
                      EasyTabButton(
                        label: loc.continueReport,
                        onTap: () => _continueLastReport(context),
                        fontSize: 18,
                        verticalPadding: btnVertical,
                        horizontalPadding: btnHorizontal,
                      ),
                      const SizedBox(height: 15),
                      EasyTabButton(
                        label: loc.yourReports,
                        onTap: () => Navigator.pushNamed(context, '/reports'),
                        fontSize: 18,
                        verticalPadding: btnVertical,
                        horizontalPadding: btnHorizontal,
                      ),
                      const SizedBox(height: 15),
                      if (!authProvider.isLoggedIn)
                        EasyTabButton(
                          label: loc.loginButton,
                          onTap: () => showLoginDialog(context),
                          fontSize: 18,
                          verticalPadding: btnVertical,
                          horizontalPadding: btnHorizontal,
                        )
                      else
                        EasyTabButton(
                          label: loc.logoutAction,
                          onTap: () => authProvider.logout(),
                          fontSize: 18,
                          verticalPadding: btnVertical,
                          horizontalPadding: btnHorizontal,
                        ),
                      const SizedBox(height: 30),
                      Text(
                        loc.instructionsText,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<String?>(
                        future: _versionFuture,
                        builder: (context, snapshot) {
                          final version = snapshot.data;
                          if (version == null || version.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            'v$version',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSwitcher(
    BuildContext context,
    LocaleProvider localeProvider,
    AppLocalizations loc,
  ) {
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language, size: 24),
      onSelected: (locale) {
        localeProvider.setLocale(locale);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: const Locale('en'),
          child: Row(
            children: [
              Text(loc.english),
              if (localeProvider.locale.languageCode == 'en')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        ),
        PopupMenuItem(
          value: const Locale('ru'),
          child: Row(
            children: [
              Text(loc.russian),
              if (localeProvider.locale.languageCode == 'ru')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        ),
        PopupMenuItem(
          value: const Locale('zh'),
          child: Row(
            children: [
              Text(loc.chinese),
              if (localeProvider.locale.languageCode == 'zh')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _continueLastReport(BuildContext context) async {
    final reportState = Provider.of<ReportState>(context, listen: false);
    final reports = await reportState.loadReportList();

    if (!context.mounted) return;

    if (reports.isEmpty) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.noSavedReports)));
      return;
    }

    reports.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final lastReport = reports.first;

    await reportState.loadReport(lastReport.folderName);
    if (!context.mounted) return;
    final reportId = reportState.serverReportId;
    Navigator.of(context).pushNamed(
      reportId != null ? '/fill?reportId=$reportId' : '/fill',
    );
  }
}
