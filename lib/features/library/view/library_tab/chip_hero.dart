part of '../library_tab.dart';

// TODO(raseel): The old chip hero, kept in case it comes back. The scan card replaced it (see scan_card.dart).
/*
/// The chip at the top of the page: waiting to be started, scanning, or done.
///
/// While scanning it shows indexing's progress, the photos being read and the queue of those waiting for their
/// faces. Indexing and finding faces take turns: every so many photos indexing waits while their faces are found,
/// and then the chip shows the faces lifted out of their photos and placed among the people. It is one widget for
/// all three modes, so the chip itself never moves.
class _ChipHero extends StatelessWidget {
  const _ChipHero({required this.controller});

  final LibraryController controller;

  /// The number in the "found N files so far" text that native reports through [IndexedFolder.path] while it is
  /// still walking the picked folder, before a total is known. A whole-device scan skips that phase. The number
  /// drives an animated counter, because a number that visibly ticks up reads as working far more than the same text
  /// replacing itself now and then.
  int? _foundSoFarCount(IndexedFolder scan) {
    final match = RegExp(r'\d+').firstMatch(scan.path);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  String _thumbKey(RecentEmbeddedItem item) =>
      item.isVideo ? '${item.uri}@${item.timestampMs}' : item.uri;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FacesController>()) return _body(context, null);
    return GetBuilder<FacesController>(
      builder: (faces) => _body(context, faces),
    );
  }

  Widget _body(BuildContext context, FacesController? faces) {
    final scan = controller.scanResult;
    final summary = controller.scanSummary;
    final mode = controller.isScanning
        ? ScanChipMode.scanning
        : summary != null
        ? ScanChipMode.complete
        : ScanChipMode.idle;
    final progress = scan.total == 0
        ? 0.0
        : (scan.processed / scan.total).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final faceStatus = faces?.status ?? FaceStatus();
    final findingFaces = faceStatus.running && faceStatus.batch;
    final tuning = findingFaces && faceStatus.phase == 'tune';
    final faceFraction = faceStatus.total <= 0
        ? 0.0
        : (faceStatus.processed / faceStatus.total).clamp(0.0, 1.0);
    final photos = [
      for (final item in controller.recentThumbnails)
        OrbitPhoto(
          id: _thumbKey(item),
          bytes: controller.recentThumbBytes[_thumbKey(item)],
          isVideo: item.isVideo,
          frames: item.frames,
        ),
    ];

    final semantics = switch (mode) {
      ScanChipMode.idle => 'Index phone',
      ScanChipMode.complete =>
        'Scan complete, ${summary?.indexed ?? 0} indexed. Tap to dismiss',
      ScanChipMode.scanning when controller.isStopping => 'Stopping indexing',
      ScanChipMode.scanning =>
        findingFaces
            ? (tuning
                  ? 'Optimising face search for your phone'
                  : 'Finding faces, ${faceStatus.processed} of ${faceStatus.total} photos')
            : scan.total == 0
            ? 'Preparing to index'
            : 'Indexing $percent percent, ${scan.processed} of ${scan.total}',
    };

    return SquareScanHero(
      mode: mode,
      onStart: () => startIndexing(context, controller),
      idleHint: controller.scanWholePhone
          ? 'TAP TO SCAN'
          : 'TAP TO CHOOSE A FOLDER',
      onDismiss: controller.dismissScanSummary,
      summary: summary == null
          ? null
          : ScanChipSummary(
              indexed: summary.indexed,
              failed: summary.failed,
              people: faceStatus.people,
            ),
      progress: scan.total == 0 ? null : progress,
      stats: ScanChipStats(
        indexed: scan.processed,
        total: scan.total,
        found: scan.total == 0 ? _foundSoFarCount(scan) : null,
        faceDone: faceStatus.processed,
        faceTotal: faceStatus.total,
        people: faceStatus.people,
        tuning: tuning,
        etaMs: controller.scanEtaMs,
      ),
      photos: photos,
      events: findingFaces && !tuning ? faceStatus.recentFaceEvents : const [],
      discovered: scan.total == 0 ? _foundSoFarCount(scan) : null,
      queue: controller.faceQueueCount == null
          ? null
          : OrbitQueueInfo(
              count: controller.faceQueueCount!,
              ms: controller.faceQueueMs,
              photos: controller.faceBatchPhotos,
              windowMs: controller.faceBatchMs,
              at: controller.faceQueueAt,
            ),
      loadPhoto: (uri) => MediaService()
          .loadUprightPhoto(uri)
          .then<Uint8List?>((bytes) => bytes)
          .catchError((_) => null),
      rate: controller.recentEmbeddingsPerSecond,
      faceMode: mode == ScanChipMode.scanning && findingFaces,
      faceProgress: tuning ? null : faceFraction,
      semanticsLabel: semantics,
    );
  }
}
*/

/// Starts indexing the way the Library's scan card does when its button is tapped: the whole phone (asking for the photos first if
/// need be) or a folder to choose, as "Where to look" says. Nothing happens while a scan is already running.
Future<void> startIndexing(
  BuildContext context,
  LibraryController controller,
) async {
  if (controller.isScanning) return;
  if (controller.scanWholePhone) {
    await _startDeviceScan(context, controller);
  } else {
    controller.pickAndScanFolders(isScanEntirePhone: false);
  }
}
