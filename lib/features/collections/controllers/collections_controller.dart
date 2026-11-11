import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/library/db/indexed_folder_db_helper.dart';
import 'package:lost_and_found/features/collections/models/collection_model.dart';
import 'package:lost_and_found/features/collections/models/default_collections.dart';
import 'package:lost_and_found/features/search/services/tokenizer/clip_tokenizer.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/collections/services/collections_service.dart';
import 'package:lost_and_found/features/people/services/people_service.dart';
import 'package:lost_and_found/features/search/services/search_service.dart';

/// Owns the collections: the list the Collections tab and the Search tab chip row show, each one's count
/// and cover from the last scoring pass, and the open collection.
///
/// Every collection can be edited, hidden or deleted. Built-ins live in code, so for them these are stored as
/// small overrides (see the collections section of [IndexedFolderDbHelper]). Deleting a built-in only takes it
/// off the list until Settings restores it.
class CollectionsController extends GetxController {
  /// Version of the search model that the cached query embeddings and photo seed vectors belong to.
  /// Change it when the search model changes, or when a text or a photo is prepared for it differently.
  static const modelVersion = 'mobileclip-s0-apple-2024-v1';
  static const _modelVersion = modelVersion;
  static const _embeddingsKey = 'collection_embeddings';
  static const int _memberLimit = 200;

  static const int _stateVisible = 0;
  static const int _stateHidden = 1;
  static const int _stateDeleted = 2;

  /// The least time a saved collection's card shows its matching animation, so a quick sync does not flash past.
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

  /// True if any built-in was edited, hidden or deleted, so that Restore default collections has something to undo.
  bool get hasCustomizedBuiltIns =>
      _edited.isNotEmpty ||
      deletedBuiltInCount > 0 ||
      _builtIns.any((c) => _stateOf(c.id) == _stateHidden);

  final Map<String, CollectionStats> stats = {};
  /// Card covers by [CollectionCover.cacheKey].
  final Map<String, Uint8List> coverBytes = {};
  /// The long side in px that each cover in [coverBytes] was loaded at. A cover loaded smaller is loaded again
  /// for a bigger tile.
  final Map<String, int> _coverSize = {};
  final Map<String, Future<Uint8List?>> _coverLoads = {};
  bool isScoring = false;
  bool _statsLoadedOnce = false;
  bool _refreshAgain = false;
  bool get hasScored => _statsLoadedOnce;

  /// Ids of the collections being computed, whose cards show the matching animation.
  final Set<String> syncing = {};

  /// Progress of embedding every collection's prompts, the slow part of the first scoring pass.
  /// [setupTotal] is 0 when nothing needed embedding.
  int setupDone = 0;
  int setupTotal = 0;

  /// Query embeddings by collection id. Each entry holds the signature (sig) and the vector (emb).
  final Map<String, Map<String, dynamic>> _embeddingCache = {};

  SmartCollection? active;
  List<Map<String, dynamic>> members = [];
  final Map<String, Uint8List> memberThumbs = {};
  bool isLoadingMembers = false;
  /// True while the members are known but their thumbnails are still arriving, so tiles show a placeholder
  /// rather than an error icon.
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

  /// The cover shown for a collection. It rotates through the top few matches once a day, offset per collection so
  /// that they do not all change together.
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

  /// Whether the built-ins with no matches, tucked away at the end of the tab, are shown.
  bool showEmpty = false;

  void toggleShowEmpty() {
    showEmpty = !showEmpty;
    update();
  }

  /// Larger pictures for the featured card, by the cover's cache key. A cover changes with the day and with the index.
  final Map<String, Uint8List> _heroBytes = {};

  Uint8List? heroBytesFor(String id) {
    final cover = selectedCover(id);
    return cover == null ? null : (_heroBytes[cover.cacheKey] ?? coverBytes[cover.cacheKey]);
  }

  /// The collections that take turns on the featured card. They have something in them and a cover, known from the
  /// scores and not from the picture having arrived, so the set does not shuffle while pictures come in. Those with
  /// new photos come first. The order differs each day and is the same all day.
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
        _heroBytes[cover.cacheKey] = await MediaService().loadThumbnail(
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

  /// Pictures arrive one by one, so the tab is told about them a few times a second and not once per picture.
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

  /// Builds the built-ins and the user's collections from the stored rows. A built-in whose row keeps its prompts
  /// (a rename or a sensitivity change) keeps its short [SmartCollection.explainQuery], so that the explanation of a
  /// match and the edit sheet do not change to the first long prompt.
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
          if (prompts.isEmpty) return d;
          _edited.add(d.id);
          return d.copyWith(
            name: r['name'] as String?,
            prompts: prompts,
            explainQuery: listEquals(prompts, d.prompts) ? d.explainQuery : null,
            contentMode: r['contentMode'] as String?,
            sensitivity: (r['sensitivity'] as num?)?.toDouble(),
          );
        }(),
    ];
  }

  void _rebuildLists() {
    final builtIns = _builtIns.where((c) => _stateOf(c.id) == _stateVisible).toList();
    builtIns.sort((a, b) => statsFor(b.id).count.compareTo(statsFor(a.id).count));
    visible = [..._user.where((c) => _stateOf(c.id) == _stateVisible), ...builtIns];
    hiddenCollections = [
      ..._user.where((c) => _stateOf(c.id) == _stateHidden),
      ..._builtIns.where((c) => _stateOf(c.id) == _stateHidden),
    ];
    deletedBuiltInCount = _builtIns.where((c) => _stateOf(c.id) == _stateDeleted).length;
  }

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

  /// The embedding of a collection. Each prompt is embedded and normalized on its own, then the vectors are averaged
  /// and normalized again, because several phrasings of the same idea are more robust than one.
  ///
  /// A photo collection returns its own seed vector when the current search model made it.
  Future<List<double>> _embeddingFor(SmartCollection c) async {
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

  /// The prompts' vectors averaged, or null when none could be made.
  Future<List<double>?> _embedPrompts(List<String> prompts) async {
    final tokenizer = await ClipTokenizer.load();
    List<double>? sum;
    for (final prompt in prompts) {
      final e = _normalized(await SearchService().encodeText(tokenizer.tokenize(prompt)));
      if (e.isEmpty) continue;
      sum = sum == null ? e : [for (var i = 0; i < sum.length; i++) sum[i] + e[i]];
    }
    return sum == null ? null : _normalized(sum);
  }

  /// The vectors of the words and photos previewed lately, so that editing one phrase or switching between photos
  /// and videos does not run the model again for the rest.
  final Map<String, List<double>> _previewVectors = {};

  /// What a collection made of these words (or, with [seedUri], of looking like that photo or video frame) would
  /// hold, found the same way a saved collection's members are: how many items, the best few, and the people in
  /// them. Null when it cannot be worked out (nothing indexed, the search model not ready).
  ///
  /// With only people and no words it scores against the generic prompt, as [createCollection] does. When no
  /// embedding comes out the model is not ready, so nothing is kept and it is tried again next time.
  Future<CollectionPreview?> previewCollection({
    List<String> prompts = const [],
    String? seedUri,
    int? seedTimestampMs,
    String contentMode = 'both',
    List<int> personIds = const [],
    double sensitivity = SmartCollection.defaultSensitivity,
    int shown = 5,
  }) async {
    try {
      final words = [
        for (final p in prompts)
          if (p.trim().isNotEmpty) p.trim(),
      ];
      if (seedUri == null && words.isEmpty) words.add('a photo');
      final key = seedUri != null ? 'photo|$seedUri@$seedTimestampMs' : 'words|${words.join('|')}';
      final embedding = _previewVectors[key] ??
          (seedUri != null
              ? _normalized(await SearchService().encodeImage(uri: seedUri, timestampMs: seedTimestampMs))
              : await _embedPrompts(words) ?? const <double>[]);
      if (embedding.isEmpty) return null;
      _previewVectors[key] = embedding;
      if (_previewVectors.length > 40) _previewVectors.remove(_previewVectors.keys.first);

      final spec = {
        'id': 'preview',
        'embedding': embedding,
        'contentMode': contentMode,
        'k': sensitivity,
        if (personIds.isNotEmpty) 'personIds': personIds,
      };
      final scored = await CollectionsService().scoreCollections([spec]);
      final count = scored.isEmpty ? 0 : (scored.first['count'] as num? ?? 0).toInt();
      if (count == 0) return const CollectionPreview(count: 0, items: [], people: []);
      final members = await CollectionsService().collectionMembers(spec, limit: 400);
      final items = [for (final m in members.take(shown)) CollectionCover.fromMap(m)];
      List<({int personId, int count})> people = const [];
      try {
        people = await PeopleService().peopleIn([
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

  /// Embeds the photo of a photo collection again with the current search model and keeps the result, so this happens
  /// once. It throws when the photo cannot be read. The collection is then left empty, because the stored vector means
  /// nothing to the current model.
  Future<List<double>> _seedAgain(SmartCollection c) async {
    final uri = c.seedUri;
    if (uri == null) throw StateError('Collection ${c.id} has no photo to embed again');
    final fresh = _normalized(
      await SearchService().encodeImage(uri: uri, timestampMs: c.seedTimestampMs ?? 0),
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

  /// Throws away every cached query embedding and score and computes them again. Used by Resync collections in
  /// Settings.
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

  /// Scores every visible collection in one native pass. Cheap enough to call whenever the index changes.
  ///
  /// A call made during a pass runs again once that pass is done, so a change is not dropped. When nothing is indexed
  /// the kept counts and covers are cleared, because they belong to an index that is gone.
  Future<void> refreshStats() async {
    if (isScoring) {
      _refreshAgain = true;
      return;
    }
    final native = Get.find<NativeController>();
    if (native.totalEmbeddings == 0) {
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

      final scored = await CollectionsService().scoreCollections(specs);
      stats.clear();
      for (final s in scored) {
        stats[s['id'] as String] = _statsFromMap(s);
      }
      _statsLoadedOnce = true;
      _rebuildLists();
    } on ModelsNotReadyError {
      // No models yet, so the tab shows empty cards.
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

  /// Scores just [c], so that a saved or edited collection's card can animate without waiting for a pass over all
  /// of them.
  Future<void> _syncOne(SmartCollection c) async {
    final started = DateTime.now();
    syncing.add(c.id);
    update();
    try {
      final native = Get.find<NativeController>();
      if (native.modelsReady && native.totalEmbeddings > 0) {
        final scored = await CollectionsService().scoreCollections([await _specFor(c)]);
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

  /// Set while a cover pass runs. A scan that finishes meanwhile asks for another pass afterwards, so the same
  /// pictures are not loaded twice at once.
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

  /// Loads the pictures that are shown without a tile asking for them, which is the featured card. The tiles of the
  /// tab and the story rings of the Search tab load their own cover as they come on screen. The last pictures do not
  /// wait for the notify timer.
  Future<void> _loadCoversPass() async {
    unawaited(_loadHeroImages());
    _notifyTimer?.cancel();
    _notifyTimer = null;
    update();
  }

  /// The cover of collection [id] with its long side at least [size] px: the one in memory when it was loaded that
  /// large already, else loaded at that size (null when the collection has no cover, or it cannot be read). A tile
  /// asks for the size that fits it, so a big tile of the mosaic is not given a small picture.
  Future<Uint8List?> loadCover(String id, int size) {
    final cover = selectedCover(id);
    if (cover == null) return Future.value(null);
    final have = coverBytes[cover.cacheKey];
    if (have != null && (_coverSize[cover.cacheKey] ?? 0) >= size) return Future.value(have);
    final key = '${cover.cacheKey}@$size';
    return _coverLoads[key] ??= _fetchCover(cover, size).whenComplete(() => _coverLoads.remove(key));
  }

  /// Loads a cover and keeps it, unless a bigger request for the same cover finished first. Returns null when the
  /// picture is missing, which leaves the tile with its icon.
  Future<Uint8List?> _fetchCover(CollectionCover cover, int size) async {
    try {
      final bytes = await _loadThumb(cover.uri, cover.isVideo, cover.timestampMs, size: size);
      if ((_coverSize[cover.cacheKey] ?? 0) < size) {
        coverBytes[cover.cacheKey] = bytes;
        _coverSize[cover.cacheKey] = size;
        _updateSoon();
      }
      return coverBytes[cover.cacheKey] ?? bytes;
    } catch (_) {
      return null;
    }
  }

  /// Loads a thumbnail sized for tiles and cards, not for full screen. A video's is a bit larger because it is also
  /// the poster in the viewer for a moment.
  Future<Uint8List> _loadThumb(String uri, bool isVideo, int timestampMs, {int? size}) {
    return MediaService().loadThumbnail(
      uri: uri,
      isVideo: isVideo,
      timestampMs: timestampMs,
      size: size ?? (isVideo ? 640 : 420),
    );
  }

  /// Turns the search that is showing into a collection. [personIds] lets the caller pass the people mentioned in
  /// the search itself, because search_tab.dart takes them when the search runs and the text field may by then hold
  /// a different search. Without it the people on the controller are used.
  ///
  /// A search of only a person mention is still saved. Null when there is neither text nor a person.
  Future<SmartCollection?> saveSearchAsCollection({
    required String name,
    List<int>? personIds,
  }) async {
    final native = Get.find<NativeController>();
    final query = native.lastTextQuery;
    final ids = personIds ?? native.lastMentionedPersonIds;
    if ((query == null || query.trim().isEmpty) && ids.isEmpty) return null;
    return createCollection(
      name: name,
      query: query?.trim() ?? '',
      contentMode: native.getContentModeString(contentMode: native.searchContentMode),
      personIds: ids,
    );
  }

  /// Turns the image search that is showing (a picked photo, a photo from the viewer, or a video frame) into a
  /// photo-seeded collection.
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
      embedding = _normalized(await SearchService().encodeImage(uri: uri, timestampMs: timestampMs));
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

  /// Adds a collection made of [query] and shows its card at once, marked as syncing. The database write and the
  /// scoring happen behind it.
  ///
  /// An empty [query] (only people) embeds the generic prompt 'a photo', because the model needs something to score
  /// against. The person filter, applied natively (see [_specFor]), does the narrowing. [morePrompts] are other
  /// phrasings that are averaged in, which is steadier than one phrase alone.
  Future<SmartCollection> createCollection({
    required String name,
    required String query,
    String contentMode = 'both',
    List<int> personIds = const [],
    List<String> morePrompts = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveQuery = query.trim().isEmpty ? 'a photo' : query.trim();
    return _addAndSync(
      SmartCollection(
        id: 'user_$now',
        name: name.trim().isEmpty ? query : name.trim(),
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

  /// Saves [collection] (a photo collection) with [name] and [contentMode], looking like the photo at [uri] from now on.
  /// The new photo is embedded with the current search model, and the matches are found again. Returns false when the
  /// photo could not be read: the name and what is included are saved all the same, and the collection keeps looking
  /// like the photo it had.
  Future<bool> changePhoto(
    SmartCollection collection, {
    required String uri,
    required String name,
    required String contentMode,
  }) async {
    List<double> embedding = const [];
    try {
      embedding = _normalized(await SearchService().encodeImage(uri: uri));
    } catch (e) {
      debugPrint('Could not embed the new photo: $e');
    }
    var updated = collection.copyWith(name: name, contentMode: contentMode);
    if (embedding.isNotEmpty) {
      updated = updated.withSeed(uri: uri, embedding: embedding, model: _modelVersion);
    }
    await updateCollection(updated);
    return embedding.isNotEmpty;
  }

  /// Saves [updated]. A rename changes nothing about what matches, so the work and the matching animation are
  /// redone only when the query, content filter, sensitivity or people changed.
  Future<void> updateCollection(SmartCollection updated) async {
    final before = [..._user, ..._builtIns].firstWhereOrNull((c) => c.id == updated.id);
    await _db.upsertCollection(updated, hiddenState: _stateOf(updated.id));
    await _reload(refresh: false);
    final fresh = [..._user, ..._builtIns].firstWhereOrNull((c) => c.id == updated.id);
    if (fresh == null) return;

    final matchesChanged = before == null ||
        before.embeddingSignature != fresh.embeddingSignature ||
        before.contentMode != fresh.contentMode ||
        before.sensitivity != fresh.sensitivity ||
        before.seedUri != fresh.seedUri ||
        before.seedTimestampMs != fresh.seedTimestampMs ||
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

  /// Hides collection [id]. When it is open it is closed first, so the screen does not sit on something that is gone.
  Future<void> hideCollection(String id) {
    if (active?.id == id) closeCollection();
    return _setState(id, _stateHidden);
  }

  Future<void> unhideAll() async {
    for (final c in [...hiddenCollections]) {
      await _db.setCollectionState(c.id, _stateVisible, isBuiltIn: c.isBuiltIn);
    }
    await _reload();
  }

  /// Deletes a collection you made for real. A built-in ships with the app, so it is only taken off the list until
  /// Settings restores it.
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

  /// Undoes the edits to one built-in.
  Future<void> resetBuiltIn(String id) async {
    await _db.deleteCollection(id);
    await _reload();
  }

  /// Puts every built-in back as it ships. Used by Restore default collections in Settings. Collections you made are
  /// untouched.
  Future<void> restoreDefaults() async {
    await _db.resetBuiltIns();
    await _reload();
  }

  Future<void> _setState(String id, int state) async {
    final isBuiltIn = _builtIns.any((c) => c.id == id);
    await _db.setCollectionState(id, state, isBuiltIn: isBuiltIn);
    await _reload(refresh: false);
  }

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
      return await CollectionsService().collectionMembers(await _specFor(collection), limit: 100000);
    } on ModelsNotReadyError {
      return const [];
    }
  }

  /// The best matches of [collection], for a story: a few dozen, not the whole collection. Empty
  /// if the models are not ready.
  Future<List<Map<String, dynamic>>> membersForStory(SmartCollection collection, {int limit = 30}) async {
    try {
      return await CollectionsService().collectionMembers(await _specFor(collection), limit: limit);
    } on ModelsNotReadyError {
      return const [];
    } catch (e) {
      debugPrint('Failed to load story members: $e');
      return const [];
    }
  }

  /// Opens [collection] and loads its members. Thumbnails fill in progressively and the grid shows a placeholder until
  /// each arrives, so the screen does not wait for up to 200 decodes. Ones seen before come from the in-memory cache.
  /// The rest load four at a time in list order, so the top of the grid fills first. Items from the latest scan come
  /// first. A later call makes an earlier one stop loading.
  Future<void> openCollection(SmartCollection collection) async {
    final token = ++_openToken;
    active = collection;
    members = [];
    memberThumbs.clear();
    isLoadingMembers = true;
    isLoadingThumbs = false;
    update();

    try {
      final found = await CollectionsService().collectionMembers(
        await _specFor(collection),
        limit: _memberLimit,
      );
      if (token != _openToken) return;
      members = found;
    } on ModelsNotReadyError {
      // No models yet, so the screen shows nothing.
    } catch (e) {
      debugPrint('Failed to load collection members: $e');
    }
    if (token != _openToken) return;
    isLoadingMembers = false;
    isLoadingThumbs = members.isNotEmpty;
    update();

    var sinceUpdate = 0;
    final pending = <Map<String, dynamic>>[];
    for (final item in Get.find<NativeController>().newFirst(members)) {
      final key = memberKey(item);
      final cached = _thumbCache.remove(key);
      if (cached != null) {
        _thumbCache[key] = cached;
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

  /// Recently shown thumbnails (small JPEGs), so that opening a collection again or scrolling back through one does
  /// not decode them all again.
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
