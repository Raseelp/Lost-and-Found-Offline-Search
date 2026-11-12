import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';
import 'package:lost_and_found/features/update/services/update_service.dart';

/// Whether a newer version of the app is waiting in Google Play, and how far an update has got.
///
/// It asks a few seconds after the app opens and again when the app comes back after at least an hour, so it never
/// holds anything up. "Not now" only hides the card for the rest of this session: it is there again the next time the
/// app is opened, until the app is updated. An update that is downloading or ready to install is always shown.
class UpdateController extends GetxController with WidgetsBindingObserver {
  /// [firstCheckAfter] is how long to wait after the app opens before the first look. Null means no first look, for a
  /// test that looks by itself.
  UpdateController(this._service, {this.firstCheckAfter = const Duration(seconds: 4)});

  static const _lookAgainAfter = Duration(hours: 1);

  final UpdateService _service;
  final Duration? firstCheckAfter;

  UpdateStage stage = UpdateStage.none;
  int versionCode = 0;

  /// How much of the update has come, from 0 to 1, or null when it is not known.
  double? progress;

  /// The version put off with "Not now" in this session. It lives only as long as the app does.
  int? _dismissed;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _starting = false;
  Timer? _first;
  StreamSubscription<UpdateEvent>? _events;

  /// The card on the home screen shows while there is something to say.
  bool get visible => switch (stage) {
    UpdateStage.none => false,
    UpdateStage.available => versionCode != _dismissed,
    UpdateStage.downloading || UpdateStage.downloaded => true,
  };

  /// True from the moment a newer version is found until the app has been updated, even after "Not now". The dot on the
  /// settings gear and the Update section in Settings follow this.
  bool get pending => stage != UpdateStage.none;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _events = _service.events.listen(_onEvent, onError: (_) {});
    final wait = firstCheckAfter;
    if (wait != null) _first = Timer(wait, check);
    super.onInit();
  }

  @override
  void onClose() {
    _first?.cancel();
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    final busy = stage == UpdateStage.downloading || stage == UpdateStage.downloaded;
    if (busy || last == null || DateTime.now().difference(last) > _lookAgainAfter) unawaited(check());
  }

  /// Asks Google Play. Anything that goes wrong means no update, because the card is only a convenience.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final info = await _service.check();
      stage = info.stage;
      versionCode = info.versionCode;
      if (stage != UpdateStage.downloading) progress = null;
    } catch (_) {
      stage = UpdateStage.none;
    } finally {
      _checking = false;
    }
    update();
  }

  void _onEvent(UpdateEvent event) {
    switch (event.status) {
      case 'downloading':
        stage = UpdateStage.downloading;
        progress = event.progress;
      case 'downloaded':
        stage = UpdateStage.downloaded;
        progress = null;
      case 'installed':
        stage = UpdateStage.none;
        progress = null;
      case 'failed':
        stage = UpdateStage.none;
        progress = null;
        unawaited(check());
    }
    update();
  }

  /// Starts the update. Google Play asks the person to agree first, and puts the download in the background.
  Future<void> accept() async {
    if (_starting) return;
    _starting = true;
    String answer;
    try {
      answer = await _service.start();
    } catch (_) {
      answer = 'failed';
    } finally {
      _starting = false;
    }
    switch (answer) {
      case 'accepted':
        stage = UpdateStage.downloading;
        progress = null;
      case 'declined':
        await dismiss();
        return;
      default:
        AppToast.show("Couldn't start the update. You can update in Google Play.");
    }
    update();
  }

  /// "Not now": the card goes for the rest of this session and comes back the next time the app is opened.
  Future<void> dismiss() async {
    _dismissed = versionCode;
    update();
  }

  /// Installs the downloaded update. The app closes and opens in the new version.
  Future<void> restart() async {
    try {
      await _service.complete();
    } catch (_) {
      AppToast.show("Couldn't restart the app. Open it again to finish the update.");
    }
  }
}
