import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/settings/view/auto_index_content.dart';

/// The choice under the switch of auto indexing.
void main() {
  Future<void> show(WidgetTester tester, {String value = 'both', ValueChanged<String>? onChanged, double width = 360, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: AutoIndexContentChoice(value: value, onChanged: onChanged ?? (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers both, photos and videos, with the current one selected', (tester) async {
    await show(tester, value: 'images');
    expect(find.text('Both'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    final buttons = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(buttons.selected, {'images'});
  });

  testWidgets('tells which choice was made', (tester) async {
    final chosen = <String>[];
    await show(tester, onChanged: chosen.add);
    await tester.tap(find.text('Videos'));
    await tester.tap(find.text('Photos'));
    expect(chosen, ['videos', 'images']);
  });

  testWidgets('says in one short line what it is for', (tester) async {
    await show(tester);
    expect(find.text('What auto indexing picks up.'), findsOneWidget);
  });

  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at $width wide and text size ${scale}x', (tester) async {
        await show(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
