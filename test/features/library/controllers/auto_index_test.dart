import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
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

  group('LibraryController.autoIndexed', () {
    /// Answers takeAutoShown with what [batches] holds, one for each call.
    void shown(List<Map<String, dynamic>> batches) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'takeAutoShown') {
          return batches.isEmpty ? {'photos': 0, 'videos': 0, 'items': []} : batches.removeAt(0);
        }
        return null;
      });
    }

    Map<String, dynamic> batch(int photos, int videos, List<String> uris) => {
      'photos': photos,
      'videos': videos,
      'items': [for (final uri in uris) {'uri': uri, 'video': false}],
    };

    test('holds what was indexed, and adds to it while the app stays open', () async {
      final controller = LibraryController();
      shown([
        batch(2, 0, ['content://a', 'content://b']),
        batch(1, 1, ['content://c', 'content://d']),
      ]);

      await controller.refreshLatestScan();
      expect(controller.autoIndexed.count, 2);

      await controller.refreshLatestScan();
      expect(controller.autoIndexed.photos, 3);
      expect(controller.autoIndexed.videos, 1);
      expect(controller.autoIndexed.items.map((i) => i.uri), ['content://c', 'content://d', 'content://a', 'content://b']);
    });

    test('keeps it when there is nothing more', () async {
      final controller = LibraryController();
      shown([batch(1, 0, ['content://a'])]);
      await controller.refreshLatestScan();
      await controller.refreshLatestScan();

      expect(controller.autoIndexed.count, 1);
    });

    test('keeps only the newest few pictures, and all of the count', () async {
      final controller = LibraryController();
      shown([
        batch(30, 0, [for (var i = 0; i < 24; i++) 'content://old$i']),
        batch(5, 0, [for (var i = 0; i < 5; i++) 'content://new$i']),
      ]);
      await controller.refreshLatestScan();
      await controller.refreshLatestScan();

      expect(controller.autoIndexed.count, 35);
      expect(controller.autoIndexed.items, hasLength(24));
      expect(controller.autoIndexed.items.first.uri, 'content://new0');
    });

    test('shows nothing when nothing was indexed', () async {
      final controller = LibraryController();
      shown([]);
      await controller.refreshLatestScan();

      expect(controller.autoIndexed.count, 0);
    });

    test('starts empty in a new visit', () {
      expect(LibraryController().autoIndexed.count, 0);
      expect(const AutoIndexedBatch().items, isEmpty);
    });
  });

  group('LibraryController.checkForInterruptedScan', () {
    const marker = {'folderId': '__device_scan__', 'uri': '', 'mode': 'device', 'contentMode': 'both'};

    void know({Map<String, dynamic>? last, bool withMarker = true}) {
      SharedPreferences.setMockInitialValues({if (withMarker) 'interrupted_scan': jsonEncode(marker)});
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'lastScanProgress') return last;
        return null;
      });
    }

    Map<String, dynamic> progress({required int processed, required bool done}) => {
      'id': '__device_scan__',
      'path': '',
      'done': done,
      'total': 5000,
      'processed': processed,
      'embedded': processed,
      'skipped': 0,
      'failed': 0,
      'elapsedMs': 1000,
      'activeMs': 900,
    };

    test('shows a scan cut short as paused where it got to, and keeps it to resume', () async {
      know(last: progress(processed: 1200, done: false));
      final controller = LibraryController();

      await controller.checkForInterruptedScan();

      expect(controller.isScanning, isFalse);
      expect(controller.interruptedScan, isNotNull);
      expect(controller.scanResult.total, 5000);
      expect(controller.scanResult.processed, 1200);
    });

    test('a scan that ended while the app was away is not offered again', () async {
      know(last: progress(processed: 5000, done: true));
      final controller = LibraryController();

      await controller.checkForInterruptedScan();

      expect(controller.interruptedScan, isNull);
      expect(controller.scanResult.processed, 5000);
      expect((await SharedPreferences.getInstance()).getString('interrupted_scan'), isNull);
    });

    test('offers the resume when nothing is known about how far it got', () async {
      know();
      final controller = LibraryController();

      await controller.checkForInterruptedScan();

      expect(controller.interruptedScan, isNotNull);
      expect(controller.scanResult.total, 0);
    });

    test('a scan that failed while the app was away is not offered again', () async {
      know(last: {'id': '__device_scan__', 'path': '', 'done': true, 'total': 0, 'processed': 0});
      final controller = LibraryController();

      await controller.checkForInterruptedScan();

      expect(controller.interruptedScan, isNull);
      expect((await SharedPreferences.getInstance()).getString('interrupted_scan'), isNull);
    });

    test('a folder scan leaves One folder as the choice, a phone scan Whole phone', () async {
      SharedPreferences.setMockInitialValues({
        'interrupted_scan': jsonEncode({'folderId': 'tree', 'uri': 'content://tree', 'mode': 'folder', 'contentMode': 'both'}),
      });
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final folder = LibraryController();
      await folder.checkForInterruptedScan();
      expect(folder.scanWholePhone, isFalse);

      know();
      final phone = LibraryController()..scanWholePhone = false;
      await phone.checkForInterruptedScan();
      expect(phone.scanWholePhone, isTrue);
    });

    test('does nothing when no scan was interrupted', () async {
      know(last: progress(processed: 5000, done: true), withMarker: false);
      final controller = LibraryController();

      await controller.checkForInterruptedScan();

      expect(controller.interruptedScan, isNull);
      expect(controller.scanResult.total, 0);
    });

    test('does nothing while a scan is running', () async {
      know(last: progress(processed: 10, done: false));
      final controller = LibraryController()..isScanning = true;

      await controller.checkForInterruptedScan();

      expect(controller.interruptedScan, isNull);
    });
  });

  group('LibraryController.toggleSelectedContentMode', () {
    test('is the choice of the manual scan only and does not reach auto indexing', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final controller = LibraryController();

      controller.toggleSelectedContentMode(contentMode: ContentMode.videos);
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedContentMode, ContentMode.videos);
      expect(calls.where((c) => c.contains('AutoIndex')), isEmpty);
    });
  });
}
