import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/db/indexed_folder_db_helper.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/models/default_collections.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/tokanizer/clip_tokenizer.dart';

// Owns everything about collections (see collections_plan.md): the list the
// Collections tab and the Search tab's chip row show, each one's count/cover
// from the last scoring pass, and the one collection currently open.
//
// Every collection - built-in or the user's own - can be edited, hidden or
// deleted. Built-ins live in code, so for them those are stored as small
// overrides (see IndexedFolderDbHelper's collections section): "deleted"
// just means off the list until restored from Settings.
class CollectionsController extends GetxController {
  // Cached query embeddings are only valid for the model that produced
  // them - bump this if the search model is ever swapped (or how a text or a
  // photo is prepared for it changes). A photo collection's own seed vector
  // is checked against it too.
  static const modelVersion = 'mobileclip-s0-apple-2024-v1';
  static const _modelVersion = modelVersion;
  static const _embeddingsKey = 'collection_embeddings';
  static const int _memberLimit = 200;

  static const int _stateVisible = 0;
  static const int _stateHidden = 1;
  static const int _stateDeleted = 2;

  // A freshly saved collection's card shows its "finding matches" animation
  // for at least this long, so a quick sync doesn't flash past unseen.
  static const _minSyncDisplay = Duration(milliseconds: 1100);

  final _db = IndexedFolderDbHelper.instance;

  List<SmartCollection> _user = [];
  List<SmartCollection> _builtIns = [];
  final Map<String, int> _state = {};
  final Set<String> _edited = {};

  /// What the tab and chip row show: the user's own first (newest first),
  /// then the built-ins, fullest first once counts are known.
  List<SmartCollection> visible = [];
  List<SmartCollection> hiddenCollections = [];
  int deletedBuiltInCount = 0;

  /// True if any built-in has been edited, hidden or deleted - i.e. there's
  /// something for "Restore default collections" to undo.
  bool get hasCustomizedBuiltIns =>
      _edited.isNotEmpty ||
      deletedBuiltInCount > 0 ||
      _builtIns.any((c) => _stateOf(c.id) == _stateHidden);

  final Map<String, CollectionStats> stats = {};
  // Card covers, keyed by CollectionCover.cacheKey.
  final Map<String, Uint8List> coverBytes = {};
  // How large (long side, px) each of them was loaded: a tile asks for the size it needs, and a cover that was
  // loaded smaller (for a small tile, or a chip) is loaded again bigger for a big tile.
  final Map<String, int> _coverSize = {};
  final Map<String, Future<Uint8List?>> _coverLoads = {};
  bool isScoring = false;
  bool _statsLoadedOnce = false;
  bool _refreshAgain = false;
  bool get hasScored => _statsLoadedOnce;

  // Collections being (re)computed right now - their cards show the
  // "finding matches" animation.
  final Set<String> syncing = {};

  // Progress of the one-time (or resync) work of embedding every collection's
  // prompts - the slow part of the first scoring pass. 0 total means nothing
  // needed embedding, just the (fast) scoring itself.
  int setupDone = 0;
  int setupTotal = 0;

  // query embeddings: id -> {sig, emb}
  final Map<String, Map<String, dynamic>> _embeddingCache = {};

  // The collection currently open.
  SmartCollection? active;
  List<Map<String, dynamic>> members = [];
  final Map<String, Uint8List> memberThumbs = {};
  bool isLoadingMembers = false;
  // Members are known but their thumbnails are still arriving - tiles show a
  // loading placeholder instead of an error icon until this clears.
  bool isLoadingThumbs = false;
  int _openToken = 0;

  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  CollectionStats statsFor(String id) => stats[id] ?? CollectionStats.empty;

  int _stateOf(String id) => _state[id] ?? _stateVisible;

  bool isEdited(String id) => _edited.contains(id);

  // ---- Cover ----

  // A collection's cover isn't always its single best match: it rotates
  // through its top few, changing once a day (staggered per collection so
  // they don't all flip together). Stable within a day, fresh on return.
  CollectionCover? selectedCover(String id) {
    final covers = statsFor(id).covers;
    if (covers.isEmpty) return null;
    final day = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final salt = id.codeUnits.fold<int>(0, (a, b) => a + b);
    return covers[(day + salt) % covers.length];
  }

  Uint8List? coverFor(String id) {
    final cover = selectedCover(id);
    return cover == null ? null : coverBytes[cover.cacheKey];
  }

  /// The photos of a collection's stack on its tile: the cover first (the one of the day), then
  /// two more of its best matches.
  List<CollectionCover> stackCovers(String id) {
    final covers = statsFor(id).covers;
    if (covers.isEmpty) return const [];
    final day = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final salt = id.codeUnits.fold<int>(0, (a, b) => a + b);
    final start = (day + salt) % covers.length;
    return [for (var k = 0; k < math.min(3, covers.length); k++) covers[(start + k) % covers.length]];
  }

  /// Whether any photo on the stack came in with the latest scan.
  bool hasNewCover(String id, bool Function(String uri) isNew) => stackCovers(id).any((c) => isNew(c.uri));

  // Built-ins with no matches are tucked away at the end of the tab; this opens that group.
  bool showEmpty = false;

  void toggleShowEmpty() {
    showEmpty = !showEmpty;
    update();
  }

  // Larger pictures for the featured card at the top of the Collections tab, by the cover's
  // cache key (a collection's cover changes with the day and with the index).
  final Map<String, Uint8List> _heroBytes = {};

  Uint8List? heroBytesFor(String id) {
    final cover = selectedCover(id);
    return cover == null ? null : (_heroBytes[cover.cacheKey] ?? coverBytes[cover.cacheKey]);
  }

  /// The collections that take turns on the featured card: those with something in them and a
  /// cover (known from the scores, not from the picture having arrived, so the set does not
  /// shuffle while pictures come in), the ones that just got new photos first, then others. A different order each day
  /// (the same all day, so it does not jump about on every visit).
  List<SmartCollection> heroCandidates({required bool Function(String uri) isNew, int max = 5}) {
    final pool = [
      for (final c in visible)
        if (!c.isEveryday && statsFor(c.id).count > 0 && selectedCover(c.id) != null) c,
    ];
    if (pool.isEmpty) return const [];
    final day = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    pool.shuffle(math.Random(day));
    final fresh = [
      for (final c in pool)
        if (hasNewCover(c.id, isNew)) c,
    ];
    final rest = [
      for (final c in pool)
        if (!hasNewCover(c.id, isNew)) c,
    ];
    return [...fresh, ...rest].take(max).toList();
  }

  bool _heroRunning = false;

  Future<void> _loadHeroImages() async {
    if (_heroRunning) return;
    _heroRunning = true;
    try {
      await _loadHeroImagesOnce();
    } finally {
      _heroRunning = false;
    }
  }

  Future<void> _loadHeroImagesOnce() async {
    final native = Get.isRegistered<NativeController>() ? Get.find<NativeController>() : null;
    final list = heroCandidates(isNew: native?.isInLatestScan ?? (_) => false);
    for (final c in list) {
      final cover = selectedCover(c.id);
      if (cover == null || _heroBytes.containsKey(cover.cacheKey)) continue;
      try {
        _heroBytes[cover.cacheKey] = await NativeServices().loadThumbnail(
          uri: cover.uri,
          isVideo: cover.isVideo,
          timestampMs: cover.timestampMs,
          size: 900,
        );
        _updateSoon();
      } catch (_) {
        // The smaller cover is used instead.
      }
    }
  }

  // Pictures arrive one by one (dozens of them): the tab is told about them a few times a
  // second, not once per picture.
  Timer? _notifyTimer;

  void _updateSoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 150), () {
      _notifyTimer = null;
      update();
    });
  }

  @override
  void onClose() {
    _notifyTimer?.cancel();
    super.onClose();
  }

  // ---- Loading ----

  Future<void> load() async {
    await _reload(refresh: false);
    await _loadEmbeddingCache();
    await refreshStats();
  }

  Future<void> _reload({bool refresh = true}) async {
    try {
      _applyRows(await _db.getCollectionRows());
    } catch (e) {
      debugPrint('Failed to load collections: $e');
    }
    _rebuildLists();
    update();
    if (refresh) unawaited(refreshStats());
  }

  void _applyRows(List<Map<String, Object?>> rows) {
    final rowsById = {for (final r in rows) r['id'] as String: r};
    _state.clear();
    _edited.clear();

    final user = <SmartCollection>[];
    for (final r in rows) {
      if ((r['isBuiltIn'] as int? ?? 0) == 0) {
        final c = SmartCollection.fromRow(r);
        user.add(c);
        _state[c.id] = r['hidden'] as int? ?? _stateVisible;
      }
    }
    user.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _user = user;

    _builtIns = [
      for (final d in defaultCollections)
        () {
          final r = rowsById[d.id];
          _state[d.id] = r == null ? _stateVisible : (r['hidden'] as int? ?? _stateVisible);
          if (r == null) return d;
          final prompts = (jsonDecode(r['prompts'] as String? ?? '[]') as List).cast<String>();
          if (prompts.isEmpty) return d; // just a hidden/deleted marker
          _edited.add(d.id);
          return d.copyWith(
            name: r['name'] as String?,
            prompts: prompts,
            // A rename or sensitivity tweak stores the ensemble unchanged - keep
            // its short phrase ("pet") instead of falling back to the first
            // long prompt, which would change what "why this matched" and the
            // edit sheet show.
            explainQuery: listEquals(prompts, d.prompts) ? d.explainQuery : null,
            contentMode: r['contentMode'] as String?,
            sensitivity: (r['sensitivity'] as num?)?.toDouble(),
          );
        }(),
    ];
  }

  void _rebuildLists() {
    final builtIns = _builtIns.where((c) => _stateOf(c.id) == _stateVisible).toList();
    // Once counts are known, ones with something in them come first.
    builtIns.sort((a, b) => statsFor(b.id).count.compareTo(statsFor(a.id).count));
    visible = [..._user.where((c) => _stateOf(c.id) == _stateVisible), ...builtIns];
    hiddenCollections = [
      ..._user.where((c) => _stateOf(c.id) == _stateHidden),
      ..._builtIns.where((c) => _stateOf(c.id) == _stateHidden),
    ];
    deletedBuiltInCount = _builtIns.where((c) => _stateOf(c.id) == _stateDeleted).length;
  }

  // ---- Query embeddings ----

  Future<void> _loadEmbeddingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_embeddingsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map;
      _embeddingCache
        ..clear()
        ..addAll(decoded.map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))));
    } catch (e) {
      debugPrint('Failed to load collection embeddings: $e');
    }
  }

  Future<void> _saveEmbeddingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_embeddingsKey, jsonEncode(_embeddingCache));
    } catch (e) {
      debugPrint('Failed to save collection embeddings: $e');
    }
  }

  String _signature(SmartCollection c) => '$_modelVersion|${c.embeddingSignature}';

  bool _hasValidEmbedding(SmartCollection c) {
    if (c.seedEmbedding != null) return c.seedModel == _modelVersion;
    final cached = _embeddingCache[c.id];
    return cached != null && cached['sig'] == _signature(c);
  }

  List<double> _normalized(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    return norm == 0 ? v : [for (final x in v) x / norm];
  }

  // Each prompt embedded on its own, normalized, then averaged and
  // normalized again - averaging several phrasings of the same idea is
  // noticeably more robust than any single one.
  Future<List<double>> _embeddingFor(SmartCollection c) async {
    // A photo-seeded collection carries its own embedding - nothing to encode - as long as the current search
    // model made it.
    if (c.seedEmbedding != null && c.seedModel == _modelVersion) return c.seedEmbedding!;
    if (c.isPhotos) return _seedAgain(c);

    final cached = _embeddingCache[c.id];
    if (cached != null && cached['sig'] == _signature(c)) {
      return (cached['emb'] as List).cast<num>().map((e) => e.toDouble()).toList();
    }

    final result = await _embedPrompts(c.prompts);
    if (result == null) throw StateError('No prompts could be embedded for ${c.id}');
    _embeddingCache[c.id] = {'sig': _signature(c), 'emb': result};
    unawaited(_saveEmbeddingCache());
    return result;
  }

  // The prompts' vectors averaged (null when none could be made).
  Future<List<double>?> _embedPrompts(List<String> prompts) async {
    final tokenizer = await ClipTokenizer.load();
    List<double>? sum;
    for (final prompt in prompts) {
      final e = _normalized(await NativeServices().encodeText(tokenizer.tokenize(prompt)));
      if (e.isEmpty) continue;
      sum = sum == null ? e : [for (var i = 0; i < sum.length; i++) sum[i] + e[i]];
    }
    return sum == null ? null : _normalized(sum);
  }

  // ---- Preview (the new-collection sheet) ----

  // The vectors of the words and photos previewed lately, so editing one phrase, or switching photos and videos,
  // does not run the model again for the rest.
  final Map<String, List<double>> _previewVectors = {};

  /// What a collection made of these words (or, with [seedUri], of looking like that photo or video frame) would
  /// hold now, found the same way a saved collection's members are: how many items, the best few, and the people
  /// in them. Null when it cannot be worked out (nothing indexed, the search model not ready).
  Future<CollectionPreview?> previewCollection({
    List<String> prompts = const [],
    String? seedUri,
    int? seedTimestampMs,
    String contentMode = 'both',
    List<int> personIds = const [],
    int shown = 5,
  }) async {
    try {
      final words = [
        for (final p in prompts)
          if (p.trim().isNotEmpty) p.trim(),
      ];
      // Only people, no words: what a collection made of them scores against (see createCollection).
      if (seedUri == null && words.isEmpty) words.add('a photo');
      final key = seedUri != null ? 'photo|$seedUri@$seedTimestampMs' : 'words|${words.join('|')}';
      final embedding = _previewVectors[key] ??
          (seedUri != null
              ? _normalized(await NativeServices().encodeImage(uri: seedUri, timestampMs: seedTimestampMs))
              : await _embedPrompts(words) ?? const <double>[]);
      // Nothing came out (the model not ready, say): not kept, so it is tried again next time.
      if (embedding.isEmpty) return null;
      _previewVectors[key] = embedding;
      if (_previewVectors.length > 40) _previewVectors.remove(_previewVectors.keys.first);

      final spec = {
        'id': 'preview',
        'embedding': embedding,
        'contentMode': contentMode,
        'k': SmartCollection.defaultSensitivity,
        if (personIds.isNotEmpty) 'personIds': personIds,
      };
      final scored = await NativeServices().scoreCollections([spec]);
      final count = scored.isEmpty ? 0 : (scored.first['count'] as num? ?? 0).toInt();
      if (count == 0) return const CollectionPreview(count: 0, items: [], people: []);
      // The best few to show, and enough of the rest to tell who is in them.
      final members = await NativeServices().collectionMembers(spec, limit: 400);
      final items = [for (final m in members.take(shown)) CollectionCover.fromMap(m)];
      List<({int personId, int count})> people = const [];
      try {
        people = await NativeServices().peopleIn([
          for (final m in members)
            if ((m['videoUri'] as String? ?? '').isNotEmpty) m['videoUri'] as String else m['path'] as String,
        ]);
      } catch (_) {
        // No faces to name: the preview is shown without them.
      }
      return CollectionPreview(count: count, items: items, people: people);
    } catch (e) {
      debugPrint('Collection preview failed: $e');
      return null;
    }
  }

  // A photo collection saved with the previous search model: its photo is embedded again with the current one and
  // kept (so this happens once). If the photo can no longer be read there is nothing to do but leave the collection
  // empty - the old vector means nothing to the new model.
  Future<List<double>> _seedAgain(SmartCollection c) async {
    final uri = c.seedUri;
    if (uri == null) throw StateError('Collection ${c.id} has no photo to embed again');
    final fresh = _normalized(
      await NativeServices().encodeImage(uri: uri, timestampMs: c.seedTimestampMs ?? 0),
    );
    if (fresh.isEmpty) throw StateError('The photo of ${c.id} could not be embedded again');
    final updated = c.copyWith(seedEmbedding: fresh, seedModel: _modelVersion);
    await _db.upsertCollection(updated, hiddenState: _stateOf(c.id));
    await _reload(refresh: false);
    return fresh;
  }

  Future<Map<String, dynamic>> _specFor(SmartCollection c) async => {
    'id': c.id,
    'embedding': await _embeddingFor(c),
    'contentMode': c.contentMode,
    'k': c.sensitivity,
    if (c.personIds.isNotEmpty) 'personIds': c.personIds,
  };

  // Throws away every cached query embedding and score and redoes them from
  // scratch - Settings' "Resync collections", for checking that the heavy
  // first-run path is fine and for recovering from anything odd.
  Future<void> resyncAll() async {
    if (isScoring) return;
    _embeddingCache.clear();
    stats.clear();
    coverBytes.clear();
    _coverSize.clear();
    _heroBytes.clear();
    await _saveEmbeddingCache();
    update();
    await refreshStats();
  }

  // ---- Counts and covers ----

  // Cheap enough to call whenever the index changes (after a scan, on first
  // open) - one native pass scores every visible collection at once.
  Future<void> refreshStats() async {
    if (isScoring) {
      // Something changed mid-pass (a scan finished while one was
      // running) - go again once this one's done rather than drop it.
      _refreshAgain = true;
      return;
    }
    final native = Get.find<NativeController>();
    if (native.totalEmbeddings == 0) {
      // Nothing is indexed (it was just cleared, say): the counts and covers kept
      // from before belong to an index that is gone, and would show collections
      // full of photos that open onto nothing.
      stats.clear();
      coverBytes.clear();
      _coverSize.clear();
      _heroBytes.clear();
      _rebuildLists();
    }
    if (!native.modelsReady || native.totalEmbeddings == 0) {
      _statsLoadedOnce = true;
      update();
      return;
    }

    isScoring = true;
    setupDone = 0;
    setupTotal = visible.where((c) => !_hasValidEmbedding(c)).length;
    update();
    try {
      final specs = <Map<String, dynamic>>[];
      for (final c in visible) {
        final needed = !_hasValidEmbedding(c);
        try {
          specs.add(await _specFor(c));
        } catch (e) {
          debugPrint('Skipping ${c.id}: $e');
        }
        if (needed) {
          setupDone++;
          update();
        }
      }

      final scored = await NativeServices().scoreCollections(specs);
      stats.clear();
      for (final s in scored) {
        stats[s['id'] as String] = _statsFromMap(s);
      }
      _statsLoadedOnce = true;
      _rebuildLists();
    } on ModelsNotReadyError {
      // Nothing to score against yet - the tab just shows empty cards.
    } catch (e) {
      debugPrint('Collection scoring failed: $e');
    } finally {
      isScoring = false;
      update();
    }
    if (_refreshAgain) {
      _refreshAgain = false;
      return refreshStats();
    }
    unawaited(_loadCovers());
  }

  CollectionStats _statsFromMap(Map<String, dynamic> s) => CollectionStats(
    count: s['count'] as int? ?? 0,
    covers: (s['covers'] as List<dynamic>? ?? const [])
        .map((e) => CollectionCover.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList(),
  );

  // Just this one collection - what a freshly saved or edited collection
  // uses so its card can animate on its own instead of waiting on a full
  // pass over all of them.
  Future<void> _syncOne(SmartCollection c) async {
    final started = DateTime.now();
    syncing.add(c.id);
    update();
    try {
      final native = Get.find<NativeController>();
      if (native.modelsReady && native.totalEmbeddings > 0) {
        final scored = await NativeServices().scoreCollections([await _specFor(c)]);
        if (scored.isNotEmpty) stats[c.id] = _statsFromMap(scored.first);
        _rebuildLists();
      } else if (native.totalEmbeddings == 0) {
        stats.remove(c.id);
        _rebuildLists();
      }
    } on ModelsNotReadyError {
      // Card just stays empty.
    } catch (e) {
      debugPrint('Sync failed for ${c.id}: $e');
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minSyncDisplay) await Future<void>.delayed(_minSyncDisplay - elapsed);
    syncing.remove(c.id);
    update();
    unawaited(_loadCovers());
  }

  @visibleForTesting
  Future<void> loadCoversNow() => _loadCovers();

  // One pass at a time: a scan finishing while pictures are still arriving asks for another
  // pass afterwards instead of loading the same pictures twice at once.
  bool _coversRunning = false;
  bool _coversAgain = false;

  Future<void> _loadCovers() async {
    if (_coversRunning) {
      _coversAgain = true;
      return;
    }
    _coversRunning = true;
    try {
      do {
        _coversAgain = false;
        await _loadCoversPass();
      } while (_coversAgain);
    } finally {
      _coversRunning = false;
    }
  }

  Future<void> _loadCoversPass() async {
    // Only what is shown without a tile asking for it: the featured card (first, as it is at the top of the
    // Collections tab). The tiles of the tab, and the story rings of the Search tab, load their own cover as
    // they come on screen.
    unawaited(_loadHeroImages());
    // The last pictures are not left waiting for the timer.
    _notifyTimer?.cancel();
    _notifyTimer = null;
    update();
  }

  /// The cover of collection [id] with its long side at least [size] px: the one in memory when it was loaded
  /// that large already, else loaded now (null when the collection has no cover, or it cannot be read). A tile
  /// asks for the size that fits it, so a big tile of the mosaic is not given a small picture.
  Future<Uint8List?> loadCover(String id, int size) {
    final cover = selectedCover(id);
    if (cover == null) return Future.value(null);
    final have = coverBytes[cover.cacheKey];
    if (have != null && (_coverSize[cover.cacheKey] ?? 0) >= size) return Future.value(have);
    final key = '${cover.cacheKey}@$size';
    return _coverLoads[key] ??= _fetchCover(cover, size).whenComplete(() => _coverLoads.remove(key));
  }

  Future<Uint8List?> _fetchCover(CollectionCover cover, int size) async {
    try {
      final bytes = await _loadThumb(cover.uri, cover.isVideo, cover.timestampMs, size: size);
      // Another, bigger request may have finished first: the bigger one stays.
      if ((_coverSize[cover.cacheKey] ?? 0) < size) {
        coverBytes[cover.cacheKey] = bytes;
        _coverSize[cover.cacheKey] = size;
        _updateSoon();
      }
      return coverBytes[cover.cacheKey] ?? bytes;
    } catch (_) {
      // A missing picture just leaves that tile with its icon.
      return null;
    }
  }

  Future<Uint8List> _loadThumb(String uri, bool isVideo, int timestampMs, {int? size}) {
    // Small, not full-screen sized: these only back tiles and cards (a video's
    // is also its poster in the viewer for a moment, hence a bit larger).
    return NativeServices().loadThumbnail(
      uri: uri,
      isVideo: isVideo,
      timestampMs: timestampMs,
      size: size ?? (isVideo ? 640 : 420),
    );
  }

  // ---- Create / edit ----

  /// Turns the search that's currently showing into a collection. A
  /// personIds override lets the caller pass the search's own mentioned
  /// people explicitly (search_tab.dart snapshots them onto the controller
  /// right when the search runs, since searchTextController may have since
  /// been edited for a *different*, not-yet-run search by the time this is
  /// called) - falls back to whatever's on the controller now otherwise.
  Future<SmartCollection?> saveSearchAsCollection({
    required String name,
    List<int>? personIds,
  }) async {
    final native = Get.find<NativeController>();
    final query = native.lastTextQuery;
    final ids = personIds ?? native.lastMentionedPersonIds;
    // A pure "@Raseel" mention with no other words is still a real,
    // saveable search - only bail out if there's neither text nor anyone
    // mentioned at all.
    if ((query == null || query.trim().isEmpty) && ids.isEmpty) return null;
    return createCollection(
      name: name,
      query: query?.trim() ?? '',
      contentMode: native.getContentModeString(contentMode: native.searchContentMode),
      personIds: ids,
    );
  }

  /// Turns the image search that's currently showing (a picked photo, a
  /// photo from the viewer, or a video frame) into a photo-seeded collection.
  Future<SmartCollection?> saveImageSearchAsCollection({required String name}) async {
    final native = Get.find<NativeController>();
    final uri = native.lastImageSeedUri;
    if (uri == null) return null;
    return createPhotoCollection(
      name: name,
      uri: uri,
      timestampMs: native.lastImageSeedTimestampMs,
      contentMode: native.getContentModeString(contentMode: native.searchContentMode),
    );
  }

  /// A collection of the photos and videos that look like this one (or this frame of a video).
  Future<SmartCollection?> createPhotoCollection({
    required String name,
    required String uri,
    int? timestampMs,
    String contentMode = 'both',
  }) async {
    final List<double> embedding;
    try {
      embedding = _normalized(await NativeServices().encodeImage(uri: uri, timestampMs: timestampMs));
    } catch (e) {
      debugPrint('Could not embed the seed photo: $e');
      return null;
    }
    if (embedding.isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final collection = SmartCollection(
      id: 'user_$now',
      name: name.trim().isEmpty ? 'Similar photos' : name.trim(),
      prompts: const ['photos like the one you saved'],
      icon: Icons.photo_library_outlined,
      contentMode: contentMode,
      createdAt: now,
      kind: SmartCollection.kindPhotos,
      seedEmbedding: embedding,
      seedUri: uri,
      seedTimestampMs: timestampMs,
      seedModel: _modelVersion,
    );
    return _addAndSync(collection);
  }

  // The card appears at once (marked as syncing, so it plays its "finding
  // matches" animation) and the database write and scoring happen behind it.
  Future<SmartCollection> createCollection({
    required String name,
    required String query,
    String contentMode = 'both',
    List<int> personIds = const [],
    List<String> morePrompts = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // A pure "@Raseel" collection has no real topic to embed - CLIP needs
    // *something* to score against, so this falls back to a generic prompt
    // rather than embedding an empty string. The person filter (applied
    // natively - see _specFor) still does the actual narrowing; this just
    // keeps the z-score step from operating on a meaningless embedding.
    final effectiveQuery = query.trim().isEmpty ? 'a photo' : query.trim();
    return _addAndSync(
      SmartCollection(
        id: 'user_$now',
        name: name.trim().isEmpty ? query : name.trim(),
        // Other ways of saying the same thing are averaged in: steadier than one phrase alone.
        prompts: [
          effectiveQuery,
          for (final p in morePrompts)
            if (p.trim().isNotEmpty) p.trim(),
        ],
        contentMode: contentMode,
        createdAt: now,
        personIds: personIds,
      ),
    );
  }

  Future<SmartCollection> _addAndSync(SmartCollection collection) async {
    _user = [collection, ..._user];
    _state[collection.id] = _stateVisible;
    syncing.add(collection.id);
    _rebuildLists();
    update();

    await _db.upsertCollection(collection);
    unawaited(_syncOne(collection));
    return collection;
  }

  Future<void> updateCollection(SmartCollection updated) async {
    final before = [..._user, ..._builtIns].firstWhereOrNull((c) => c.id == updated.id);
    await _db.upsertCollection(updated, hiddenState: _stateOf(updated.id));
    await _reload(refresh: false);
    final fresh = [..._user, ..._builtIns].firstWhereOrNull((c) => c.id == updated.id);
    if (fresh == null) return;

    // A rename changes nothing about what matches - only redo the work (and
    // replay the card's "finding matches" animation) when the query, content
    // filter or sensitivity actually changed.
    final matchesChanged = before == null ||
        before.embeddingSignature != fresh.embeddingSignature ||
        before.contentMode != fresh.contentMode ||
        before.sensitivity != fresh.sensitivity ||
        !listEquals(before.personIds, fresh.personIds);

    if (active?.id == updated.id) {
      if (matchesChanged) {
        unawaited(openCollection(fresh));
      } else {
        active = fresh;
        update();
      }
    }
    if (matchesChanged) unawaited(_syncOne(fresh));
  }

  Future<void> hideCollection(String id) {
    // Hidden from inside its own screen: leave it (the screen pops when there
    // is no active collection) rather than sit on something that's gone.
    if (active?.id == id) closeCollection();
    return _setState(id, _stateHidden);
  }

  Future<void> unhideAll() async {
    for (final c in [...hiddenCollections]) {
      await _db.setCollectionState(c.id, _stateVisible, isBuiltIn: c.isBuiltIn);
    }
    await _reload();
  }

  // A collection you made is deleted for real. A built-in can't be (it ships
  // with the app), so it's just taken off the list until Settings restores it.
  Future<void> deleteCollection(String id) async {
    final isBuiltIn = _builtIns.any((c) => c.id == id);
    if (active?.id == id) closeCollection();
    stats.remove(id);
    if (isBuiltIn) {
      await _setState(id, _stateDeleted);
    } else {
      _embeddingCache.remove(id);
      unawaited(_saveEmbeddingCache());
      await _db.deleteCollection(id);
      await _reload(refresh: false);
    }
  }

  /// Undoes edits to one built-in (keeps nothing else about it).
  Future<void> resetBuiltIn(String id) async {
    await _db.deleteCollection(id);
    await _reload();
  }

  /// Every built-in back to how it ships - Settings' "Restore default
  /// collections". Collections you made are untouched.
  Future<void> restoreDefaults() async {
    await _db.resetBuiltIns();
    await _reload();
  }

  Future<void> _setState(String id, int state) async {
    final isBuiltIn = _builtIns.any((c) => c.id == id);
    await _db.setCollectionState(id, state, isBuiltIn: isBuiltIn);
    await _reload(refresh: false);
  }

  // ---- Choosing several (for exporting) ----

  bool selecting = false;
  final Set<String> selectedIds = {};

  void startSelecting([String? first]) {
    selecting = true;
    selectedIds
      ..clear()
      ..addAll(first == null ? const <String>[] : [first]);
    update();
  }

  void toggleSelected(String id) {
    if (!selectedIds.remove(id)) selectedIds.add(id);
    update();
  }

  void stopSelecting() {
    selecting = false;
    selectedIds.clear();
    update();
  }

  /// Every member of [collection] (not just the first screenful), for exporting. Empty if the
  /// models are not ready.
  Future<List<Map<String, dynamic>>> allMembersOf(SmartCollection collection) async {
    try {
      return await NativeServices().collectionMembers(await _specFor(collection), limit: 100000);
    } on ModelsNotReadyError {
      return const [];
    }
  }

  /// The best matches of [collection], for a story: a few dozen, not the whole collection. Empty
  /// if the models are not ready.
  Future<List<Map<String, dynamic>>> membersForStory(SmartCollection collection, {int limit = 30}) async {
    try {
      return await NativeServices().collectionMembers(await _specFor(collection), limit: limit);
    } on ModelsNotReadyError {
      return const [];
    } catch (e) {
      debugPrint('Failed to load story members: $e');
      return const [];
    }
  }

  // ---- Opening one ----

  Future<void> openCollection(SmartCollection collection) async {
    final token = ++_openToken;
    active = collection;
    members = [];
    memberThumbs.clear();
    isLoadingMembers = true;
    isLoadingThumbs = false;
    update();

    try {
      final found = await NativeServices().collectionMembers(
        await _specFor(collection),
        limit: _memberLimit,
      );
      if (token != _openToken) return;
      members = found;
    } on ModelsNotReadyError {
      // Left empty - the screen says there's nothing here yet.
    } catch (e) {
      debugPrint('Failed to load collection members: $e');
    }
    if (token != _openToken) return;
    isLoadingMembers = false;
    isLoadingThumbs = members.isNotEmpty;
    update();

    // Thumbnails fill in progressively (the grid shows a loading placeholder
    // until each arrives) rather than the screen waiting on up to 200 decodes.
    // Ones seen before come straight from the in-memory cache; the rest load
    // a few at a time, in list order, so the top of the grid fills first.
    var sinceUpdate = 0;
    final pending = <Map<String, dynamic>>[];
    // What the latest scan indexed (tagged New) shows first in the grid, so it loads first too.
    for (final item in Get.find<NativeController>().newFirst(members)) {
      final key = memberKey(item);
      final cached = _thumbCache.remove(key);
      if (cached != null) {
        _thumbCache[key] = cached; // refresh recency
        memberThumbs[key] = cached;
      } else {
        pending.add(item);
      }
    }
    if (memberThumbs.isNotEmpty) update();

    var next = 0;
    Future<void> worker() async {
      while (token == _openToken && next < pending.length) {
        final item = pending[next++];
        final key = memberKey(item);
        try {
          final bytes = await _loadThumb(
            item['path'] as String,
            item['isVideo'] as bool? ?? false,
            (item['timestampMs'] as num?)?.toInt() ?? 0,
          );
          _rememberThumb(key, bytes);
          if (token != _openToken) return;
          memberThumbs[key] = bytes;
        } catch (_) {}
        if (token == _openToken && ++sinceUpdate >= 6) {
          sinceUpdate = 0;
          update();
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    if (token == _openToken) {
      isLoadingThumbs = false;
      update();
    }
  }

  // Recently shown thumbnails (small JPEGs), so re-opening a collection - or
  // scrolling back through one - doesn't decode them all again.
  final Map<String, Uint8List> _thumbCache = {};
  static const int _thumbCacheLimit = 500;

  void _rememberThumb(String key, Uint8List bytes) {
    _thumbCache.remove(key);
    _thumbCache[key] = bytes;
    while (_thumbCache.length > _thumbCacheLimit) {
      _thumbCache.remove(_thumbCache.keys.first);
    }
  }

  void closeCollection() {
    _openToken++;
    active = null;
    members = [];
    memberThumbs.clear();
    isLoadingMembers = false;
    isLoadingThumbs = false;
  }

  String memberKey(Map<String, dynamic> item) {
    final uri = item['path'] as String;
    final isVideo = item['isVideo'] as bool? ?? false;
    final timestampMs = (item['timestampMs'] as num?)?.toInt() ?? 0;
    return isVideo ? '$uri@$timestampMs' : uri;
  }
}
