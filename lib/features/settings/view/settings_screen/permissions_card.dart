part of '../settings_screen.dart';

/// Every permission the app asks for, one row each. It is the one place that shows the app's whole permission
/// footprint, so a permission added anywhere else gets its row here too. Photos and videos are required for scanning
/// ([NativeController.requestMediaPermission]). Notifications are optional: they keep a scan going in the background
/// and show its progress, and [NativeController] refreshes `backgroundNotificationsGranted` on every resume. The rows
/// always show, because hiding the card once everything is granted would leave the Permissions label above nothing.
/// The check runs when the card opens and on resume, to catch a change made in system Settings.
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
              await askPermission(AppPermission.media);
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
