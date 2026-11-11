import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lost_and_found/core/permissions/permission_prompt.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/media/grid_video_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/app_links.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/view/hidden_people_screen.dart';
import 'package:lost_and_found/features/people/features/merge/view/merge_history_screen.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/tour/view/first_run_tour.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/core/native/device_service.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
import 'package:lost_and_found/features/settings/services/settings_service.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';
part 'settings_screen/shared.dart';
part 'settings_screen/settings_row.dart';
part 'settings_screen/danger_row.dart';
part 'settings_screen/permissions_card.dart';
part 'settings_screen/permission_row.dart';
part 'settings_screen/build_row.dart';
part 'settings_screen/expert_face_rows.dart';
part 'settings_screen/notifications_off_banner.dart';
part 'settings_screen/notifications_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ModelDownloadController>(
      builder: (models) => GetBuilder<LibraryController>(
        builder: (library) => GetBuilder<SettingsController>(
          builder: (settings) => _content(context, models, library, settings),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ModelDownloadController models,
    LibraryController library,
    SettingsController settings,
  ) {
    final modelBytes = models.searchModelBytes;
    final modelsVerified = models.searchModelsVerified;
    final hasEmbeddings =
        library.totalEmbeddings > 0 ||
        library.allIndexedFoldersList.isNotEmpty;
    final deletableBytes = models.searchModelsVerified
        ? models.searchModelBytes
        : 0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  const _GroupLabel('Models'),
                  _GroupCard(
                    children: [
                      _SettingsRow(
                        icon: modelsVerified
                            ? Icons.verified_outlined
                            : Icons.download_for_offline_outlined,
                        accentIcon: modelsVerified,
                        title: modelsVerified
                            ? 'Search model'
                            : 'Search model - not ready',
                        subtitle: modelsVerified
                            ? 'MobileCLIP-S0 (Apple)  ·  finds photos by meaning  ·  ${ModelDownloadProgress.formatBytes(modelBytes)}  ·  verified'
                            : null,
                        trailing: modelsVerified
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 18,
                              )
                            : null,
                      ),
                      const _SettingsRow(
                        icon: Icons.verified_outlined,
                        accentIcon: true,
                        title: 'Face detector',
                        subtitle:
                            'SCRFD det_2.5g  ·  finds where faces are in photos and videos  ·  about 3 MB  ·  built in',
                        trailing: Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const _SettingsRow(
                        icon: Icons.verified_outlined,
                        accentIcon: true,
                        title: 'Face recognition',
                        subtitle:
                            'MobileFaceNet w600k_mbf  ·  groups photos by person  ·  about 13 MB  ·  built in',
                        trailing: Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs,
                      AppSpacing.sm,
                      AppSpacing.xs,
                      0,
                    ),
                    child: Text(
                      'All the models run only on this device. Your photos, faces and names are never uploaded, '
                      'and nothing needs the internet once they are downloaded.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.ink48, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Permissions'),
                  _PermissionsCard(controller: settings),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Collections'),
                  GetBuilder<CollectionsController>(
                    builder: (collections) => _GroupCard(
                      children: [
                        _TapRow(
                          icon: Icons.sync_rounded,
                          title: 'Resync collections',
                          subtitle: collections.isScoring
                              ? 'Working on it...'
                              : 'Recompute every collection from scratch',
                          onTap: collections.isScoring
                              ? null
                              : collections.resyncAll,
                        ),
                        GetBuilder<MemoriesController>(
                          builder: (memories) {
                            final restorable =
                                collections.hasCustomizedBuiltIns ||
                                memories.hidden;
                            return _TapRow(
                              icon: Icons.restart_alt_rounded,
                              title: 'Restore default collections',
                              subtitle: restorable
                                  ? 'Bring back deleted or hidden ones (and On this day) and undo edits'
                                  : 'Nothing to restore',
                              onTap: restorable
                                  ? () {
                                      if (memories.hidden) {
                                        memories.setHidden(false);
                                      }
                                      if (collections
                                          .hasCustomizedBuiltIns) {
                                        collections.restoreDefaults();
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('People'),
                  GetBuilder<FacesController>(
                    builder: (faces) {
                      final st = faces.status;
                      return _GroupCard(
                        children: [
                          _SettingsRow(
                            icon: Icons.videocam_outlined,
                            title: 'Find people in videos',
                            subtitle:
                                'Checks a few frames of each video after the photos. Takes a while and uses battery.',
                            trailing: Switch(
                              value: st.scanVideos,
                              onChanged: faces.setScanVideos,
                            ),
                          ),
                          if (st.scanVideos)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.base,
                                AppSpacing.sm,
                                AppSpacing.base,
                                AppSpacing.md,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: SegmentedButton<String>(
                                      showSelectedIcon: false,
                                      segments: const [
                                        ButtonSegment(
                                          value: 'fast',
                                          label: Text('Fast'),
                                        ),
                                        ButtonSegment(
                                          value: 'balanced',
                                          label: Text('Balanced'),
                                        ),
                                        ButtonSegment(
                                          value: 'thorough',
                                          label: Text('Thorough'),
                                        ),
                                      ],
                                      selected: {st.videoDensity},
                                      onSelectionChanged: (s) =>
                                          faces.setVideoDensity(s.first),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'How many frames of each video are checked. Applies to videos not scanned yet - '
                                    '"Clear face data" below redoes the rest.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.ink48,
                                          height: 1.4,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          _TapRow(
                            icon: Icons.undo_rounded,
                            title: 'Undo a merge',
                            subtitle:
                                'Split two people you merged by mistake',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MergeHistoryScreen(),
                              ),
                            ),
                          ),
                          _TapRow(
                            icon: Icons.visibility_off_outlined,
                            title: 'Hidden people',
                            subtitle: faces.hiddenPeople.isEmpty
                                ? 'None'
                                : '${faces.hiddenPeople.length} hidden',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const HiddenPeopleScreen(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Videos'),
                  GetBuilder<GridVideoController>(
                    builder: (videos) => _GroupCard(
                      children: [
                        _SettingsRow(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'Play videos in grids',
                          subtitle:
                              'A silent preview of up to 15 seconds plays for the first video in view, then the next. Pauses while scanning and in battery saver.',
                          trailing: Switch(
                            value: videos.enabled,
                            onChanged: videos.setEnabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Notifications'),
                  const _NotificationsSection(),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Diagnostics'),
                  _GroupCard(
                    children: [
                      _SettingsRow(
                        icon: Icons.speed_rounded,
                        title: 'Performance logs',
                        subtitle:
                            'Logs how long indexing and finding faces take. Read with: adb logcat -s LostFoundBench',
                        trailing: Switch(
                          value: settings.benchLogsEnabled,
                          onChanged: settings.setBenchLogsEnabled,
                        ),
                      ),
                      _TapRow(
                        icon: Icons.content_copy_rounded,
                        title: 'Copy logs',
                        subtitle:
                            'Copies the app\'s recent log, to paste into a bug report. It can contain photo file addresses.',
                        onTap: () => _copyLogs(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('About'),
                  _GroupCard(
                    children: [
                      _TapRow(
                        icon: Icons.help_outline_rounded,
                        title: 'Help',
                        subtitle: 'A short tour of what the app does.',
                        onTap: () => openHelpTour(context),
                      ),
                      const _BuildRow(),
                      const _SourceRow(),
                      const _LicenseRow(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _GroupLabel('Danger zone'),
                  _GroupCard(
                    children: [
                      if (deletableBytes > 0 || modelsVerified)
                        _DangerRow(
                          title: 'Delete search model',
                          subtitle:
                              'Frees ~${ModelDownloadProgress.formatBytes(deletableBytes)} - the search model',
                          onTap: () => showConfirmDialog(
                            context,
                            title: 'Delete the search model?',
                            message:
                                'Search and indexing stop working until you download the search model again - you will be taken back to the setup screen. Your photos, the search index and the people already found are kept.',
                            confirmLabel: 'Delete',
                            onConfirm: () {
                              models.deleteModels().then((_) {
                                if (context.mounted) {
                                  Navigator.of(
                                    context,
                                  ).popUntil((route) => route.isFirst);
                                }
                              });
                            },
                          ),
                        ),
                      _DangerRow(
                        title: 'Clear all embeddings',
                        subtitle: hasEmbeddings
                            ? 'Forgets everything indexed for search'
                            : 'Nothing indexed yet',
                        onTap: !hasEmbeddings
                            ? null
                            : () => showConfirmDialog(
                                context,
                                title: 'Clear all embeddings?',
                                message:
                                    'This removes every generated search embedding and forgets all indexed folders. You will need to re-scan to search again. The people already found are kept - see "Clear face data" for those.',
                                confirmLabel: 'Clear',
                                onConfirm: library.clearAllEmbeddings,
                              ),
                      ),
                      GetBuilder<FacesController>(
                        builder: (faces) {
                          final st = faces.status;
                          final hasFaceData =
                              st.faces > 0 ||
                              st.people > 0 ||
                              st.processed > 0;
                          return _DangerRow(
                            title: 'Clear face data',
                            subtitle: hasFaceData
                                ? 'Forgets every group and name, then finds faces again'
                                : 'No face data yet',
                            onTap: !hasFaceData
                                ? null
                                : () => showConfirmDialog(
                                    context,
                                    title: 'Clear face data?',
                                    message:
                                        'All groups and the names you gave will be removed, and every indexed photo is searched for faces again.',
                                    confirmLabel: 'Clear',
                                    onConfirm: faces.rescanEverything,
                                  ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xl,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppColors.ink,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        0,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.ink48,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A link to the project's source code.
class _SourceRow extends StatelessWidget {
  const _SourceRow();

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(kRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) AppToast.show("Couldn't open the link.");
  }

  @override
  Widget build(BuildContext context) {
    return _TapRow(
      icon: Icons.code_rounded,
      title: 'Source code on GitHub',
      subtitle: 'Free, ad-free and fully open source.',
      onTap: () => _open(context),
    );
  }
}

/// The app's license notice (the AGPL asks for one in the app), and the licenses of the packages
/// it is built with.
class _LicenseRow extends StatelessWidget {
  const _LicenseRow();

  static const _legalese =
      'Copyright (C) 2026 Raseel.\n\n'
      'This program is free software: you can redistribute it and/or modify it under the terms '
      'of the GNU Affero General Public License, version 3.\n\n'
      'It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of '
      'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.\n\n'
      'The full license and the source code: $kRepoUrl';

  @override
  Widget build(BuildContext context) {
    return _TapRow(
      icon: Icons.description_outlined,
      title: 'License',
      subtitle: 'GNU AGPL-3.0, with no warranty. Tap for details.',
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'Lost & Found',
        applicationLegalese: _legalese,
      ),
    );
  }
}

Future<void> _copyLogs(BuildContext context) async {
  String message;
  try {
    final text = await SettingsService().appLogs();
    if (text.isEmpty) {
      message = 'There is no log to copy.';
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      message = 'Logs copied.';
    }
  } catch (_) {
    message = "Couldn't read the log.";
  }
  AppToast.show(message);
}
