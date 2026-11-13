import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/core/permissions/permission_prompt.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
import 'package:lost_and_found/features/memories/services/memories_service.dart';

class SettingsController extends GetxController with WidgetsBindingObserver {
  @override
  onInit() async {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadIndexNudge());
    unawaited(_loadAutoIndex());
    super.onInit();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  /// Checks the notification permission again on resume. A permanently denied permission hands off to the system
  /// settings screen (see [requestBackgroundScanPermission]) and returns at once, well before the person has answered,
  /// so checking right after that call reads the answer too early and leaves the "Enable" control showing stale state.
  /// The check on resume catches the real answer when the person comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkBackgroundScanPermission());
      if (_offerNotificationsPending) {
        _offerNotificationsPending = false;
        unawaited(offerNotifications());
      }
    }
  }

  static const _notificationsOfferedKey = 'notifications_offered';

  bool _offerNotificationsPending = false;

  bool _offeringNotifications = false;

  /// After the first scan ends, finished or stopped, asks once whether the app may send notifications. The daily memory
  /// and the stories note are on by default and cannot come without it. Nothing is asked if it is already allowed, and
  /// a scan that ends while the app is in the background asks when the app is next opened.
  Future<void> offerNotifications() async {
    if (_offeringNotifications) return;
    _offeringNotifications = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_notificationsOfferedKey) ?? false) return;
      await checkBackgroundScanPermission();
      if (backgroundNotificationsGranted) {
        await prefs.setBool(_notificationsOfferedKey, true);
        return;
      }
      final context = Get.context;
      final state = WidgetsBinding.instance.lifecycleState;
      final foreground = state == null || state == AppLifecycleState.resumed;
      if (!foreground || context == null || !context.mounted) {
        _offerNotificationsPending = true;
        return;
      }
      await prefs.setBool(_notificationsOfferedKey, true);
      if (!context.mounted) return;
      await showConfirmDialog(
        context,
        title: 'Allow notifications?',
        message:
            'Your daily memory, your stories note and the scan\'s progress come as notifications. '
            'You can turn each one off in Settings.',
        confirmLabel: 'Allow',
        confirmColor: AppColors.primary,
        onConfirm: () => unawaited(
          requestBackgroundScanPermission(
            purpose: 'send your daily memory, your stories note and the scan\'s progress',
          ),
        ),
      );
    } catch (e) {
      debugPrint('offerNotifications failed: $e');
    } finally {
      _offeringNotifications = false;
    }
  }

  /// Whether the system will show the scan-progress notification (see ScanForegroundService on the native side). It is
  /// never requested automatically, because storage and media access is asked for right before a scan and asking for
  /// both at once overwhelms people. The scanning UI offers its own "Enable" control instead. This only reflects the
  /// current answer of the system, checked when the app opens and whenever a scan starts.
  bool backgroundNotificationsGranted = false;

  /// The note that asks to finish indexing (see IndexNudge): on until turned off. The switch lives natively, where
  /// the note is made; this mirrors it.
  bool indexNudgeEnabled = true;

  /// Whether new photos and videos are indexed by themselves (see AutoIndex). The switch lives natively, where the work
  /// is done; this mirrors it. On until turned off.
  bool autoIndexEnabled = true;

  /// What auto indexing picks up: 'both' (the default), 'images' or 'videos'. It belongs to auto indexing alone, and the
  /// choice of the manual scan in the Library is separate.
  String autoIndexContent = 'both';

  Future<void> _loadAutoIndex() async {
    try {
      autoIndexEnabled = await LibraryService().autoIndexEnabled();
      autoIndexContent = await LibraryService().autoIndexContent();
      update();
    } catch (_) {
      // Stays on, the default.
    }
  }

  /// Turns indexing of new photos and videos on or off. Turning it on asks for the notification permission (Android 13
  /// and later), as a big batch is asked about in a notification and a medium one says that it is indexing. The choice is
  /// kept whether or not it is given. Returns whether it is on.
  Future<bool> setAutoIndexEnabled(bool on) async {
    if (on) {
      await askPermission(
        AppPermission.notifications,
        purpose: 'tell you when new photos are indexed, and ask before a big batch',
      );
    }
    autoIndexEnabled = on;
    update();
    await LibraryService().setAutoIndexEnabled(on);
    return on;
  }

  /// Sets what auto indexing picks up. What arrived while another choice was on is not looked at again.
  Future<void> setAutoIndexContent(String mode) async {
    if (mode == autoIndexContent) return;
    autoIndexContent = mode;
    update();
    await LibraryService().setAutoIndexContent(mode);
  }

  Future<void> _loadIndexNudge() async {
    try {
      indexNudgeEnabled = await MemoriesService().indexNudgeEnabled();
      update();
    } catch (_) {
      // Stays on, the default.
    }
  }

  /// Turns the note on or off. The choice is kept even when the notification permission is refused, because the note is
  /// on by default and only goes out while the permission is given. Turning it on asks for the permission (Android 13
  /// and later). Returns whether it is on.
  Future<bool> setIndexNudgeEnabled(bool on) async {
    if (on) {
      await askPermission(
        AppPermission.notifications,
        purpose: 'remind you to finish indexing your photos',
      );
    }
    indexNudgeEnabled = on;
    update();
    await MemoriesService().setIndexNudgeEnabled(on);
    return on;
  }

  /// Read-only: reflects the OS's current answer without prompting. Always granted before Android 13, where this
  /// permission does not exist.
  Future<void> checkBackgroundScanPermission() async {
    if (!Platform.isAndroid) {
      backgroundNotificationsGranted = true;
      update();
      return;
    }
    backgroundNotificationsGranted = await Permission.notification.isGranted;
    update();
  }

  /// The only place that prompts for it, wired to the Enable control in the scanning UI and never called
  /// automatically. There is no battery optimisation exemption request, because Play policy allows that only for a
  /// short list of core-function use cases this app does not fit. The scan surviving being killed (WorkManager's retry
  /// after interruption) takes its place. The value read afterwards may be stale until didChangeAppLifecycleState
  /// corrects it on resume.
  Future<void> requestBackgroundScanPermission({String? purpose}) async {
    if (!Platform.isAndroid) return;

    await askPermission(
      AppPermission.notifications,
      purpose:
          purpose ??
          'show the scan\'s progress and keep it going in the background',
    );

    await checkBackgroundScanPermission();
  }
}
