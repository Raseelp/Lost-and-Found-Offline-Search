import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/view/widget/library_orbit.dart';

// Stopping a scan takes a few seconds (the work in hand is finished first). The app shows
// "Stopping" straight away and ignores further taps until the scan has ended.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('NativeController.stopScanning', () {
    test(
      'shows stopping at once and sends one cancel for repeated taps',
      () async {
        var cancels = 0;
        final reply = Completer<bool>();
        messenger.setMockMethodCallHandler(channel, (call) {
          if (call.method == 'cancelEmbedding') {
            cancels++;
            return reply.future;
          }
          return null;
        });
        final controller = NativeController()..isScanning = true;

        final first = controller.stopScanning();
        expect(
          controller.isStopping,
          isTrue,
          reason: 'set before the native side answers',
        );

        await controller.stopScanning();
        await controller.stopScanning();
        reply.complete(true);
        await first;

        expect(cancels, 1);
        expect(
          controller.isStopping,
          isTrue,
          reason: 'stays until the scan ends',
        );
      },
    );

    test('does nothing when no scan is running', () async {
      var cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancelEmbedding') cancels++;
        return true;
      });
      final controller = NativeController();

      await controller.stopScanning();

      expect(cancels, 0);
      expect(controller.isStopping, isFalse);
    });

    test('offers the button again when the stop could not be sent', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR');
      });
      final controller = NativeController()..isScanning = true;

      await controller.stopScanning();

      expect(controller.isStopping, isFalse);
    });
  });

  group('OrbitPill', () {
    Future<int> pump(WidgetTester tester, {required bool busy}) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OrbitPill(
                label: busy ? 'Stopping…' : 'Stop indexing',
                icon: Icons.stop_rounded,
                busy: busy,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(OrbitPill));
      await tester.pump();
      return taps;
    }

    testWidgets('busy shows a spinner instead of the icon and ignores taps', (
      tester,
    ) async {
      final taps = await pump(tester, busy: true);
      expect(find.text('Stopping…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      expect(taps, 0);
    });

    testWidgets('not busy shows the icon and taps go through', (tester) async {
      final taps = await pump(tester, busy: false);
      expect(find.text('Stop indexing'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(taps, 1);
    });
  });
}
