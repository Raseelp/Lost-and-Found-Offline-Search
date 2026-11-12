import 'dart:async';

import 'package:get/get.dart';
import 'package:lost_and_found/core/storage/preferences.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the developer's note is shown in full, and whether the green dot that points to it is waiting.
///
/// Until [unlockAt] photos and videos have been indexed, the page in Settings is only a way to report a problem. Once
/// the library reaches that size the note unlocks and stays unlocked, even if the index is cleared later. A dot on the
/// settings button and on the page's tile asks the person to look, and goes after the first visit.
class DeveloperNoteController extends GetxController {
  DeveloperNoteController(this._library);

  /// How many photos and videos have to be indexed before the note shows in full.
  static const int unlockAt = 1000;

  static const _unlockedKey = 'developer_note_unlocked';
  static const _seenKey = 'developer_note_seen';

  final LibraryController _library;

  bool unlocked = false;
  bool seen = false;

  /// The dot is shown from the moment the note unlocks until the person has opened it.
  bool get showDot => unlocked && !seen;

  @override
  void onInit() {
    _library.addListener(_check);
    unawaited(_load());
    super.onInit();
  }

  @override
  void onClose() {
    _library.removeListener(_check);
    super.onClose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      unlocked = unlocked || (prefs.getBool(_unlockedKey) ?? false);
      seen = seen || (prefs.getBool(_seenKey) ?? false);
    } catch (_) {
      // Stays as it was: locked until the library is big enough.
    }
    _check();
    update();
  }

  void _check() {
    if (unlocked || _library.totalImages + _library.totalVideos < unlockAt) return;
    unlocked = true;
    unawaited(persistBool(_unlockedKey, true));
    update();
  }

  /// The person has opened the note. The dot goes and stays gone.
  void markSeen() {
    if (!unlocked || seen) return;
    seen = true;
    unawaited(persistBool(_seenKey, true));
    update();
  }
}
