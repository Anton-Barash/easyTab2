

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import './providers/report_provider.dart';
import './providers/settings_provider.dart';
import './screens/template_select_screen.dart';
import './screens/form_fill_screen.dart';
import './screens/reports_screen.dart';

void main() {
  runApp(const EasyTabApp());
}

class EasyTabApp extends StatelessWidget {
  const EasyTabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReportState()),
        ChangeNotifierProvider(create: (_) => SettingsState()),
      ],
      child: MaterialApp(
        title: 'EasyTab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563eb)),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const StartScreen(),
          '/template': (context) => const TemplateSelectScreen(),
          '/fill': (context) => FormFillScreen(),
          '/reports': (context) => ReportsScreen(),
        },
      ),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFf8f7f2),
              child: CustomPaint(
                painter: DottedPatternPainter(),
              ),
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
                  const Text(
                    'EasyTab',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF424242),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Excel Report Builder',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF424242),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildButton(
                    label: '+ Create New Report',
                    onTap: () => Navigator.pushNamed(context, '/template'),
                  ),
                  const SizedBox(height: 15),
                  _buildButton(
                    label: 'Open Existing Report',
                    onTap: () => _openExistingReport(context),
                  ),
                  const SizedBox(height: 15),
                  _buildButton(
                    label: 'Your Reports',
                    onTap: () => Navigator.pushNamed(context, '/reports'),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Instructions: create a report, select a template,\nfill in the data and export!',
                    style: TextStyle(color: Color(0xFF424242), fontSize: 12),
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

  Future<void> _openExistingReport(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка существующих отчётов — скоро!')),
    );
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
