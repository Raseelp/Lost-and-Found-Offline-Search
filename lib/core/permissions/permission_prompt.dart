import 'dart:io';

import 'package:get/get.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/core/native/device_service.dart';

/// What the app asks Android for, each with what it is for.
enum AppPermission {
  /// Photos and videos, to index them.
  media,

  /// Notifications: the scan's progress, the daily memory, the stories note.
  notifications,

  /// Storage, to save a copy to the gallery on Android 9 and older (later versions need no permission for it).
  storage,
}

/// Asks for [what] the one way every part of the app does. Returns whether it is allowed.
///
/// When Android has stopped asking, a dialog says what is off and opens App info. Notifications before Android 13 have
/// no prompt at all, so the same dialog is the only way to turn them on. When it was turned down in the system prompt,
/// a short message says what it is needed for. [only] narrows [AppPermission.media] to photos or
/// videos, and [purpose] finishes "... so Lost & Found can't ...". [explain] runs right before Android's own prompt
/// would appear, and returning false stops the request without a message. Storage only matters before Android 10, and an
/// unknown version (0) is let through, because asking on a newer phone is always refused and would stop every save.
Future<bool> askPermission(
  AppPermission what, {
  List<Permission>? only,
  String? purpose,
  Future<bool> Function()? explain,
}) async {
  if (!Platform.isAndroid) return true;
  final sdk = await DeviceService().androidSdk();
  if (what == AppPermission.storage && (sdk == 0 || sdk >= 29)) return true;
  final permissions = only ?? _permissionsFor(what);
  if (permissions.isEmpty) return true;

  final before = [for (final p in permissions) await p.status];
  if (before.every(_allowed)) return true;
  final noPrompt = what == AppPermission.notifications && sdk > 0 && sdk < 33;
  if (noPrompt || before.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
    await _showBlocked(what, sdk, purpose);
    return false;
  }
  if (explain != null && !await explain()) return false;
  final after = await permissions.request();
  if (after.values.every(_allowed)) return true;
  _say(_turnedDown(what, purpose));
  return false;
}

/// Limited access (a few chosen photos) counts as allowed, because the app indexes what it may see.
bool _allowed(PermissionStatus s) => s.isGranted || s.isLimited;

List<Permission> _permissionsFor(AppPermission what) => switch (what) {
  AppPermission.media => [Permission.photos, Permission.videos],
  AppPermission.notifications => [Permission.notification],
  AppPermission.storage => [Permission.storage],
};

/// [purpose] when given, else the usual purpose of [what].
String _purposeOf(AppPermission what, String? purpose) =>
    purpose ??
    switch (what) {
      AppPermission.media => 'see your photos and videos to index them',
      AppPermission.notifications => 'show you its notifications',
      AppPermission.storage => 'save a copy to your gallery',
    };

String _turnedDown(AppPermission what, String? purpose) {
  final need = switch (what) {
    AppPermission.media => 'Photo and video access is needed',
    AppPermission.notifications => 'Notifications are needed',
    AppPermission.storage => 'Storage access is needed',
  };
  return '$need to ${_purposeOf(what, purpose)}.';
}

/// Where the switch is in App info, in the words this Android version uses.
String _steps(AppPermission what, int sdk) => switch (what) {
  AppPermission.media =>
    sdk >= 33
        ? 'In App info, tap Permissions, then Photos and videos, and choose Allow all.'
        : sdk >= 30
        ? 'In App info, tap Permissions, then Files and media, and choose Allow access to media only.'
        : 'In App info, tap Permissions, then Storage, and choose Allow.',
  AppPermission.notifications =>
    'In App info, tap Notifications and turn on All Lost & Found notifications.',
  AppPermission.storage =>
    'In App info, tap Permissions, then Storage, and choose Allow.',
};

Future<void> _showBlocked(AppPermission what, int sdk, String? purpose) async {
  final context = Get.context;
  if (context == null || !context.mounted) {
    await openAppSettings();
    return;
  }
  final (title, off) = switch (what) {
    AppPermission.media => ('Photo access is off', 'photo and video access'),
    AppPermission.notifications => ('Notifications are off', 'notifications'),
    AppPermission.storage => ('Storage access is off', 'storage access'),
  };
  await showConfirmDialog(
    context,
    title: title,
    message:
        'Android has stopped asking for $off, so Lost & Found can\'t ${_purposeOf(what, purpose)}. '
        '${_steps(what, sdk)} Then come back here.',
    confirmLabel: 'Open App info',
    confirmColor: AppColors.primary,
    onConfirm: () => openAppSettings(),
  );
}

void _say(String message) => AppToast.show(message);
