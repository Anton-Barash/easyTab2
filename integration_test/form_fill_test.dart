import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/screens/form_fill_screen.dart';
import 'package:easy_tab/widgets/form_fill/header_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('FormFillScreen end-to-end', () {
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

    Widget buildTestApp(ReportState reportState) {
      return ChangeNotifierProvider<ReportState>.value(
        value: reportState,
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
      final reportState = createReportState();
      await tester.pumpWidget(buildTestApp(reportState));
      await tester.pumpAndSettle();

      expect(find.text('Airfryer | Factory A | Model X'), findsOneWidget);
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Question 2'), findsOneWidget);
    });

    testWidgets('switches to card view and shows header card', (tester) async {
      final reportState = createReportState();
      await tester.pumpWidget(buildTestApp(reportState));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();

      expect(find.byType(HeaderListTile), findsOneWidget);
      expect(find.text('Airfryer | Factory A | Model X'), findsWidgets);
    });

    testWidgets('opens header edit dialog', (tester) async {
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
      expect(find.text('Отмена'), findsOneWidget);
    });
  });
}
