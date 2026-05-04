import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tab/main.dart';

void main() {
  testWidgets('App loads StartScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyTabApp());
    expect(find.text('EasyTab'), findsOneWidget);
  });
}
