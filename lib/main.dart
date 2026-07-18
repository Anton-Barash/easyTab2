import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import './providers/report_provider.dart';
import './providers/settings_provider.dart';
import './providers/locale_provider.dart';
import './providers/auth_provider.dart';
import './l10n/app_localizations.dart';
import './screens/template_select_screen.dart';
import './screens/form_fill_screen.dart';
import './screens/reports_screen.dart';
import './screens/login_screen.dart' show showLoginDialog, showSettingsDialog;
import './widgets/dotted_pattern_painter.dart';
import './widgets/easy_tab_button.dart';

void main() async {
  // P3: runZonedGuarded перехватывает необработанные async-ошибки,
  // предотвращая тихое падение приложения.
  runZonedGuarded(() async {
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
    runApp(EasyTabApp(
      localeProvider: localeProvider,
      authProvider: authProvider,
      settingsProvider: settingsProvider,
    ));
  }, (error, stackTrace) {
    debugPrint('Unhandled async error: $error\n$stackTrace');
  });
}

class EasyTabApp extends StatelessWidget {
  final LocaleProvider localeProvider;
  final AuthProvider authProvider;
  final SettingsState settingsProvider;
  const EasyTabApp({super.key, required this.localeProvider, required this.authProvider, required this.settingsProvider});

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
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2563eb),
              ),
              useMaterial3: true,
            ),
            initialRoute: '/',
            routes: {
              '/': (context) => const StartScreen(),
              '/template': (context) => const TemplateSelectScreen(),
              '/fill': (context) => FormFillScreen(),
              '/reports': (context) => ReportsScreen(),
            },
          );
        },
      ),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFf8f7f2),
              child: CustomPaint(painter: DottedPatternPainter()),
            ),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(40),
              constraints: const BoxConstraints(maxWidth: 500),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(width: 2, color: const Color(0xFF333333)),
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
                    style: TextStyle(fontSize: 16, color: Color(0xFF424242)),
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
                    ),
                  const SizedBox(height: 30),
                  Text(
                    loc.instructionsText,
                    style: const TextStyle(
                      color: Color(0xFF424242),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'v1.0.15',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 10),
                    textAlign: TextAlign.center,
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
    
    if (reports.isEmpty) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.noSavedReports)),
      );
      return;
    }
    
    reports.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final lastReport = reports.first;
    
    await reportState.loadReport(lastReport.folderName);
    Navigator.of(context).pushNamed('/fill');
  }
}
