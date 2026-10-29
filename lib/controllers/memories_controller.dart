import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/view/on_this_day_screen.dart';
import 'package:lost_and_found/view/person_screen.dart';
import 'package:lost_and_found/view/widget/permission_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Memories: "on this day" (the card on the Library tab and its screen), "then and now" for a person,
/// and the settings of the daily notification.
///
/// The dates of everything indexed are looked up a slice at a time in the background (native
/// LibraryDates), with pauses between slices, and "on this day" is shown from whatever is dated as
/// soon as there is anything - then again once the rest is in.
class MemoriesController extends GetxController with WidgetsBindingObserver {
  final _native = NativeServices();

  // ---- on this day ----

  OnThisDay today = OnThisDay.empty;
  bool loaded = false;

  /// What the card is called while collections are chosen for export (next to the real collections' ids).
  static const String selectionId = 'on-this-day';

  /// Whether the user took the card off the Collections tab. Kept; undone with [restore].
  bool hidden = false;
  static const String _hiddenKey = 'on_this_day_hidden';

  /// Set while the home screen is up: a tapped notification opens its memory only then.
  bool homeReady = false;

  bool _running = false;
  bool _closed = false;
  String _loadedDay = '';
  DateTime? _loadedAt;

  static const Duration _stale = Duration(minutes: 30);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadSettings());
    unawaited(_loadHidden());
  }

  Future<void> _loadHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      hidden = prefs.getBool(_hiddenKey) ?? false;
      update();
    } catch (e) {
      debugPrint('on this day: could not read hidden: $e');
    }
  }

  /// Takes the card off the Collections tab (or brings it back). The screen stays reachable from
  /// the daily notification either way.
  Future<void> setHidden(bool value) async {
    hidden = value;
    update();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hiddenKey, value);
    } catch (e) {
      debugPrint('on this day: could not save hidden: $e');
    }
  }

  @override
  void onClose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back in the app: the day may have turned over, and a notification may have been tapped.
    unawaited(loadToday());
    unawaited(loadSettings());
    unawaited(checkLaunch());
  }

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  /// Looks up today's date in the past years. Does nothing again for half an hour unless [force], or
  /// the date has changed.
  Future<void> loadToday({bool force = false}) async {
    final now = DateTime.now();
    final fresh =
        !force &&
        _loadedDay == _dayKey(now) &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < _stale;
    if (_running || fresh) return;
    _running = true;
    try {
      // The first slice brings the catalog in step with the index; what is dated by then is shown.
      await _native.memoryPrepare(budgetMs: 300);
      today = await _native.onThisDay();
      loaded = true;
      update();

      // Then the rest, gently: short turns with pauses (the dates of a big library can take a while).
      var stuck = 0;
      var before = -1;
      var progressed = false;
      while (!_closed) {
        final p = await _native.memoryPrepare(budgetMs: 500);
        if (before >= 0 && p.pending < before) progressed = true;
        if (p.pending == 0) break;
        stuck = (before >= 0 && p.pending >= before) ? stuck + 1 : 0;
        before = p.pending;
        if (stuck >= 4) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (progressed && !_closed) {
        today = await _native.onThisDay();
        update();
      }
      _loadedDay = _dayKey(now);
      _loadedAt = DateTime.now();
    } catch (e) {
      debugPrint('memories failed: $e');
      loaded = true;
      update();
    } finally {
      _running = false;
    }
  }

  int _lastIndexed = -1;

  /// The number of things indexed changed (a scan finished): the memories are looked up again, since
  /// there are new photos to date. The first call only notes the number.
  void onIndexChanged(int indexed) {
    if (indexed == _lastIndexed) return;
    final first = _lastIndexed < 0;
    _lastIndexed = indexed;
    if (!first) unawaited(loadToday(force: true));
  }

  /// Opens the memory a tapped notification was about (once), when the home screen is up.
  Future<void> checkLaunch() async {
    if (!homeReady) return;
    try {
      final launch = await _native.takeLaunchMemory();
      if (launch == null) return;
      // A memory about a person opens their page (where then and now is); the others open the day.
      if (launch.personId != 0 && Get.isRegistered<FacesController>()) {
        final faces = Get.find<FacesController>();
        // Opened cold from the notification: the people may not be in yet.
        if (faces.people.isEmpty) await faces.refreshPeople();
        final people = faces.people.where((p) => p.id == launch.personId);
        if (people.isNotEmpty) {
          Get.to<void>(() => PersonScreen(person: people.first));
          return;
        }
      }
      if (!loaded) await loadToday();
      openOnThisDay(focusYear: launch.year == 0 ? null : launch.year);
    } catch (e) {
      debugPrint('takeLaunchMemory failed: $e');
    }
  }

  void openOnThisDay({int? focusYear}) {
    Get.to<void>(() => OnThisDayScreen(focusYear: focusYear));
  }

  // ---- then and now ----

  // Kept for the day (which photos are shown first changes daily). "Not enough to compare" is not kept: the
  // dates may still be coming in.
  final Map<String, ThenNow> _thenNow = {};

  /// [person]'s clearest photo from their first year and from their latest, or null when there are not
  /// enough photos over enough time to compare. Kept until their photos change.
  Future<ThenNow?> thenNowFor(Person person) async {
    final key = '${person.id}:${person.photoCount}:${_dayKey(DateTime.now())}';
    final known = _thenNow[key];
    if (known != null) return known;
    try {
      final found = await _native.thenAndNow(person.id);
      if (found != null) _thenNow[key] = found;
      return found;
    } catch (e) {
      debugPrint('thenAndNow failed: $e');
      return null;
    }
  }

  // A few portraits are kept (they are small, but a person flips between them and the full screen).
  final LinkedHashMap<String, Uint8List> _portraits = LinkedHashMap();

  Future<Uint8List?> portrait(ThenNowSide side) async {
    final key = side.cropKey;
    final kept = _portraits.remove(key);
    if (kept != null) {
      _portraits[key] = kept;
      return kept;
    }
    try {
      final bytes = await _native.portraitCrop(side);
      if (bytes != null) {
        _portraits[key] = bytes;
        while (_portraits.length > 16) {
          _portraits.remove(_portraits.keys.first);
        }
      }
      return bytes;
    } catch (e) {
      debugPrint('portraitCrop failed: $e');
      return null;
    }
  }

  // ---- the daily notification ----

  MemorySettings settings = const MemorySettings();

  Future<void> loadSettings() async {
    try {
      settings = await _native.memorySettings();
      update();
    } catch (e) {
      debugPrint('memorySettings failed: $e');
    }
  }

  /// Turns the daily memory on or off. Turning it on asks for the notification permission first (Android 13
  /// and later) and stays off if it is refused. Returns whether it is on now.
  Future<bool> setEnabled(bool on) async {
    if (on) {
      // Asked as every permission is (see askPermission): it says why if it is turned down.
      final allowed = await askPermission(
        AppPermission.notifications,
        purpose: 'send your daily memory',
      );
      if (!allowed) {
        await loadSettings();
        return false;
      }
    }
    settings = await _native.setMemorySettings(enabled: on);
    update();
    return settings.enabled;
  }

  /// Sends today's memory now. Returns what happened, in words.
  Future<String> sendTest() async {
    try {
      final message = await _native.memoryTest();
      return message;
    } catch (e) {
      return 'Could not make a memory: $e';
    }
  }
}
