import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/grid_video_controller.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/model_status.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_links.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/hidden_people_screen.dart';
import 'package:lost_and_found/view/merge_history_screen.dart';
import 'package:lost_and_found/view/widget/confirm_dialog.dart';
import 'package:lost_and_found/view/tour/first_run_tour.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NativeController>(
      builder: (controller) {
        final modelBytes = controller.searchModelBytes;
        final modelsVerified = controller.searchModelsVerified;
        final hasEmbeddings =
            controller.totalEmbeddings > 0 ||
            controller.allIndexedFoldersList.isNotEmpty;
        // What a delete would free: the downloaded (search) models.
        final deletableBytes = controller.searchModelsVerified
            ? controller.searchModelBytes
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
                      _PermissionsCard(controller: controller),
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
                              // The expert controls are switched off (their defaults give the
                              // best results). To bring them back, add:
                              //   ..._expertFaceRows(context, faces, st, null)
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
                      const _GroupLabel('Memories'),
                      const _MemoriesSection(),
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
                              value: controller.benchLogsEnabled,
                              onChanged: controller.setBenchLogsEnabled,
                            ),
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
                                  controller.deleteModels().then((_) {
                                    // Back to the root: the app gate now shows the setup screen.
                                    if (context.mounted) {
                                      Navigator.of(
                                        context,
                                      ).popUntil((route) => route.isFirst);
                                    }
                                  });
                                },
                              ),
                            ),
                          // Greyed out once there is nothing left to clear.
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
                                    onConfirm: controller.clearAllEmbeddings,
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
      },
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: AppColors.pearl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.dividerSoft),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accentIcon = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool accentIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      child: Row(
        // Long text wraps to more lines instead of being cut off.
        children: [
          Icon(
            icon,
            size: 18,
            color: accentIcon ? AppColors.primary : AppColors.ink48,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: accentIcon ? AppColors.primary : null,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) const SizedBox(width: AppSpacing.sm),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;

  /// Null greys the row out: there is nothing for it to do.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: AppColors.danger),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Only ever checked once at startup before - this screen is reached by a
// normal push now (not kept alive under an IndexedStack), so a fresh check
// in initState is enough on its own; the lifecycle observer still catches
// granting/revoking from system Settings while this screen is open.
// Every permission the app ever asks for should have a row here - this is
// meant to be the one place a user (or us, reviewing it) can see the
// app's complete permission footprint at a glance. Whenever a new one is
// added anywhere else in the app, add its row here too:
//  - Photos/Videos: storage access, requested in NativeController.
//    requestMediaPermission - required, the app can't scan without it.
//  - Notifications: "keep this going in the background" - requested by
//    NativeController.requestBackgroundScanPermission (see its doc),
//    tracked in backgroundNotificationsGranted, refreshed automatically
//    on every app resume by NativeController's own WidgetsBindingObserver -
//    optional, scanning works without it, it just won't show a progress
//    notification.
class _PermissionsCard extends StatefulWidget {
  const _PermissionsCard({required this.controller});

  final NativeController controller;

  @override
  State<_PermissionsCard> createState() => _PermissionsCardState();
}

class _PermissionsCardState extends State<_PermissionsCard>
    with WidgetsBindingObserver {
  bool? _photosGranted;
  bool? _videosGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final photos = await Permission.photos.isGranted;
    final videos = await Permission.videos.isGranted;
    if (!mounted) return;
    setState(() {
      _photosGranted = photos;
      _videosGranted = videos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    // Always shows every status row, granted or not - hiding the whole
    // card once granted left the "Permissions" label sitting above
    // nothing, which reads as broken rather than as good news.
    final needsStorageGrant =
        _photosGranted == false || _videosGranted == false;
    final needsNotificationGrant = !controller.backgroundNotificationsGranted;

    return _GroupCard(
      children: [
        _PermissionRow(label: 'Photos', granted: _photosGranted),
        _PermissionRow(label: 'Videos', granted: _videosGranted),
        if (needsStorageGrant)
          _GrantAccessRow(
            onTap: () async {
              await [Permission.photos, Permission.videos].request();
              await _refresh();
            },
          ),
        const Divider(height: 1, color: AppColors.hairline),
        _PermissionRow(
          label: 'Notifications',
          granted: controller.backgroundNotificationsGranted,
        ),
        if (needsNotificationGrant)
          _GrantAccessRow(onTap: controller.requestBackgroundScanPermission),
      ],
    );
  }
}

class _GrantAccessRow extends StatelessWidget {
  const _GrantAccessRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Text(
          'Grant access',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});

  final String label;
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    final isGranted = granted == true;
    final color = granted == null
        ? AppColors.ink48
        : (isGranted ? AppColors.primary : AppColors.danger);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            granted == null
                ? Icons.hourglass_empty_rounded
                : (isGranted
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined),
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          Text(
            granted == null
                ? 'Checking...'
                : (isGranted ? 'Granted' : 'Not granted'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Which build this is, the way Telegram X lists it: the version, the build number and the commit it was made from
/// (a "+" after the commit means there were changes that were not committed). Tapping copies it, for a bug report.
class _BuildRow extends StatefulWidget {
  const _BuildRow();

  @override
  State<_BuildRow> createState() => _BuildRowState();
}

class _BuildRowState extends State<_BuildRow> {
  String? _text;

  @override
  void initState() {
    super.initState();
    NativeServices().buildInfo().then((info) {
      if (!mounted || info == null) return;
      final parts = [
        'Version ${info['version']} (${info['build']})',
        'commit ${info['commit']}',
        if ('${info['commitDate']}' != 'unknown') '${info['commitDate']}',
        if (info['debug'] == true || kDebugMode) 'debug build',
      ];
      setState(() => _text = parts.join(' · '));
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return InkWell(
      onTap: text == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(
                ClipboardData(text: 'Lost & Found $text'),
              );
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Build details copied.')),
                );
            },
      child: _SettingsRow(
        icon: Icons.info_outline_rounded,
        title: 'Lost & Found',
        subtitle: text ?? 'Version',
      ),
    );
  }
}

/// A link to the project's source code.
class _SourceRow extends StatelessWidget {
  const _SourceRow();

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(kRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
    }
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

// A settings row that does something when tapped - dimmed and inert when
// [onTap] is null.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: _SettingsRow(icon: icon, title: title, subtitle: subtitle),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// The face controls that are not shown (their defaults are the best settings). They moved here
// from the old Faces options sheet. Everything they call still works: FacesController
// .setStrictness / setRefine / setThorough / retune / regroup / models / selectModel. To bring any
// back, add these rows to the People section above, e.g.
//   ..._expertFaceRows(context, faces, st, models)
// ---------------------------------------------------------------------------------------------

// ignore: unused_element
List<Widget> _expertFaceRows(
  BuildContext context,
  FacesController faces,
  FaceStatus status,
  FaceModels? models,
) {
  final textTheme = Theme.of(context).textTheme;

  Widget chips(String kind) {
    final list = models?.ofKind(kind) ?? const <FaceModelInfo>[];
    if (list.isEmpty) {
      return Text(
        'none installed',
        style: textTheme.bodySmall?.copyWith(color: AppColors.danger),
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final m in list)
          ChoiceChip(
            label: Text(
              '${m.name}  ${(m.sizeBytes / 1048576).toStringAsFixed(0)} MB',
            ),
            selected: m.selected,
            onSelected: (_) => faces.selectModel(m),
          ),
      ],
    );
  }

  return [
    // Sorts the automatic groups again from every face known now (names and hand edits are kept).
    SheetRow(
      icon: Icons.auto_fix_high_rounded,
      label: 'Regroup now',
      subtitle:
          'Sorts the faces into people again. Names and your edits are kept',
      onTap: faces.regroup,
    ),
    // Models (the detector and the recognition model).
    Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Text(
        'Models',
        style: textTheme.labelMedium?.copyWith(color: AppColors.ink48),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Finds faces', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          chips('detector'),
          const SizedBox(height: AppSpacing.md),
          Text('Tells people apart', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          chips('embedder'),
        ],
      ),
    ),
    // How strict the grouping is (applied by "Regroup now").
    Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Text(
        'Grouping',
        style: textTheme.labelMedium?.copyWith(color: AppColors.ink48),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'strict', label: Text('Strict')),
            ButtonSegment(value: 'balanced', label: Text('Balanced')),
            ButtonSegment(value: 'loose', label: Text('Loose')),
          ],
          selected: {status.strictness},
          onSelectionChanged: (s) => faces.setStrictness(s.first),
        ),
      ),
    ),
    SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      title: Text(
        'Recognise small and blurry faces',
        style: textTheme.bodyMedium,
      ),
      subtitle: Text(
        'A second pass after the clear faces are done, matching the rest to the same people.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
      value: status.refine,
      onChanged: (v) => faces.setRefine(v),
    ),
    SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      title: Text('Search harder for small faces', style: textTheme.bodyMedium),
      subtitle: Text(
        'Slower. Applies to photos scanned from now on.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
      value: status.thorough,
      onChanged: (v) => faces.setThorough(v),
    ),
    SheetRow(
      icon: Icons.speed_rounded,
      label: 'Speed test',
      subtitle: status.tuning ?? 'Runs once, at the start of the next scan',
      onTap: faces.retune,
    ),
  ];
}

// ---------------------------------------------------------------------------------------------
// The daily memory: one notification a day at most, only when there is something good.
// ---------------------------------------------------------------------------------------------

class _MemoriesSection extends StatelessWidget {
  const _MemoriesSection();

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MemoriesController>(
      builder: (memories) {
        final s = memories.settings;

        void say(String text) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(text)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupCard(
              children: [
                _SettingsRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Daily memory',
                  subtitle:
                      'Two a day, morning and evening, only when there is something good.',
                  trailing: Switch(
                    value: s.enabled,
                    onChanged: (on) async {
                      final ok = await memories.setEnabled(on);
                      if (on && !ok) say('Allow notifications for this app to get a daily memory.');
                    },
                  ),
                ),
                if (s.enabled && !s.allowed)
                  _TapRow(
                    icon: Icons.notifications_off_outlined,
                    title: 'Notifications are off for this app',
                    subtitle:
                        'Tap to open the system settings and turn them on.',
                    onTap: openAppSettings,
                  ),
                if (s.enabled) ...[
                  _TapRow(
                    icon: Icons.send_rounded,
                    title: 'Send one now',
                    subtitle: 'See a different one each time.',
                    onTap: () async => say(await memories.sendTest()),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
