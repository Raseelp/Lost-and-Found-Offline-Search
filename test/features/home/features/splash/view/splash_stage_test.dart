import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/home/features/splash/view/splash_overlay.dart';

Widget host(Widget child, {bool calm = false}) => MediaQuery(
      data: MediaQueryData(size: const Size(360, 780), devicePixelRatio: 2, disableAnimations: calm),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

Future<void> run(WidgetTester t, int ms) async {
  for (var i = 0; i < ms; i += 16) {
    splashNowMsForTest += 16;
    await t.pump(const Duration(milliseconds: 16));
  }
}

int splashNowMsForTest = 0;

void main() {
  setUp(() {
    splashNowMsForTest = 0;
    splashNowMs = () => splashNowMsForTest;
    SplashGate.released.value = false;
  });

  testWidgets('releases the app at the hold point, plays on, and finishes once', (t) async {
    var done = 0;
    await t.pumpWidget(host(SplashStage(ready: true, onDone: () => done++)));
    expect(SplashGate.released.value, isFalse);
    await run(t, 300);
    expect(SplashGate.released.value, isFalse);
    await run(t, 200);
    expect(SplashGate.released.value, isTrue);
    expect(done, 0);
    await run(t, 6000);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('waits at the start while the app is not ready, then goes on when it is', (t) async {
    var done = 0;
    Widget w(bool ready) => host(SplashStage(ready: ready, onDone: () => done++));
    await t.pumpWidget(w(false));
    await run(t, 3000);
    expect(done, 0);
    expect(SplashGate.released.value, isTrue);
    await t.pumpWidget(w(true));
    await run(t, 5000);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('goes on after 6 seconds even if the app never gets ready', (t) async {
    var done = 0;
    await t.pumpWidget(host(SplashStage(ready: false, onDone: () => done++)));
    await run(t, 5000);
    expect(done, 0);
    await run(t, 6000);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tap during the wait finishes it, once, even with a second tap', (t) async {
    var done = 0;
    await t.pumpWidget(host(SplashStage(ready: true, onDone: () => done++)));
    await run(t, 100);
    await t.tapAt(const Offset(100, 100));
    await t.tapAt(const Offset(100, 100));
    await run(t, 1000);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tap while the lens is moving finishes it, once', (t) async {
    var done = 0;
    await t.pumpWidget(host(SplashStage(ready: true, onDone: () => done++)));
    await run(t, 2200);
    await t.tapAt(const Offset(100, 100));
    await t.tapAt(const Offset(100, 100));
    await run(t, 4000);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with Remove animations it shows a still picture and is then taken away at once', (t) async {
    var done = 0;
    await t.pumpWidget(host(SplashStage(ready: true, onDone: () => done++), calm: true));
    await t.pump();
    expect(SplashGate.released.value, isTrue);
    await run(t, 400);
    expect(done, 0);
    await run(t, 300);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with Remove animations it stays until the app is ready', (t) async {
    var done = 0;
    Widget w(bool ready) => host(SplashStage(ready: ready, onDone: () => done++), calm: true);
    await t.pumpWidget(w(false));
    await run(t, 2000);
    expect(done, 0);
    await t.pumpWidget(w(true));
    await run(t, 100);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('taken out of the tree in the middle of any phase leaves no timer or ticker running', (t) async {
    for (final at in [50, 450, 900, 1800, 2600, 3500]) {
      SplashGate.released.value = false;
      await t.pumpWidget(host(SplashStage(ready: true, onDone: () {})));
      await run(t, at);
      await t.pumpWidget(const SizedBox());
    }
  });
}
