import 'package:easy_tab/l10n/app_localizations.dart';
import 'package:easy_tab/models/report_models.dart';
import 'package:easy_tab/providers/auth_provider.dart';
import 'package:easy_tab/providers/locale_provider.dart';
import 'package:easy_tab/providers/report_provider.dart';
import 'package:easy_tab/screens/form_fill_screen.dart';
import 'package:easy_tab/widgets/form_fill/header_field.dart';
import 'package:easy_tab/widgets/form_fill/header_list_tile.dart';
import 'package:easy_tab/widgets/form_fill/header_photo_picker.dart';
import 'package:easy_tab/widgets/form_fill/header_side_panel_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  ReportState createReportState({
    String productType = 'Аэрогриль',
    String factory = 'TestFactory',
    String model = 'TestModel',
    String headerImagePath = '',
  }) {
    final state = ReportState();
    state.newReport(
      'Test Report',
      <Question>[],
      <String>['RU'],
      productType: productType,
      factory: factory,
      model: model,
      headerImagePath: headerImagePath.isEmpty ? null : headerImagePath,
    );
    return state;
  }

  Widget buildTestableWidget(ReportState reportState) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ReportState>.value(value: reportState),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('ru'),
        home: FormFillScreen(),
      ),
    );
  }

  Widget buildLocalizedWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ru'),
      home: Scaffold(body: child),
    );
  }

  group('FormFillScreen header rendering', () {
    testWidgets('renders report name in app bar', (tester) async {
      final reportState = createReportState();
      await tester.pumpWidget(buildTestableWidget(reportState));
      await tester.pumpAndSettle();

      expect(find.text('Test Report'), findsOneWidget);
    });

    testWidgets('renders product type, factory and model values', (
      tester,
    ) async {
      final reportState = createReportState(
        productType: 'Airfryer',
        factory: 'Factory A',
        model: 'Model X',
      );
      await tester.pumpWidget(buildTestableWidget(reportState));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(HeaderListTile),
          matching: find.text('Airfryer | Factory A | Model X'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders add photo placeholder when no header image', (
      tester,
    ) async {
      final reportState = createReportState(headerImagePath: '');
      await tester.pumpWidget(buildTestableWidget(reportState));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_a_photo), findsOneWidget);
      expect(find.text('Добавить фото'), findsOneWidget);
    });

    testWidgets(
      'does not render add photo placeholder when header image exists',
      (tester) async {
        final reportState = createReportState(headerImagePath: 'header.jpg');
        await tester.pumpWidget(buildTestableWidget(reportState));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.add_a_photo), findsNothing);
        expect(find.text('Добавить фото'), findsNothing);
      },
    );
  });

  group('HeaderField', () {
    testWidgets('renders label and text field', (tester) async {
      final controller = TextEditingController(text: 'Test value');
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderField(label: 'Test label', controller: controller),
        ),
      );

      expect(find.text('Test label'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Test value'), findsOneWidget);
    });
  });

  group('HeaderPhotoPicker', () {
    testWidgets('renders add photo placeholder when no image', (tester) async {
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderPhotoPicker(
            hasImage: false,
            imagePath: null,
            loc: await AppLocalizations.delegate.load(const Locale('ru')),
            onImagePathChanged: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      expect(find.text('Добавить фото'), findsOneWidget);
      expect(find.text('Изменить фото'), findsNothing);
    });

    testWidgets('renders change photo button when image exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderPhotoPicker(
            hasImage: true,
            imagePath: 'header.jpg',
            loc: await AppLocalizations.delegate.load(const Locale('ru')),
            onImagePathChanged: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
      expect(find.text('Добавить фото'), findsNothing);
      expect(find.text('Изменить фото'), findsOneWidget);
    });
  });

  group('HeaderListTile', () {
    testWidgets('renders combined header line and photo placeholder', (
      tester,
    ) async {
      final reportState = createReportState(
        productType: 'Airfryer',
        factory: 'Factory A',
        model: 'Model X',
      );
      var navigateCalled = false;
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderListTile(
            report: reportState.currentReport!,
            reportState: reportState,
            onNavigateToHeader: () => navigateCalled = true,
            onEditHeader: () {},
            onPhotoAreaTap: () {},
            onViewPhoto: () {},
          ),
        ),
      );

      expect(find.text('Airfryer | Factory A | Model X'), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo), findsOneWidget);

      await tester.tap(find.text('0'));
      await tester.pump();
      expect(navigateCalled, isTrue);
    });

    testWidgets('edit icon calls onEditHeader', (tester) async {
      final reportState = createReportState(
        productType: 'Airfryer',
        factory: 'Factory A',
        model: 'Model X',
      );
      var editCalled = false;
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderListTile(
            report: reportState.currentReport!,
            reportState: reportState,
            onNavigateToHeader: () {},
            onEditHeader: () => editCalled = true,
            onPhotoAreaTap: () {},
            onViewPhoto: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      expect(editCalled, isTrue);
    });
  });

  group('HeaderSidePanelTile', () {
    testWidgets('renders combined header line and calls onTap', (tester) async {
      final report = createReportState(
        productType: 'Airfryer',
        factory: 'Factory A',
        model: 'Model X',
      ).currentReport!;
      var tapCalled = false;
      await tester.pumpWidget(
        buildLocalizedWidget(
          HeaderSidePanelTile(report: report, onTap: () => tapCalled = true),
        ),
      );

      expect(find.text('Airfryer | Factory A | Model X'), findsOneWidget);

      await tester.tap(find.text('Airfryer | Factory A | Model X'));
      expect(tapCalled, isTrue);
    });
  });
}
