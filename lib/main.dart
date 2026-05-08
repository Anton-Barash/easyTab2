import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import './providers/report_provider.dart';
import './providers/settings_provider.dart';
import './providers/locale_provider.dart';
import './l10n/app_localizations.dart';
import './screens/template_select_screen.dart';
import './screens/form_fill_screen.dart';
import './screens/reports_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeProvider = LocaleProvider();
  await localeProvider.init();
  runApp(EasyTabApp(localeProvider: localeProvider));
}

class EasyTabApp extends StatelessWidget {
  final LocaleProvider localeProvider;
  const EasyTabApp({super.key, required this.localeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReportState()),
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider.value(value: localeProvider),
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
                  // Language switcher at top right
                  Align(
                    alignment: Alignment.topRight,
                    child: _buildLanguageSwitcher(context, localeProvider, loc),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Excel Report Builder',
                    style: TextStyle(fontSize: 16, color: Color(0xFF424242)),
                  ),
                  const SizedBox(height: 30),
                  _buildButton(
                    label: loc.createNewReport,
                    onTap: () => Navigator.pushNamed(context, '/template'),
                  ),
                  const SizedBox(height: 15),
                  _buildButton(
                    label: loc.openExistingReport,
                    onTap: () => _openExistingReport(context, loc),
                  ),
                  const SizedBox(height: 15),
                  _buildButton(
                    label: loc.yourReports,
                    onTap: () => Navigator.pushNamed(context, '/reports'),
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
                    'v1.0.6',
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

  Widget _buildButton({required String label, required VoidCallback onTap}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFe0e0e0),
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
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xFF424242),
                shadows: [
                  Shadow(
                    color: Color.fromRGBO(66, 66, 66, 0.45),
                    blurRadius: 1.2,
                  ),
                  Shadow(
                    color: Color.fromRGBO(255, 255, 255, 0.9),
                    blurRadius: 0.8,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openExistingReport(
    BuildContext context,
    AppLocalizations loc,
  ) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.comingSoon)));
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
