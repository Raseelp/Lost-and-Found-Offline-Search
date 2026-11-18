import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';

/// The time left that the Library shows is the one the scan reports, and only while it is running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IndexedFolder progress({int processed = 3100, int total = 4000, Object? etaMs = 180000}) => IndexedFolder.fromMap({
    'id': '__device_scan__',
    'path': '',
    'done': false,
    'total': total,
    'processed': processed,
    'embedded': 100,
    'skipped': 3000,
    'elapsedMs': 20000,
    'etaMs': etaMs,
  });

  test('is what the scan reports, not worked out from the items done', () {
    // 3,100 of 4,000 items are done after 20 seconds, but 3,000 of them were skipped as already indexed.
    final controller = LibraryController()
      ..isScanning = true
      ..scanResult = progress();

    expect(controller.scanEtaMs, 180000);
  });

  test('is unknown while the scan cannot say yet', () {
    final controller = LibraryController()
      ..isScanning = true
      ..scanResult = progress(etaMs: -1);
    expect(controller.scanEtaMs, isNull);

    controller.scanResult = progress(etaMs: null);
    expect(controller.scanEtaMs, isNull);
  });

  test('is unknown when nothing is running, or nothing is left', () {
    final controller = LibraryController()..scanResult = progress();
    expect(controller.scanEtaMs, isNull);

    controller
      ..isScanning = true
      ..scanResult = progress(processed: 4000);
    expect(controller.scanEtaMs, isNull);
  });
}
