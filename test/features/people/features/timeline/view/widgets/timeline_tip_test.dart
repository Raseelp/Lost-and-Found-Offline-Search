import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_tip.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _title = 'Good to know';

/// A page with a button that asks for the tip, so the dialog is opened the way the screen opens it.
Widget _app({bool motionOff = false, double textScale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: motionOff,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showTimelineTipOnce(context),
            child: const Text('Open timeline'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the tip shows on the first visit, with its words and one button', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_title), findsOneWidget);
    expect(find.textContaining('This page shows when the people in your photos appeared'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('Got it closes it, and it does not come back on the next visit', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_title), findsNothing);

    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_title), findsNothing);
  });

  testWidgets('a tip that was already seen is not shown', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_title), findsNothing);
  });

  testWidgets('closing it by tapping outside counts as seen too', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_title), findsNothing);

    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_title), findsNothing);
  });

  testWidgets('the animation loops, and stands still when the phone asks for no animations', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(motionOff: true));
    await tester.tap(find.text('Open timeline'));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('asking twice at the same moment shows one tip', (tester) async {
    await tester.pumpWidget(_app());
    final context = tester.element(find.text('Open timeline'));
    final first = showTimelineTipOnce(context);
    final second = showTimelineTipOnce(context);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_title), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    await Future.wait([first, second]);
  });

  testWidgets('a screen that is already gone does not use the tip up', (tester) async {
    late BuildContext gone;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (home) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(home).push(
              MaterialPageRoute<void>(
                builder: (page) {
                  gone = page;
                  return const Scaffold(body: Text('page'));
                },
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    Navigator.of(gone).pop();
    await tester.pumpAndSettle();

    await tester.runAsync(() => showTimelineTipOnce(gone));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('timeline_tip_seen'), isNull);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('a small phone with the largest text still reaches the button, with nothing overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(textScale: 2));
    await tester.tap(find.text('Open timeline'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Got it'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_title), findsNothing);
  });
}
