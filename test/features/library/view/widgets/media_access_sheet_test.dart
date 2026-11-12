import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/library/view/widgets/media_access_sheet.dart';

void main() {
  bool? answer;

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    answer = null;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => answer = await showMediaAccessSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('says why the access is needed and what happens to the media', (tester) async {
    await open(tester);

    expect(find.text('Enable media access'), findsOneWidget);
    expect(find.textContaining('To make your media searchable offline'), findsOneWidget);
    expect(find.textContaining('store it right on your device.', findRichText: true), findsOneWidget);
    expect(find.text('Your media never leaves this device.'), findsOneWidget);
    expect(find.textContaining('The entire app works offline'), findsOneWidget);
    expect(find.textContaining('airplane mode'), findsOneWidget);
  });

  testWidgets('Continue answers yes', (tester) async {
    await open(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect(find.text('Enable media access'), findsNothing);
  });

  testWidgets('Not now answers no', (tester) async {
    await open(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('tapping outside the sheet answers no', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
    expect(find.text('Enable media access'), findsNothing);
  });

  testWidgets('fits a small phone at double text size, and the buttons can be reached', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, textScale: 2);

    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
