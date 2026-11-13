import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
import 'package:lost_and_found/features/viewer/view/image_full_screen.dart';
import 'package:lost_and_found/features/viewer/view/video_full_screen.dart';
import 'package:lost_and_found/features/search/view/widgets/auto_indexed_card.dart';

/// The card under the search bar that tells about photos and videos indexed by themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// A 1x1 picture, which is all a thumbnail has to be here.
  final Uint8List pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadThumbnail') return pixel;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  AutoIndexedBatch batch(int photos, int videos, {int items = 24}) => AutoIndexedBatch(
    photos: photos,
    videos: videos,
    items: [
      for (var i = 0; i < items; i++) (uri: 'content://media/$i', video: i % 4 == 3),
    ],
  );

  group('AutoIndexedCard.sentence', () {
    test('says what was indexed, with the right plurals', () {
      expect(AutoIndexedCard.sentence(batch(1, 0)), '1 new photo is ready to search.');
      expect(AutoIndexedCard.sentence(batch(0, 1)), '1 new video is ready to search.');
      expect(AutoIndexedCard.sentence(batch(3, 0)), '3 new photos are ready to search.');
      expect(AutoIndexedCard.sentence(batch(0, 2)), '2 new videos are ready to search.');
      expect(AutoIndexedCard.sentence(batch(12, 2)), '12 new photos and 2 videos are ready to search.');
      expect(AutoIndexedCard.sentence(batch(1, 1)), '1 new photo and 1 video are ready to search.');
    });

    test('puts commas in big numbers', () {
      expect(AutoIndexedCard.sentence(batch(1234, 0)), '1,234 new photos are ready to search.');
      expect(AutoIndexedCard.sentence(batch(1000000, 0)), '1,000,000 new photos are ready to search.');
    });
  });

  group('AutoIndexedCard layout', () {
    Future<void> show(WidgetTester tester, AutoIndexedBatch batch, {double width = 360, double scale = 1, List<NavigatorObserver> observers = const []}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: observers,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(child: AutoIndexedCard(batch: batch)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final width in [320.0, 360.0, 411.0, 800.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at $width wide and text size ${scale}x', (tester) async {
          await show(tester, batch(1234, 56), width: width, scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('shows how many more there are on the last picture', (tester) async {
      await show(tester, batch(30, 0));
      expect(find.text('+25'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(5));
    });

    testWidgets('shows no count when everything is shown', (tester) async {
      await show(tester, batch(3, 0, items: 3));
      expect(find.textContaining('+'), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('keeps a slot grey when its picture cannot be read', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'ERROR'));
      await show(tester, batch(2, 0, items: 2));
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.text('2 new photos are ready to search.'), findsOneWidget);
    });

    testWidgets('a narrow phone shows fewer pictures, each big enough to tap', (tester) async {
      await show(tester, batch(30, 0), width: 320);
      final tiles = find.byType(Image);
      expect(tiles, findsNWidgets(4));
      for (final tile in tiles.evaluate()) {
        final size = tester.getSize(find.byWidget(tile.widget));
        expect(size.width, greaterThanOrEqualTo(48), reason: '$size');
      }
      expect(find.text('+26'), findsOneWidget);
    });

    testWidgets('a tap on a photo opens it in the viewer', (tester) async {
      final observer = _PushedRoutes();
      await show(tester, batch(3, 0, items: 3), observers: [observer]);
      await tester.tap(find.byType(Image).first);

      expect(observer.pushed, hasLength(1));
      final route = observer.pushed.single as PageRouteBuilder;
      final viewer = route.pageBuilder(tester.element(find.byType(AutoIndexedCard)), const AlwaysStoppedAnimation(1), const AlwaysStoppedAnimation(1));
      expect(viewer, isA<ImageViewScreen>());
      expect((viewer as ImageViewScreen).uri, 'content://media/0');
      expect(viewer.loadFullRes, isTrue);
    });

    testWidgets('a tap on a video opens the video viewer', (tester) async {
      final observer = _PushedRoutes();
      await show(tester, batch(0, 1, items: 1).copy(video: true), observers: [observer]);
      await tester.tap(find.byType(Image).first);

      final route = observer.pushed.single as PageRouteBuilder;
      final viewer = route.pageBuilder(tester.element(find.byType(AutoIndexedCard)), const AlwaysStoppedAnimation(1), const AlwaysStoppedAnimation(1));
      expect(viewer, isA<VideoViewScreen>());
    });

    testWidgets('a tap before the picture has loaded does nothing', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'ERROR'));
      final observer = _PushedRoutes();
      await show(tester, batch(1, 0, items: 1), observers: [observer]);
      await tester.tapAt(tester.getCenter(find.byType(AutoIndexedCard)) + const Offset(0, 40));

      expect(observer.pushed, isEmpty);
    });

    testWidgets('has a button for each picture, named for what it opens', (tester) async {
      await show(tester, batch(3, 1, items: 4));
      expect(find.bySemanticsLabel('Open photo'), findsNWidgets(3));
      expect(find.bySemanticsLabel('Open video'), findsOneWidget);
    });

    testWidgets('does not ask again for a picture that could not be read', (tester) async {
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'loadThumbnail') {
          reads++;
          throw PlatformException(code: 'ERROR');
        }
        return null;
      });
      final items = batch(2, 0, items: 2);
      await show(tester, items);
      await show(tester, items);
      expect(reads, 2);
    });

    testWidgets('does not read a picture twice when the page is rebuilt', (tester) async {
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'loadThumbnail') {
          reads++;
          return pixel;
        }
        return null;
      });
      final items = batch(4, 0, items: 4);
      await show(tester, items);
      await show(tester, items);
      expect(reads, 4);
    });
  });
}

/// Notes the routes that are pushed, so a tap can be followed without building the screen it opens.
class _PushedRoutes extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushed.add(route);
  }
}

extension on AutoIndexedBatch {
  /// The same batch with every picture a video.
  AutoIndexedBatch copy({required bool video}) =>
      AutoIndexedBatch(photos: photos, videos: videos, items: [for (final i in items) (uri: i.uri, video: video)]);
}
