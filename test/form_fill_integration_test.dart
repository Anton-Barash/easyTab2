import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/auth_provider.dart';
import 'package:easy_tab/providers/locale_provider.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/providers/settings_provider.dart';
import 'package:easy_tab/screens/form_fill_screen.dart';
import 'package:easy_tab/widgets/form_fill/header_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group('FormFillScreen integration', () {
    ReportState createReportState() {
      final state = ReportState();
      state.newReport(
        'Test Report',
        [
          Question(
            id: 1,
            localizations: {
              'RU': QuestionLocalization(
                name: 'Question 1',
                description: 'First question description',
              ),
            },
          ),
          Question(
            id: 2,
            localizations: {
              'RU': QuestionLocalization(
                name: 'Question 2',
                description: 'Second question description',
              ),
            },
          ),
        ],
        ['RU'],
        productType: 'Airfryer',
        factory: 'Factory A',
        model: 'Model X',
      );
      return state;
    }

    Future<void> prepareScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildTestApp(ReportState reportState) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ReportState>.value(value: reportState),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => SettingsState()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('ru'), Locale('zh')],
          locale: Locale('ru'),
          home: FormFillScreen(),
        ),
      );
    }

    testWidgets('renders header and questions in list view', (tester) async {
      await prepareScreen(tester);
      final reportState = createReportState();
      await tester.pumpWidget(buildTestApp(reportState));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(HeaderListTile),
          matching: find.text('Airfryer | Factory A | Model X'),
        ),
        findsOneWidget,
      );
      final mainList = find.byType(ScrollablePositionedList).first;
      expect(
        find.descendant(of: mainList, matching: find.text('Question 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mainList, matching: find.text('Question 2')),
        findsOneWidget,
      );
    });

    testWidgets('switches to card view and shows header card', (tester) async {
      await prepareScreen(tester);
      final reportState = createReportState();
      await tester.pumpWidget(buildTestApp(reportState));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();

      expect(find.byType(HeaderListTile), findsOneWidget);
      expect(find.text('Airfryer | Factory A | Model X'), findsWidgets);
    });

    testWidgets('opens header edit dialog', (tester) async {
      await prepareScreen(tester);
      final reportState = createReportState();
      await tester.pumpWidget(buildTestApp(reportState));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(HeaderListTile),
          matching: find.byIcon(Icons.edit),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Airfryer'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Сохранить'), findsOneWidget);
    });
  });
}
