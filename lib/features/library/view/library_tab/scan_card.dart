part of '../library_tab.dart';

/// The card at the top of the Library page: the three steps of a scan, with their button underneath. It is always the
/// same card. Before any scan the steps wait at 0 of 0, while a scan runs they work, and after one ends, or when the app
/// is opened again, they are held where the last scan stopped, with its real numbers from the saved record of the
/// folders.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.controller});

  final LibraryController controller;

  static const _photosShown = 8;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FacesController>()) return _body(context, null);
    return GetBuilder<FacesController>(builder: (faces) => _body(context, faces));
  }

  /// The number in the "found N files so far" text that native reports through [IndexedFolder.path] while it is still
  /// walking the picked folder, before a total is known. A whole-device scan skips that phase.
  int? _foundSoFar(IndexedFolder scan) {
    final match = RegExp(r'\d+').firstMatch(scan.path);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _thumbKey(RecentEmbeddedItem item) => item.isVideo ? '${item.uri}@${item.timestampMs}' : item.uri;

  /// The scan of this run of the app, or when none has run yet the last one from the saved record of the folders.
  IndexedFolder get _lastScan {
    final scan = controller.scanResult;
    if (scan.total > 0) return scan;
    IndexedFolder? latest;
    for (final folder in controller.allIndexedFoldersList) {
      if (folder.total > 0 && folder.updatedAt > (latest?.updatedAt ?? 0)) latest = folder;
    }
    return latest ?? scan;
  }

  /// How far the faces have got through the library, from 0 to 1. While faces follow indexing they are as far as the
  /// photos are. Otherwise it is the pass the face scan reports.
  double _facesProgress(FaceStatus status, IndexedFolder scan) {
    if (status.batch || status.following) {
      return scan.total == 0 ? 0 : (scan.processed / scan.total).clamp(0.0, 1.0);
    }
    return status.total <= 0 ? 0 : (status.processed / status.total).clamp(0.0, 1.0);
  }

  Widget _body(BuildContext context, FacesController? faces) {
    final faceStatus = faces?.status ?? FaceStatus();
    final running = controller.isScanning;
    final scan = running ? controller.scanResult : _lastScan;
    final hasScan = scan.total > 0;
    final complete = hasScan && scan.processed >= scan.total;
    final live = identical(scan, controller.scanResult);
    final findingFaces = live && faceStatus.running && faceStatus.batch;
    final tuning = findingFaces && faceStatus.phase == 'tune';
    final paused = (!running && hasScan) || controller.isStopping;
    final percent = scan.total == 0 ? 0 : (scan.processed * 100 / scan.total).floor();
    final recent = !live
        ? const <String>[]
        : [
            for (final item in controller.recentThumbnails.take(_photosShown))
              if (controller.recentThumbBytes[_thumbKey(item)] != null) _thumbKey(item),
          ];
    final lastPhoto = controller.lastPhoto;
    final photoIds = recent.isEmpty && paused && lastPhoto != null ? [_thumbKey(lastPhoto)] : recent;
    final batchFaces = findingFaces && !tuning ? [for (final e in faceStatus.recentFaceEvents) e.id] : const <int>[];
    final lastFace = faces?.lastFaceId;
    final faceIds = batchFaces.isEmpty && paused && lastFace != null ? [lastFace] : batchFaces;
    final label = !hasScan && !running
        ? 'Not started'
        : paused
        ? (complete
              ? 'Indexing finished, ${scan.total} indexed'
              : controller.isStopping
              ? 'Stopping indexing, ${scan.processed} of ${scan.total}'
              : 'Indexing paused, ${scan.processed} of ${scan.total}')
        : tuning
        ? 'Preparing face search for this phone'
        : findingFaces
        ? 'Finding people, ${faceStatus.processed} of ${faceStatus.total} photos'
        : scan.total == 0
        ? 'Preparing to index'
        : 'Indexing $percent percent, ${scan.processed} of ${scan.total}';

    final steps = ScanStepsCard(
      key: const ValueKey('steps'),
      processed: scan.processed,
      total: scan.total,
      found: scan.total == 0 ? _foundSoFar(scan) : null,
      etaMs: live ? controller.scanEtaMs : null,
      photoRate: live ? controller.recentEmbeddingsPerSecond : null,
      faceRate: live ? faces?.scanRate : null,
      searchable: controller.totalEmbeddings > 0 ? controller.totalEmbeddings : scan.processed,
      people: faceStatus.people,
      faceWork: live && faceStatus.running,
      findingFaces: findingFaces,
      tuning: tuning,
      facesProgress: _facesProgress(faceStatus, scan),
      faceFraction: faceStatus.total <= 0 ? 0 : faceStatus.processed / faceStatus.total,
      batchPhotos: faceStatus.total,
      paused: paused,
      stopping: controller.isStopping,
      idle: !hasScan && !running,
      celebrate: !running && controller.scanSummary != null,
      photoIds: photoIds,
      loadPhoto: controller.thumbnailFor,
      faceIds: faceIds,
      semanticsLabel: label,
    );

    final String button;
    if (!controller.scanWholePhone) {
      button = 'Choose a folder';
    } else if (!hasScan) {
      button = 'Start indexing';
    } else {
      button = complete ? 'Index again' : 'Continue indexing';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        steps,
        if (!running)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.base),
            child: _StartPanel(label: button, controller: controller, onStart: () => startIndexing(context, controller)),
          ),
      ],
    );
  }
}
