import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import './providers/report_provider.dart';
import './providers/settings_provider.dart';
import './providers/locale_provider.dart';
import './utils/app_colors.dart';
import './providers/auth_provider.dart';
import './l10n/app_localizations.dart';
import './screens/template_select_screen.dart';
import './screens/form_fill_screen.dart';
import './screens/reports_screen.dart';
import './screens/view_report_html_screen.dart';
import './screens/share_welcome_screen.dart';
import './screens/login_screen.dart' show showLoginDialog, showSettingsDialog;
import './widgets/dotted_background.dart';
import './widgets/easy_tab_button.dart';

void main() async {
  // P3: runZonedGuarded перехватывает необработанные async-ошибки,
  // предотвращая тихое падение приложения.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

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
              '/template': (context) => const TemplateSelectScreen(),
              '/fill': (context) => const FormFillScreen(),
              '/reports': (context) => const ReportsScreen(),
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
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Не указан ID отчёта')),
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) =>
                      ViewReportHtmlScreen(publicId: publicId, token: token),
                );
              }
              if (uri.path == '/welcome') {
                final token = uri.queryParameters['token'];
                if (token == null || token.isEmpty) {
                  return MaterialPageRoute(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Не указан токен ссылки')),
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => ShareWelcomeScreen(token: token),
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

  /// Загружает версию приложения из version.json, сгенерированного Flutter при сборке.
  /// Добавляем cache-busting, чтобы браузер не показывал старую версию после обновления.
  Future<String?> _loadVersion() async {
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
    return Scaffold(
      body: Stack(
        children: [
          const DottedBackground(),
          Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(40),
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
                    verticalPadding: 18,
                    horizontalPadding: 20,
                  ),
                  const SizedBox(height: 15),
                  EasyTabButton(
                    label: loc.continueReport,
                    onTap: () => _continueLastReport(context),
                    fontSize: 18,
                    verticalPadding: 18,
                    horizontalPadding: 20,
                  ),
                  const SizedBox(height: 15),
                  EasyTabButton(
                    label: loc.yourReports,
                    onTap: () => Navigator.pushNamed(context, '/reports'),
                    fontSize: 18,
                    verticalPadding: 18,
                    horizontalPadding: 20,
                  ),
                  const SizedBox(height: 15),
                  if (!authProvider.isLoggedIn)
                    EasyTabButton(
                      label: loc.loginButton,
                      onTap: () => showLoginDialog(context),
                      fontSize: 18,
                      verticalPadding: 18,
                      horizontalPadding: 20,
                    )
                  else
                    EasyTabButton(
                      label: loc.logoutAction,
                      onTap: () => authProvider.logout(),
                      fontSize: 18,
                      verticalPadding: 18,
                      horizontalPadding: 20,
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
    Navigator.of(context).pushNamed('/fill');
  }
}
