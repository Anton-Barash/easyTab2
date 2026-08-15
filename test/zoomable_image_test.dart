import 'package:easy_tab/widgets/zoomable_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TransformationController _controllerOf(WidgetTester tester) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  return viewer.transformationController!;
}

double _scaleOf(WidgetTester tester) =>
    _controllerOf(tester).value.getMaxScaleOnAxis();

Future<void> _doubleTap(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(ZoomableImage));
  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(center);
  await tester.pumpAndSettle();
}

void main() {
  Widget buildSubject({ValueChanged<bool>? onZoomChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: ZoomableImage(
            onZoomChanged: onZoomChanged,
            child: Container(width: 400, height: 400, color: Colors.red),
          ),
        ),
      ),
    );
  }

  testWidgets('starts at scale 1.0', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(_scaleOf(tester), 1.0);
  });

  testWidgets('double tap zooms in and notifies', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(buildSubject(onZoomChanged: events.add));

    await _doubleTap(tester);

    expect(_scaleOf(tester), greaterThan(1.0));
    expect(events, [true]);
  });

  testWidgets('second double tap resets zoom', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(buildSubject(onZoomChanged: events.add));

    await _doubleTap(tester);
    await _doubleTap(tester);

    expect(_scaleOf(tester), 1.0);
    expect(events, [true, false]);
  });
}
