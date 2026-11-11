import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/core/theme/floating_bar.dart';

Widget app({bool calm = false, bool screenReader = false, EdgeInsets padding = const EdgeInsets.only(top: 30, bottom: 24), EdgeInsets insets = EdgeInsets.zero}) =>
    GetMaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          disableAnimations: calm,
          accessibleNavigation: screenReader,
          padding: padding,
          viewPadding: padding,
          viewInsets: insets,
        ),
        child: child!,
      ),
      home: const Scaffold(body: SizedBox.expand()),
    );

Future<void> elapse(WidgetTester t, int ms) async {
  for (var i = 0; i < ms; i += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

double gapBelow(WidgetTester t) {
  final screen = t.view.physicalSize / t.view.devicePixelRatio;
  return screen.height - t.getRect(find.byType(Dismissible)).bottom;
}

void main() {
  setUp(() => FloatingBarPresence.shown = false);

  group('a message', () {
    testWidgets('shows, stays about 4 seconds and goes', (t) async {
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(find.text('Copied.'), findsOneWidget);
      await elapse(t, 4500);
      await t.pump();
      expect(find.text('Copied.'), findsNothing);
    });

    testWidgets('a new one replaces the one on screen', (t) async {
      await t.pumpWidget(app());
      AppToast.show('First.');
      await elapse(t, 400);
      AppToast.show('Second.');
      await elapse(t, 400);
      expect(find.text('First.'), findsNothing);
      expect(find.text('Second.'), findsOneWidget);
      await elapse(t, 6000);
    });

    testWidgets('swiping it sideways dismisses it', (t) async {
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      await t.drag(find.text('Copied.'), const Offset(500, 0));
      await t.pumpAndSettle();
      expect(find.text('Copied.'), findsNothing);
      await elapse(t, 6000);
    });

    testWidgets('has no time line, since there is nothing to undo', (t) async {
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(find.byType(FractionallySizedBox), findsNothing);
      await elapse(t, 6000);
    });
  });

  group('a message with a button', () {
    testWidgets('shows the time left as a line that shrinks', (t) async {
      await t.pumpWidget(app());
      AppToast.show('Merged two people.', actionLabel: 'Undo', onAction: () {}, duration: const Duration(seconds: 8));
      await elapse(t, 500);
      final full = t.getSize(find.byType(FractionallySizedBox)).width;
      await elapse(t, 4000);
      final half = t.getSize(find.byType(FractionallySizedBox)).width;
      expect(half, lessThan(full * 0.6));
      expect(half, greaterThan(full * 0.4));
      await elapse(t, 6000);
    });

    testWidgets('a tap calls the action once and takes the message away', (t) async {
      await t.pumpWidget(app());
      var undone = 0;
      AppToast.show('Merged two people.', actionLabel: 'Undo', onAction: () => undone++, duration: const Duration(seconds: 8));
      await elapse(t, 500);
      await t.tap(find.text('Undo'));
      await t.pump();
      expect(undone, 1);
      expect(find.text('Merged two people.'), findsNothing);
      await elapse(t, 10000);
      expect(undone, 1);
    });

    testWidgets('when the time runs out it goes and the action is not called', (t) async {
      await t.pumpWidget(app());
      var undone = 0;
      AppToast.show('Merged two people.', actionLabel: 'Undo', onAction: () => undone++, duration: const Duration(seconds: 8));
      await elapse(t, 9500);
      await t.pump();
      expect(find.text('Merged two people.'), findsNothing);
      expect(undone, 0);
    });

    testWidgets('stays twice as long when a screen reader is on', (t) async {
      await t.pumpWidget(app(screenReader: true));
      AppToast.show('Merged two people.', actionLabel: 'Undo', duration: const Duration(seconds: 8));
      await elapse(t, 10500);
      expect(find.text('Merged two people.'), findsOneWidget);
      await elapse(t, 7500);
      await t.pump();
      expect(find.text('Merged two people.'), findsNothing);
    });
  });

  group('with Remove animations', () {
    testWidgets('appears at once with no line, and goes at once', (t) async {
      await t.pumpWidget(app(calm: true));
      AppToast.show('Merged two people.', actionLabel: 'Undo', duration: const Duration(seconds: 8));
      await t.pump();
      expect(find.text('Merged two people.'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
      await elapse(t, 8300);
      await t.pump();
      await t.pump();
      expect(find.text('Merged two people.'), findsNothing);
    });
  });

  group('where it sits', () {
    testWidgets('above the floating bar on the home screen', (t) async {
      FloatingBarPresence.shown = true;
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(gapBelow(t), closeTo(24 + kFloatingBarBottomGap + kFloatingBarHeight + 32, 0.5));
      await elapse(t, 6000);
    });

    testWidgets('near the bottom on a screen pushed over home, and above the bar again once it closes', (t) async {
      FloatingBarPresence.shown = true;
      await t.pumpWidget(app());
      final nav = Get.key.currentState!;
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox.expand())));
      await t.pumpAndSettle();
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(gapBelow(t), closeTo(24 + 24, 0.5));
      await elapse(t, 6000);
      nav.pop();
      await t.pumpAndSettle();
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(gapBelow(t), closeTo(24 + kFloatingBarBottomGap + kFloatingBarHeight + 32, 0.5));
      await elapse(t, 6000);
    });

    testWidgets('near the bottom when there is no floating bar, as on the tour', (t) async {
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(gapBelow(t), closeTo(24 + 24, 0.5));
      await elapse(t, 6000);
    });

    testWidgets('just above the keyboard when it is up', (t) async {
      FloatingBarPresence.shown = true;
      await t.pumpWidget(app(insets: const EdgeInsets.only(bottom: 300)));
      AppToast.show('Copied.');
      await elapse(t, 500);
      expect(gapBelow(t), closeTo(316, 0.5));
      await elapse(t, 6000);
    });

    testWidgets('a readable width, in the middle, on a wide screen', (t) async {
      t.view.physicalSize = const Size(1600, 2560);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      AppToast.show('Copied.');
      await elapse(t, 500);
      final r = t.getRect(find.byType(Dismissible));
      expect(r.width, closeTo(520, 0.5));
      expect(r.center.dx, closeTo(400, 0.5));
      await elapse(t, 6000);
    });

    testWidgets('a long message wraps inside a narrow screen with large text', (t) async {
      t.view.physicalSize = const Size(640, 1136);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(GetMaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ));
      AppToast.show('Saved A very long collection name that goes on and on as a collection.', actionLabel: 'View');
      await elapse(t, 500);
      expect(t.takeException(), isNull);
      final r = t.getRect(find.byType(Dismissible));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320));
      await elapse(t, 9000);
    });
  });

  testWidgets('taken out of the tree while showing leaves nothing running', (t) async {
    await t.pumpWidget(app());
    AppToast.show('Copied.', actionLabel: 'View');
    await elapse(t, 500);
    await t.pumpWidget(const SizedBox());
  });
}
