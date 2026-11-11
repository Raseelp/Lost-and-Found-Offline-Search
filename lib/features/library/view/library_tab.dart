import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/floating_bar.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/library/view/widgets/library_orbit.dart';
import 'package:lost_and_found/features/library/view/widgets/scan_square.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
part 'library_tab/start_device_scan.dart';
part 'library_tab/chip_hero.dart';
part 'library_tab/idle_controls.dart';
part 'library_tab/segmented.dart';
part 'library_tab/library_card.dart';
part 'library_tab/background_scan_banner.dart';
part 'library_tab/model_updated_banner.dart';
part 'library_tab/interrupted_scan_banner.dart';
part 'library_tab/folder_row.dart';

/// The Library page: the chip at the top, the controls under it and a card of what is indexed so far.
///
/// The chip stays where it is through idle, scanning and done, and only what is on it changes. The card is not there
/// while a scan runs, as the chip shows the progress, nor at all until something is indexed.
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

/// Whether the list of indexed folders is shown. It is switched off until per-folder actions exist, and the code for
/// it is kept.
const bool _showIndexedFolders = false;

bool _hasLibrary(NativeController controller) =>
    controller.totalImages > 0 ||
    controller.totalVideos > 0 ||
    controller.totalEmbeddings > 0 ||
    controller.allIndexedFoldersList.isNotEmpty;

DateTime? _lastScanTime(List<IndexedFolder> folders) {
  if (folders.isEmpty) return null;
  final latest = folders
      .map((f) => f.updatedAt)
      .reduce((a, b) => a > b ? a : b);
  if (latest <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(latest);
}

/// The controls under the chip while a scan runs. The banner about notifications shows only until the permission is
/// given.
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
        if (!controller.backgroundNotificationsGranted) ...[
          const SizedBox(height: AppSpacing.base),
          _BackgroundScanBanner(controller: controller),
        ],
      ],
    );
  }
}
