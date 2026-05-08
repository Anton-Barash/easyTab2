import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tab/main.dart';
import 'package:easy_tab/providers/locale_provider.dart';

void main() {
  testWidgets('App loads StartScreen', (WidgetTester tester) async {
    final localeProvider = LocaleProvider();
    await tester.pumpWidget(EasyTabApp(localeProvider: localeProvider));
    expect(find.text('EasyTab'), findsOneWidget);
  });
}