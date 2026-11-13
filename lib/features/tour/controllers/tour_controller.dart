import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the first-run tour is showing, and which version of the introduction this phone has seen.
///
/// The tour is for fresh installs and shows before the models are downloaded. Somebody who updates with the models
/// already on the phone never sees it, unless they open it from Settings > App tour. A "What's new" introduction can use
/// the same screens ([TourScreen] takes its pages) and compare [seenVersion] with its own version.
class TourController extends GetxController {
  static const _seenKey = 'tour_seen_version';

  /// The version of the first-run tour.
  static const int firstRunVersion = 1;

  bool loaded = false;

  /// The latest version this phone has been through; 0 for none.
  int seenVersion = 0;

  /// The tour is on screen and stays until it is finished, even when the download behind it ends.
  bool active = false;

  bool _decided = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      seenVersion = prefs.getInt(_seenKey) ?? 0;
    } catch (e) {
      debugPrint('tour prefs failed: $e');
    }
    loaded = true;
    update();
  }

  /// Asked by the gate on every build. Decided once, the first time the models are known: a fresh install
  /// (nothing seen, models not there) gets the tour; a phone that already has the models never does, because an
  /// update on a phone that is already set up has nothing to introduce.
  bool shouldShow({required bool modelsReady}) {
    if (!loaded) return false;
    if (!_decided) {
      _decided = true;
      if (seenVersion < firstRunVersion) {
        if (modelsReady) {
          seenVersion = firstRunVersion;
          unawaited(_save());
        } else {
          active = true;
        }
      }
    }
    return active;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenKey, seenVersion);
    } catch (e) {
      debugPrint('tour prefs failed: $e');
    }
  }

  /// The tour was finished: it does not come back by itself.
  Future<void> finish() async {
    active = false;
    seenVersion = firstRunVersion;
    update();
    await _save();
  }
}
