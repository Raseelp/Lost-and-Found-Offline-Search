import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/indexed_folder_model.dart';
import 'package:lost_and_found/models/model_status.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/view/widget/confirm_dialog.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/view/widget/library_orbit.dart';
import 'package:lost_and_found/view/widget/scan_square.dart';

// The list of indexed folders is switched off for now (it comes back with per-folder
// actions); the code for it is kept below.
const bool _showIndexedFolders = false;

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key, required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final scanning = controller.isScanning;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        floatingBarClearance(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The chip stays where it is through idle, scanning and done: only what is on it
          // (and what is written under it) changes.
          _ChipHero(controller: controller),
          AnimatedSize(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: scanning
                  ? _ScanningControls(
                      key: const ValueKey('scanning'),
                      controller: controller,
                    )
                  : _IdleControls(
                      key: const ValueKey('idle'),
                      controller: controller,
                    ),
            ),
          ),
          // What is indexed so far: one card, which is not there while a scan runs (the chip
          // above shows the progress), nor at all until something is indexed.
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: !_hasLibrary(controller) || scanning
                  ? const SizedBox(
                      key: ValueKey('none'),
                      width: double.infinity,
                    )
                  : _LibraryCard(
                      key: const ValueKey('card'),
                      images: controller.totalImages,
                      videos: controller.totalVideos,
                      folders: controller.allIndexedFoldersList.length,
                      embeddings: controller.totalEmbeddings,
                      sizeBytes: controller.indexSizeBytes,
                      lastScan: _lastScanTime(controller.allIndexedFoldersList),
                      failed: controller.totalFailed,
                    ),
            ),
          ),
          if (_showIndexedFolders &&
              controller.allIndexedFoldersList.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'INDEXED FOLDERS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.ink48,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...controller.allIndexedFoldersList.map(
              (f) => _FolderRow(folder: f, controller: controller),
            ),
          ],
        ],
      ),
    );
  }
}

bool _hasLibrary(NativeController controller) =>
    controller.totalImages > 0 ||
    controller.totalVideos > 0 ||
    controller.totalEmbeddings > 0 ||
    controller.allIndexedFoldersList.isNotEmpty;

Future<void> _startDeviceScan(
  BuildContext context,
  NativeController controller,
) async {
  final granted = await controller.requestMediaPermission(
    contentMode: controller.selectedContentMode,
  );
  if (!granted) return;
  controller.pickAndScanFolders(isScanEntirePhone: true);
}

// Before a scan (and after one): what to include, and the way to index one folder instead of
// the whole phone.
class _IdleControls extends StatelessWidget {
  const _IdleControls({super.key, required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.base),
        if (controller.interruptedScan != null) ...[
          _InterruptedScanBanner(controller: controller),
          const SizedBox(height: AppSpacing.base),
        ],
        if (controller.modelResetFrom != 0) ...[
          _ModelUpdatedBanner(controller: controller),
          const SizedBox(height: AppSpacing.base),
        ],
        Text(
          'WHAT TO INDEX',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Segmented<ContentMode>(
          options: _scopeOrder,
          value: controller.selectedContentMode,
          labelOf: _scopeLabel,
          onChanged: (mode) =>
              controller.toggleSelectedContentMode(contentMode: mode),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'WHERE TO LOOK',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Segmented<bool>(
          options: const [true, false],
          value: controller.scanWholePhone,
          labelOf: (wholePhone) => wholePhone ? 'Whole phone' : 'One folder',
          onChanged: controller.setScanWholePhone,
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            controller.scanWholePhone
                ? 'Everything on your phone, in one go.'
                : 'Tap the chip, then pick the folder.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
          ),
        ),
      ],
    );
  }
}

const _scopeOrder = [ContentMode.images, ContentMode.both, ContentMode.videos];

String _scopeLabel(ContentMode mode) {
  switch (mode) {
    case ContentMode.images:
      return 'Photos';
    case ContentMode.videos:
      return 'Videos';
    case ContentMode.both:
      return 'Photos & videos';
  }
}

// A row of choices, all in view, one tap to pick (used for what to index and where to look).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> options;
  final T value;
  final String Function(T option) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                label: labelOf(option),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (option != value) onChanged(option);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: option == value
                          ? AppColors.canvas
                          : AppColors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: option == value
                            ? AppColors.hairline
                            : AppColors.transparent,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labelOf(option),
                        maxLines: 1,
                        style: textTheme.bodySmall?.copyWith(
                          color: option == value
                              ? AppColors.primary
                              : AppColors.ink80,
                          fontWeight: option == value
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- what is indexed

String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

String _count(int n, String one, String many) =>
    '${_grouped(n)} ${n == 1 ? one : many}';

DateTime? _lastScanTime(List<IndexedFolder> folders) {
  if (folders.isEmpty) return null;
  final latest = folders
      .map((f) => f.updatedAt)
      .reduce((a, b) => a > b ? a : b);
  if (latest <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(latest);
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  }
  if (diff.inDays < 7) {
    return diff.inDays == 1 ? 'yesterday' : '${diff.inDays} days ago';
  }
  return '${time.day}/${time.month}/${time.year}';
}

// What is indexed so far, as one card: the two numbers people asked for (photos and videos)
// large, and under them, quietly, the rest (folders, embeddings, size on the phone, when it was
// last scanned). Files that could not be read get a line of their own when there are some.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    super.key,
    required this.images,
    required this.videos,
    required this.folders,
    required this.embeddings,
    required this.sizeBytes,
    required this.lastScan,
    required this.failed,
  });

  final int images, videos, folders, embeddings, sizeBytes, failed;
  final DateTime? lastScan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      _count(folders, 'folder', 'folders'),
      _count(embeddings, 'embedding', 'embeddings'),
      if (sizeBytes > 0)
        '${ModelDownloadProgress.formatBytes(sizeBytes)} on device',
      if (lastScan != null) 'scanned ${_timeAgo(lastScan!)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _BigCount(
                      icon: Icons.image_outlined,
                      value: images,
                      label: images == 1 ? 'photo' : 'photos',
                    ),
                  ),
                  const VerticalDivider(
                    width: AppSpacing.base,
                    color: AppColors.hairline,
                  ),
                  Expanded(
                    child: _BigCount(
                      icon: Icons.videocam_outlined,
                      value: videos,
                      label: videos == 1 ? 'video' : 'videos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: AppSpacing.md),
            Text(
              details.join('  ·  '),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.45,
              ),
            ),
            if (failed > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      '${_count(failed, 'file', 'files')} could not be read and '
                      '${failed == 1 ? 'was' : 'were'} skipped',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink80,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BigCount extends StatelessWidget {
  const _BigCount({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _grouped(value),
                maxLines: 1,
                style: textTheme.titleLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
        ),
      ],
    );
  }
}

// The chip at the top of the page: waiting to be started, scanning (indexing's progress, the
// photos being read and the queue of those waiting for their faces, and when indexing stops
// to find the faces of a batch the faces lifted out of their photos and placed among the
// people), or done. It is one widget for all three, so the chip itself never moves.
class _ChipHero extends StatelessWidget {
  const _ChipHero({required this.controller});

  final NativeController controller;

  // Before a total is known, native is still walking the picked folder
  // (a whole-device scan skips this phase entirely - see ScanProgress.path)
  // and already reports a live "found N files so far" through path. Parsed
  // back out below to drive an animated counter instead of just printing
  // the string as-is - a number that visibly ticks up reads as "actively
  // working" far more than the same text replacing itself every so often.
  int? _foundSoFarCount(IndexedFolder scan) {
    final match = RegExp(r'\d+').firstMatch(scan.path);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  String _thumbKey(RecentEmbeddedItem item) =>
      item.isVideo ? '${item.uri}@${item.timestampMs}' : item.uri;

  @override
  Widget build(BuildContext context) {
    // Indexing and finding faces take turns: every so many photos, indexing waits
    // while their faces are found. The chip shows whichever is happening right now.
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
      // Tapping the chip does what the "Where to look" choice says: the whole phone as before, or
      // ask for a folder.
      onStart: () => controller.scanWholePhone
          ? _startDeviceScan(context, controller)
          : controller.pickAndScanFolders(isScanEntirePhone: false),
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
      loadPhoto: (uri) => NativeServices()
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

// While a scan runs: the controls under the chip.
class _ScanningControls extends StatelessWidget {
  const _ScanningControls({super.key, required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stopping = controller.isStopping;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: OrbitPill(
            label: stopping ? 'Stopping…' : 'Stop indexing',
            icon: Icons.stop_rounded,
            busy: stopping,
            onTap: controller.stopScanning,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          stopping
              ? 'Finishing the photos in progress and saving them. This takes a few seconds.'
              : "Search already works on what's finished. This keeps going if you switch apps.",
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink48,
            height: 1.4,
          ),
        ),
        // Only until the notification permission is given; after that there is nothing to say.
        if (!controller.backgroundNotificationsGranted) ...[
          const SizedBox(height: AppSpacing.base),
          _BackgroundScanBanner(controller: controller),
        ],
      ],
    );
  }
}

// Asks for the permission that keeps a scan going in the background. Sets expectations rather
// than overpromising: background scanning genuinely can get cut short on some phones, so a big
// library is more reliably finished with the app open.
class _BackgroundScanBanner extends StatelessWidget {
  const _BackgroundScanBanner({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 17,
                color: AppColors.ink48,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Keep this going in the background',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink80,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: controller.requestBackgroundScanPermission,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                child: const Text('Enable'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              'Big libraries index fastest with the app open - background '
              'scanning works best in short stretches.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Shown in place of the usual scan buttons when a scan was still going the
// last time this app process existed but isn't anymore - see
// NativeController._checkForInterruptedScan for how that's detected.
// Resuming picks up exactly where it left off (embedImages skips whatever
// it already finished, by hash), so this is a one-tap fix rather than a
// full rescan.
// Shown once after the app moved to a new search model: what was indexed with the old one cannot be searched with the
// new one, so the index was started again and the photos need to be scanned again. (People and their faces are
// kept: they are not part of the index.)
class _ModelUpdatedBanner extends StatelessWidget {
  const _ModelUpdatedBanner({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Search model updated',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss',
                child: InkWell(
                  onTap: controller.acknowledgeModelReset,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.ink48,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Photos are now found by a smaller, more accurate model. Scan your photos once more so it can read them. People and faces are kept.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                controller.acknowledgeModelReset();
                controller.scanWholePhone
                    ? _startDeviceScan(context, controller)
                    : controller.pickAndScanFolders(isScanEntirePhone: false);
              },
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Scan again',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InterruptedScanBanner extends StatelessWidget {
  const _InterruptedScanBanner({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_outline_rounded,
            size: 17,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Indexing was interrupted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.ink80,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Pick up right where it left off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: controller.dismissInterruptedScan,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.ink48,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          InkWell(
            onTap: controller.resumeInterruptedScan,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Resume',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.controller});

  final IndexedFolder folder;
  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.pearl,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18, color: AppColors.ink48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.path.isEmpty ? 'Unknown' : folder.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${folder.embedded} embeddings',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => showConfirmDialog(
                context,
                title: 'Remove this folder?',
                message:
                    'This forgets everything indexed from "${folder.path}".',
                confirmLabel: 'Remove',
                onConfirm: () => controller.deleteFolderById(id: folder.id),
              ),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.ink48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
