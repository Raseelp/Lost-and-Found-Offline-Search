import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/db/stories_store.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/models/story_state.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/story_planner.dart';
import 'package:lost_and_found/view/widget/permission_prompt.dart';

export 'package:lost_and_found/models/story_state.dart' show StoryFrame;

/// Who or what a ring on the Search tab is about.
enum StoryKind { person, collection }

/// One ring: a person or a collection, with a short story made of their photos.
class StoryRing {
  const StoryRing._({
    required this.key,
    required this.kind,
    required this.title,
    required this.count,
    this.person,
    this.collection,
  });

  factory StoryRing.person(Person person) => StoryRing._(
    key: 'p${person.id}',
    kind: StoryKind.person,
    title: person.name ?? 'Unnamed',
    count: person.photoCount,
    person: person,
  );

  factory StoryRing.collection(SmartCollection collection, int count) => StoryRing._(
    key: 'c${collection.id}',
    kind: StoryKind.collection,
    title: collection.name,
    count: count,
    collection: collection,
  );

  /// Stable across launches, so what was seen is remembered.
  final String key;
  final StoryKind kind;
  final String title;

  /// How many photos and videos it holds.
  final int count;
  final Person? person;
  final SmartCollection? collection;
}

/// The story of a ring right now: its pictures and the line that says how they were chosen.
class StoryEdition {
  const StoryEdition({required this.frames, this.caption});

  final List<StoryFrame> frames;
  final String? caption;

  static const StoryEdition empty = StoryEdition(frames: []);
}

/// The rings of the Search tab and their stories.
///
/// Each ring has an edition: a few pictures it has not shown before, chosen through one lens (new, a throwback,
/// the best, forgotten ones - see [StoryPlanner]). The edition is made when the ring is opened, and a ring that
/// has been opened is grey for 24 hours (its story can be played again); then it has a new edition, made of
/// pictures that were not in any before, until the ring has nothing left, when it rests for a few days and its
/// round starts again. Which rings are in the row, and in what order, is [StoryRowPicker]'s work.
class StoriesController extends GetxController with WidgetsBindingObserver {
  StoriesController({StoriesStore? store, DateTime Function()? clock})
    : _store = store ?? SqliteStoriesStore(),
      _clock = clock ?? DateTime.now;

  final StoriesStore _store;
  final DateTime Function() _clock;

  /// The collections that get a story: the pleasant ones. Screenshots, documents, tickets, notes and memes are left
  /// out, and so are collections made by the person.
  static const Set<String> storyCollectionIds = {
    'builtin_beach',
    'builtin_flowers',
    'builtin_mountains',
    'builtin_golden_hour',
    'builtin_night_sky',
    'builtin_rainy',
    'builtin_road_trip',
    'builtin_pets',
    'builtin_food',
  };

  static const int _day = StoryRowPicker.day;

  /// How long a ring that has used up what it had rests, and how long "Not now" sets one aside.
  static const int restDays = 3;
  static const int mutedDays = 30;

  final Map<String, RingState> _states = {};
  final Map<String, Future<StoryEdition?>> _building = {};

  // The rings of the row (see StoryBatch), and whether the next time they are asked for a new batch is to be made.
  StoryBatch _batch = const StoryBatch();
  bool _newBatch = false;

  /// The saved state has been read: until then there are no rings to show.
  bool ready = false;

  /// A refresh by hand is running.
  bool refreshing = false;
  int _refreshes = 0;

  /// The "your stories have refreshed" note: whether it is on, and whether the system lets the app show notes.
  bool reminderEnabled = true;
  bool reminderAllowed = false;

  int get _now => _clock().millisecondsSinceEpoch;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  // Leaving the app sets the note for a day later, so it comes even to someone who has never opened a ring.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(scheduleReminder(cancelIfNone: true));
  }

  Future<void> _load() async {
    final states = await _store.loadStates();
    final counts = await _store.shownCounts();
    for (final s in states) {
      s.shownCount = counts[s.key] ?? 0;
      _states[s.key] = s;
    }
    for (final e in counts.entries) {
      _states.putIfAbsent(e.key, () => RingState(e.key)).shownCount = e.value;
    }
    _batch = _batchFrom(await _store.loadMeta('batch'));
    ready = true;
    update();
    unawaited(_loadReminder());
  }

  Future<void> _loadReminder() async {
    final r = await NativeServices().storiesReminder();
    reminderEnabled = r.enabled;
    reminderAllowed = r.allowed;
    update();
  }

  RingState _stateOf(String key) => _states.putIfAbsent(key, () => RingState(key));

  bool _named(StoryRing ring) => ring.kind == StoryKind.collection || (ring.person!.name ?? '').trim().isNotEmpty;

  // The state as the picker should see it: a rest that is over has also ended the round.
  RingFacts _facts(StoryRing ring, int now) {
    final s = _stateOf(ring.key);
    var state = s;
    if (s.restUntil != 0 && s.restUntil <= now && s.shownCount > 0) {
      state = RingState(ring.key)
        ..builtAt = s.builtAt
        ..viewedAt = s.viewedAt
        ..lastCount = s.lastCount
        ..eligible = s.eligible
        ..lens = s.lens
        ..caption = s.caption
        ..frames = s.frames
        ..mutedUntil = s.mutedUntil;
    }
    return RingFacts(
      key: ring.key,
      isPerson: ring.kind == StoryKind.person,
      count: ring.count,
      named: _named(ring),
      state: state,
    );
  }

  List<StoryRing> _candidates(List<Person> people, CollectionsController collections) {
    return [
      for (final p in people)
        if (p.photoCount > 0) StoryRing.person(p),
      for (final c in collections.visible)
        if (storyCollectionIds.contains(c.id) && collections.statsFor(c.id).count > 0)
          StoryRing.collection(c, collections.statsFor(c.id).count),
    ];
  }

  StoryBatch _batchFrom(String? json) {
    if (json == null) return const StoryBatch();
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return StoryBatch(
        keys: [for (final k in m['keys'] as List) k as String],
        lit: {for (final k in m['lit'] as List) k as String},
        at: (m['at'] as num).toInt(),
      );
    } catch (_) {
      return const StoryBatch();
    }
  }

  void _saveBatch() {
    unawaited(_store.saveMeta('batch', jsonEncode({'at': _batch.at, 'keys': _batch.keys, 'lit': _batch.lit.toList()})));
  }

  // People and collections are found one after the other when the app starts: until both are, no batch is made or ended
  // (see StoryBatch.next), and the one there is stays as it was.
  bool _dataReady(CollectionsController collections) {
    if (Get.isRegistered<FacesController>() && Get.find<FacesController>().isLoadingPeople) return false;
    if (collections.isScoring) return false;
    final indexed = Get.isRegistered<NativeController>() && Get.find<NativeController>().totalEmbeddings > 0;
    return !indexed || collections.hasScored;
  }

  /// Whether [ring] has nothing new: it was opened (in the batch of the row), or it has nothing left to show.
  bool isSeen(StoryRing ring) => !_batch.isLit(_facts(ring, _now), _now);

  /// The rings to show: the batch of the row, the ones with something new first (people and collections taking turns,
  /// as the batch was made), then the ones that were opened, which stay where they are in the row. The batch is kept until
  /// it is used up (see [StoryBatch]). Empty until the saved state has been read.
  List<StoryRing> ringsFor(List<Person> people, CollectionsController collections) {
    if (!ready) return const [];
    final now = _now;
    final candidates = _candidates(people, collections);
    final byKey = {for (final r in candidates) r.key: r};
    final seed = now ~/ _day * 7919 + _refreshes;
    final dataReady = _dataReady(collections);
    final next = _batch.next(
      [for (final r in candidates) _facts(r, now)],
      now,
      seed,
      force: _newBatch,
      ready: dataReady,
    );
    if (dataReady) _newBatch = false;
    if (!identical(next, _batch)) {
      _batch = next;
      _saveBatch();
    }
    final inRow = [
      for (final k in _batch.keys)
        if (byKey[k] != null && _stateOf(k).mutedUntil <= now) byKey[k]!,
    ];
    final lit = [
      for (final r in inRow)
        if (!isSeen(r)) r,
    ];
    return [
      ...lit,
      for (final r in inRow)
        if (isSeen(r)) r,
    ];
  }

  /// The story of [ring]: its edition. A new one is made when it is due (and the ring has something it has not shown);
  /// an edition that has not been opened yet, or one that is being played again, is the same as before.
  Future<StoryEdition> loadEdition(StoryRing ring) async {
    final now = _now;
    final state = _stateOf(ring.key);
    if (!StoryRowPicker.unviewed(state) && StoryRowPicker.due(_facts(ring, now), now)) {
      final built = await (_building[ring.key] ??= _build(ring).whenComplete(() {
        _building.remove(ring.key);
      }));
      if (built != null) return built;
    }
    return _editionOf(state);
  }

  StoryEdition _editionOf(RingState s) =>
      s.hasEdition ? StoryEdition(frames: s.frames, caption: s.caption) : StoryEdition.empty;

  Future<StoryEdition?> _build(StoryRing ring) async {
    final now = _now;
    final state = _stateOf(ring.key);
    final items = await _poolOf(ring);
    if (items == null) return null;
    state
      ..eligible = items.length
      ..lastCount = ring.count;

    // A rest that is over starts a new round.
    if (state.restUntil != 0 && state.restUntil <= now) {
      await _store.clearShown(ring.key);
      state
        ..restUntil = 0
        ..shownCount = 0;
    }
    final shown = await _store.shownUris(ring.key);
    final pool = [
      for (final i in items)
        if (!shown.contains(i.uri)) i,
    ];

    final plan = StoryPlanner.plan(
      pool: pool,
      now: DateTime.fromMillisecondsSinceEpoch(now),
      seed: _seedFor(ring.key, now),
      lastLens: state.lens,
      ranked: ring.kind == StoryKind.collection,
    );
    if (plan == null) {
      // Nothing left that makes a story: the ring rests, and keeps its last one.
      state
        ..restUntil = now + restDays * _day
        ..shownCount = shown.length;
      await _store.saveState(state);
      update();
      return null;
    }

    await _store.addShown(ring.key, [for (final i in plan.picks) i.uri], now);
    state
      ..shownCount = shown.length + plan.picks.length
      ..frames = [for (final i in plan.picks) i.frame]
      ..lens = plan.lens
      ..caption = plan.caption
      ..builtAt = now
      ..lastCount = ring.count;
    await _store.saveState(state);
    update();
    return _editionOf(state);
  }

  int _seedFor(String key, int now) {
    var h = now ~/ _day;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  /// What a ring holds, without screenshots, with when each was taken. Null when it could not be read.
  Future<List<StoryItem>?> _poolOf(StoryRing ring) async {
    List<Map<String, dynamic>> raw;
    try {
      if (ring.kind == StoryKind.person) {
        raw = await NativeServices().personPhotos(ring.person!.id);
      } else {
        raw = await Get.find<CollectionsController>().membersForStory(ring.collection!, limit: 150);
      }
    } catch (e) {
      debugPrint('stories: could not read ${ring.key}: $e');
      return null;
    }
    // A ring that holds something but gives nothing back could not be read (the models are not ready, say): that is
    // not the same as having nothing left to show, so it is tried again later and does not rest.
    if (raw.isEmpty && ring.count > 0) return null;
    final seen = <String>{};
    final unique = [
      for (final m in raw)
        if (seen.add(m['path'] as String)) m,
    ];
    final dates = await NativeServices().mediaDates([for (final m in unique) m['path'] as String]);
    return [
      for (final m in unique)
        if (dates[m['path']]?.junk != true)
          StoryItem(
            uri: m['path'] as String,
            isVideo: m['isVideo'] as bool? ?? false,
            timestampMs: (m['timestampMs'] as num?)?.toInt() ?? 0,
            takenMs: dates[m['path']]?.takenMs ?? 0,
          ),
    ];
  }

  /// [ring]'s story was opened. The first time an edition is opened it greys the ring for 24 hours, and the note that
  /// says the stories have refreshed is set for then; playing it again changes nothing.
  Future<void> markViewed(StoryRing ring) async {
    final state = _stateOf(ring.key);
    if (!StoryRowPicker.unviewed(state)) return;
    final now = _now;
    state.viewedAt = now;
    await _store.saveState(state);
    update();
    unawaited(scheduleReminder());
  }

  /// Sets the "stories have refreshed" note for a day from now, with the rings that will be lit then (opened before or
  /// never), in place of the one waiting. When none will be, nothing is set, and with [cancelIfNone] the one waiting is
  /// taken away. Returns whether a note was set. Nothing is done before people and collections are known: rings worked
  /// out from some of them would leave the others out.
  Future<bool> scheduleReminder({bool cancelIfNone = false}) async {
    if (!ready || !reminderEnabled) return false;
    if (!Get.isRegistered<CollectionsController>() || !_dataReady(Get.find<CollectionsController>())) return false;
    final at = _now + _day;
    final rings = _reminderRings(at);
    if (rings == '[]') {
      if (cancelIfNone) unawaited(NativeServices().storiesReminder(cancel: true));
      return false;
    }
    await NativeServices().storiesReminder(atMs: at, ringsJson: rings);
    return true;
  }

  /// [scheduleReminder] once people and collections are known again after an index scan (they are looked at again when
  /// one ends), trying for a couple of minutes.
  Future<void> scheduleReminderWhenReady() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (await scheduleReminder()) return;
    }
  }

  /// Who will be in the row of rings of the "stories have refreshed" note when it comes at [atMs]: the rings that are
  /// lit then (up to eight), as text for the native side, which makes the note later without the app running.
  String _reminderRings(int atMs, {bool litOnly = true}) {
    if (!Get.isRegistered<FacesController>() || !Get.isRegistered<CollectionsController>()) return '[]';
    final collections = Get.find<CollectionsController>();
    final people = Get.find<FacesController>().people;
    final candidates = _candidates(people, collections);
    final byKey = {for (final r in candidates) r.key: r};
    // The rings of the row now, or the ones that will be lit at [atMs] (the next batch).
    final chosen = litOnly
        ? [
            for (final p in StoryRowPicker.pick(
              [for (final r in candidates) _facts(r, atMs)],
              atMs,
              atMs ~/ _day * 7919,
              keepGreys: 0,
            ))
              if (p.lit) byKey[p.facts.key]!,
          ]
        : ringsFor(people, collections);
    final out = <Map<String, Object>>[];
    for (final ring in chosen) {
      if (ring.kind == StoryKind.person) {
        // A person without a name sends an empty one: the note shows their ring but does not read "Unnamed" out.
        out.add({'title': (ring.person!.name ?? '').trim(), 'faceId': ring.person!.coverFaceId, 'person': true});
      } else {
        final cover = collections.selectedCover(ring.collection!.id);
        out.add({
          'title': ring.title,
          'person': false,
          if (cover != null) 'cover': cover.uri,
          if (cover != null) 'video': cover.isVideo,
        });
      }
    }
    return jsonEncode(out);
  }

  /// Shows the "stories have refreshed" note now, with the rings that are in the row, to see what it looks like.
  /// Returns what happened, in words.
  Future<String> sendTest() async {
    final shown = await NativeServices().storiesReminderTest(_reminderRings(_now, litOnly: false));
    return shown ? 'Sent. Look in your notifications.' : 'Allow notifications for this app to see it.';
  }

  /// Sets [ring] aside ("Not now") for [mutedDays] days.
  Future<void> setAside(StoryRing ring) async {
    final state = _stateOf(ring.key);
    state.mutedUntil = _now + mutedDays * _day;
    await _store.saveState(state);
    update();
  }

  /// A new edition now, by hand: the rings that were opened are due again at once (with pictures that have not been
  /// shown), people and collections are looked at again, and the rings are chosen again. Returns whether there is
  /// anything new to see afterwards.
  Future<bool> refreshStories() async {
    if (refreshing) return true;
    refreshing = true;
    update();
    _refreshes++;
    _newBatch = true;
    final now = _now;
    // A copy of the list: a ring being made ready elsewhere can add its state while this waits for the store.
    for (final s in _states.values.toList()) {
      if (s.hasEdition && !StoryRowPicker.unviewed(s) && now - s.viewedAt < _day) {
        // Opened a day ago, as far as the ring can tell (and made before that).
        s
          ..builtAt = now - 2 * _day
          ..viewedAt = now - _day;
        await _store.saveState(s);
      }
    }
    final faces = Get.find<FacesController>();
    final collections = Get.find<CollectionsController>();
    try {
      await Future.wait<void>([faces.refreshPeople(), collections.refreshStats()]).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('stories: refresh could not look again: $e');
    }
    refreshing = false;
    update();
    return ringsFor(faces.people, collections).any((r) => !isSeen(r));
  }

  /// Turns the "stories have refreshed" note on or off. Turning it on asks for the notification permission (Android 13
  /// and later) and stays off if it is refused. Returns whether it is on now.
  Future<bool> setReminder(bool on) async {
    if (on) {
      // Asked as every permission is (see askPermission): it says why if it is turned down.
      final allowed = await askPermission(
        AppPermission.notifications,
        purpose: 'tell you when your stories have refreshed',
      );
      if (!allowed) {
        await _loadReminder();
        return false;
      }
    }
    final r = await NativeServices().storiesReminder(enabled: on);
    reminderEnabled = r.enabled;
    reminderAllowed = r.allowed;
    update();
    return reminderEnabled;
  }

  /// The picture of [frame], sized for a phone screen. Null if it cannot be read.
  Future<Uint8List?> frameBytes(StoryFrame frame) async {
    try {
      if (frame.isVideo) {
        return await NativeServices().loadVideoThumbnail(
          uri: frame.uri,
          timestampMs: frame.timestampMs,
          maxDimension: 1600,
        );
      }
      return await NativeServices().loadThumbnail(uri: frame.uri, isVideo: false, size: 1280);
    } catch (_) {
      return null;
    }
  }
}
