import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Library tab takes from new photos and videos that were indexed by themselves: the items to tag as new, the
/// time for "Last scanned", and the choice of photos, videos or both that the native side follows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Answers the three calls of [LibraryController.refreshLatestScan] and nothing else.
  void answer({
    List<String> scan = const [],
    List<String> auto = const [],
    int at = 0,
  }) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'takeLatestScan':
          return scan;
        case 'takeAutoIndexed':
          return auto;
        case 'autoIndexedAt':
          return at;
      }
      return null;
    });
  }

  group('LibraryController.refreshLatestScan', () {
    test(
      'adds what indexing by itself stored to what is tagged as new',
      () async {
        final controller = LibraryController();
        answer(scan: ['content://a', 'content://b']);
        await controller.refreshLatestScan();

        answer(auto: ['content://c']);
        await controller.refreshLatestScan();

        expect(controller.latestScanUris, {
          'content://a',
          'content://b',
          'content://c',
        });
      },
    );

    test(
      'a scan that ended replaces the tags held, the ones from indexing by itself included',
      () async {
        final controller = LibraryController();
        answer(auto: ['content://old']);
        await controller.refreshLatestScan();

        answer(scan: ['content://scanned']);
        await controller.refreshLatestScan();

        expect(controller.latestScanUris, {'content://scanned'});
      },
    );

    test('keeps the tags when there is nothing new to take', () async {
      final controller = LibraryController();
      answer(auto: ['content://a']);
      await controller.refreshLatestScan();

      answer();
      await controller.refreshLatestScan();

      expect(controller.latestScanUris, {'content://a'});
    });

    test('reads the time indexing by itself last stored something', () async {
      final controller = LibraryController();
      expect(controller.autoIndexedAtMs, 0);

      answer(at: 1700000000000);
      await controller.refreshLatestScan();

      expect(controller.autoIndexedAtMs, 1700000000000);
    });

    test('carries on when the native side does not know the calls', () async {
      final controller = LibraryController();
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException();
      });

      await controller.refreshLatestScan();

      expect(controller.latestScanUris, isEmpty);
      expect(controller.autoIndexedAtMs, 0);
    });
  });

  group('LibraryController.toggleSelectedContentMode', () {
    test('tells the native side what to index', () async {
      SharedPreferences.setMockInitialValues({});
      final modes = <String?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setAutoIndexContent') {
          modes.add((call.arguments as Map)['mode'] as String?);
        }
        return null;
      });
      final controller = LibraryController();

      controller.toggleSelectedContentMode(contentMode: ContentMode.images);
      controller.toggleSelectedContentMode(contentMode: ContentMode.videos);
      controller.toggleSelectedContentMode(contentMode: ContentMode.both);
      await Future<void>.delayed(Duration.zero);

      expect(modes, ['images', 'videos', 'both']);
    });
  });
}
