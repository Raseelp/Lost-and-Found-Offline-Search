import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/view/day_photos_screen.dart' show dayOf;

/// One photo or video of an album to be exported, and how big it is.
class ExportItem {
  ExportItem(this.uri, this.isVideo, this.size);

  final String uri;
  final bool isVideo;

  /// Bytes; -1 when it cannot be read.
  final int size;
}

/// A collection, a person, or the "On this day" memories that can go in a zip. Its items and sizes are looked up once it is
/// ticked (a collection's members and a person's photos are asked for in full, not just the
/// first screenful).
class ExportAlbum {
  ExportAlbum({
    required this.key,
    required this.name,
    required this.approxCount,
    this.collection,
    this.person,
    this.memory,
  });

  /// "c:" and a collection id, "p:" and a person id, or [ExportController.memoryKey].
  final String key;
  final String name;

  /// What the collection or person is known to hold before it is looked up.
  final int approxCount;
  final SmartCollection? collection;
  final Person? person;

  /// Set for the "On this day" memories: everything from today's date in the past years.
  final OnThisDay? memory;

  bool get isPerson => person != null;

  List<ExportItem> _items = const [];
  bool loaded = false;
  bool loading = false;

  // Kept up to date by [items], so a screen full of albums does not count them again each frame.
  int images = 0, videos = 0, unreadable = 0, bytes = 0;

  List<ExportItem> get items => _items;

  set items(List<ExportItem> value) {
    _items = value;
    var i = 0, v = 0, u = 0, b = 0;
    for (final item in value) {
      if (item.size < 0) {
        u++;
        continue;
      }
      if (item.isVideo) {
        v++;
      } else {
        i++;
      }
      b += item.size;
    }
    images = i;
    videos = v;
    unreadable = u;
    bytes = b;
  }
}

/// One folder of the zip (an album's Images or its Videos), as the progress screen shows it
/// filling: what it holds, and the part of the whole run it takes up on screen.
class ZipFolderPlan {
  ZipFolderPlan({
    required this.albumKey,
    required this.album,
    required this.videos,
    required this.items,
  });

  /// Tells two albums of the same name apart.
  final String albumKey;
  final String album;
  final bool videos;
  final List<ExportItem> items;

  int get count => items.length;
  late final int bytes = items.fold(0, (sum, i) => sum + i.size);

  /// Where this folder starts and ends on the run's 0..1 line. Not exactly by size: a small
  /// folder still gets time on screen (see [ExportController.folders]).
  double start = 0, end = 0;

  /// A few of its photos or videos spaced along it: their thumbnails drop in as it fills.
  late final List<ExportItem> sample = () {
    final n = items.length < 5 ? items.length : 5;
    return [
      for (var i = 0; i < n; i++) items[((i + .5) * items.length / n).floor()],
    ];
  }();
}

/// Picks albums, estimates what a zip of them would be, and makes it (the work itself is done
/// natively as background work; this asks how it is getting on).
class ExportController extends GetxController {
  static const int mb = 1024 * 1024;
  static const int gb = 1024 * mb;

  /// How big one zip file may be, for the presets of the splitting control. 0: one file.
  static const List<int> presets = [0, 4 * gb, 2 * gb, 1 * gb, 512 * mb];

  /// A zip smaller than this is not worth splitting: the splitting controls are not shown.
  static const int splitMin = 100 * mb;

  List<ExportAlbum> collections = [];
  List<ExportAlbum> people = [];
  final Set<String> selected = {};

  /// Which of the two steps is showing: 0 choosing the albums, 1 the settings of the zip.
  int step = 0;

  void setStep(int value) {
    step = value;
    update();
  }

  /// What is typed in the search box: only albums with this in their name are listed.
  String query = '';

  late String zipName = _defaultName();
  bool _nameEdited = false;
  bool includeList = true;
  int partLimit = 0;

  /// A folder the user chose to save in; null means Downloads (in a folder called Lost & Found).
  String? folderUri;
  String? folderLabel;
  int freeBytes = -1;
  bool downloadsAvailable = true;

  ZipExportStatus status = ZipExportStatus.fromMap(const {});

  // The id of the last export whose end the user has seen and dismissed.
  int _seenId = -1;
  bool starting = false;
  Timer? _poll;

  /// Where the zip that was made last was saved: the name of the folder the user chose, or null
  /// for Downloads. Kept apart from [folderUri], which is chosen afresh each time the screen opens.
  String? savedLabel;

  /// While the progress screen is playing (it plays out its whole course, even for a zip that
  /// was made almost at once, before it moves on to the result).
  bool playing = false;

  /// The folders of the zip being made, in the order they are filled, and their thumbnails.
  List<ZipFolderPlan> folders = [];
  final Map<String, Uint8List> thumbs = {};
  bool _loading = false;

  // The screen has gone: albums still being looked up are given up on.
  bool _closed = false;

  // ---- albums ----

  static String _defaultName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Lost & Found export ${now.year}-${two(now.month)}-${two(now.day)}';
  }

  // An export that is going on, or that ended while the app was away and has not been seen yet,
  // is what the screen shows; an old one that was seen is forgotten.
  void _forgetSeen() {
    if (!status.running && (status.phase == 'idle' || status.id == _seenId)) {
      status = ZipExportStatus.fromMap(const {});
    }
    // One that is still going is played; one that ended while the screen was away is not
    // played again, its result is shown.
    playing = status.running;
  }

  /// Lists what can be exported, with [select] (keys) ticked to begin with. Called as the
  /// screen is made, so its first frame already shows this time's albums and not the last
  /// time's; [open] then asks about the rest.
  void prepare({Set<String> select = const {}}) {
    _forgetSeen();

    final collectionsController = Get.isRegistered<CollectionsController>()
        ? Get.find<CollectionsController>()
        : null;
    final memories = Get.isRegistered<MemoriesController>()
        ? Get.find<MemoriesController>().today
        : OnThisDay.empty;
    collections = [
      if (!memories.isEmpty && memories.total > 0)
        ExportAlbum(
          key: memoryKey,
          name: 'On this day - ${memories.dateLabel}',
          approxCount: memories.total,
          memory: memories,
        ),
      if (collectionsController != null)
        for (final c in collectionsController.visible)
          if (collectionsController.statsFor(c.id).count > 0)
            ExportAlbum(
              key: 'c:${c.id}',
              name: c.name,
              approxCount: collectionsController.statsFor(c.id).count,
              collection: c,
            ),
    ];
    final faces = Get.isRegistered<FacesController>()
        ? Get.find<FacesController>()
        : null;
    people = [
      if (faces != null)
        for (final p in faces.people)
          if (!p.hidden && p.photoCount > 0)
            ExportAlbum(
              key: 'p:${p.id}',
              name: p.name ?? 'Unnamed person',
              approxCount: p.photoCount,
              person: p,
            ),
    ];
    // Only what is really listed can be ticked (an empty collection, say, is not).
    final listed = {for (final a in allAlbums) a.key};
    selected
      ..clear()
      ..addAll(select.where(listed.contains));
    partLimit = 0;
    includeList = true;
    folderUri = null;
    folderLabel = null;
    _nameEdited = false;
    query = '';
    step = 0;
    _closed = false;
    _renameForSelection();
  }

  /// Asks what the phone can tell about the export, and starts looking the albums up.
  Future<void> open() async {
    await refreshStatus();
    _forgetSeen();
    unawaited(
      NativeServices().exportDownloadsAvailable().then((ok) {
        downloadsAvailable = ok;
        update();
      }),
    );
    unawaited(
      NativeServices().exportFreeSpace().then((free) {
        freeBytes = free;
        update();
      }),
    );
    update();
    unawaited(_pump());
  }

  /// The screen has gone: stops looking albums up. An end that was on screen has been seen, and
  /// is not shown again next time.
  void closeScreen() {
    _closed = true;
    if (!status.running && !playing && status.phase != 'idle') {
      _seenId = status.id;
    }
  }

  /// Key of the album of [collection] / [person], for [open]'s [select].
  static const String memoryKey = 'm:today';
  static String collectionKey(String id) => 'c:$id';
  static String personKey(int id) => 'p:$id';

  List<ExportAlbum> get allAlbums => [...collections, ...people];

  bool _matches(ExportAlbum album) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || album.name.toLowerCase().contains(q);
  }

  /// The albums the search box lets through.
  List<ExportAlbum> get shownCollections => [
    for (final a in collections)
      if (_matches(a)) a,
  ];
  List<ExportAlbum> get shownPeople => [
    for (final a in people)
      if (_matches(a)) a,
  ];

  /// Every album of [shown] (the collections, or the people, that the search lets through) is
  /// ticked.
  bool allChosen(List<ExportAlbum> shown) =>
      shown.isNotEmpty && shown.every((a) => selected.contains(a.key));

  /// Ticks all of [shown], or, when they all are ticked already, unticks them. Albums that the
  /// search hides are left as they were.
  void toggleAll(List<ExportAlbum> shown) {
    if (shown.isEmpty) return;
    if (allChosen(shown)) {
      for (final album in shown) {
        selected.remove(album.key);
      }
    } else {
      for (final album in shown) {
        selected.add(album.key);
      }
    }
    _renameForSelection();
    update();
    unawaited(_pump());
  }

  void setQuery(String value) {
    query = value;
    update();
    // What is now listed is looked up first.
    unawaited(_pump());
  }

  List<ExportAlbum> get selectedAlbums => [
    for (final a in allAlbums)
      if (selected.contains(a.key)) a,
  ];

  void toggle(ExportAlbum album) {
    if (!selected.remove(album.key)) selected.add(album.key);
    _renameForSelection();
    update();
    unawaited(_pump());
  }

  void setName(String name) {
    zipName = name;
    _nameEdited = true;
    update();
  }

  void _renameForSelection() {
    if (_nameEdited) return;
    final chosen = selectedAlbums;
    zipName = chosen.length == 1 ? chosen.first.name : _defaultName();
  }

  void setIncludeList(bool value) {
    includeList = value;
    update();
  }

  void setPartLimit(int bytes) {
    partLimit = bytes;
    update();
  }

  /// Whether the zip is big enough to be split at all.
  bool get canSplit => !loadingAny && totalBytes >= splitMin;

  /// The presets that make sense for this zip: the ones smaller than the zip itself (a part
  /// size the whole zip already fits in would change nothing).
  List<int> get applicablePresets => [
    for (final p in presets)
      if (p > 0 && p < totalBytes) p,
  ];

  /// The limit that is really used: what was chosen, as long as it can split this zip.
  int get activeLimit =>
      canSplit && partLimit > 0 && partLimit < totalBytes ? partLimit : 0;

  // ---- looking the albums up ----

  bool get loadingAny => selectedAlbums.any((a) => a.loading || !a.loaded);

  // Every album gets looked up in the background, so its size shows without being ticked:
  // the ticked ones first, then the ones the search lists, then the rest in order.
  ExportAlbum? _nextToLoad() {
    ExportAlbum? best;
    var bestRank = 3;
    for (final album in allAlbums) {
      if (album.loaded || album.loading) continue;
      final rank = selected.contains(album.key)
          ? 0
          : (query.trim().isNotEmpty && _matches(album) ? 1 : 2);
      if (rank < bestRank) {
        best = album;
        bestRank = rank;
      }
    }
    return best;
  }

  Future<void> _pump() async {
    if (_loading) return;
    _loading = true;
    try {
      while (!_closed) {
        final next = _nextToLoad();
        if (next == null) break;
        await _loadAlbum(next);
      }
    } finally {
      _loading = false;
    }
  }

  // Looking albums up changes the numbers many times a second; the screen is told at most this
  // often, so a big library does not make it rebuild over and over.
  Timer? _soon;

  void _updateSoon() {
    _soon ??= Timer(const Duration(milliseconds: 150), () {
      _soon = null;
      update();
    });
  }

  Future<void> _loadAlbum(ExportAlbum album) async {
    album.loading = true;
    _updateSoon();
    try {
      final List<Map<String, dynamic>> raw;
      if (album.person != null) {
        raw = await NativeServices().personPhotos(album.person!.id);
      } else if (album.memory != null) {
        // Every photo and video of the date in each year shown (not only the few the screen picks).
        final today = album.memory!;
        raw = [];
        for (final year in today.years) {
          final day = dayOf(year, today);
          final photos = await NativeServices().memoryDay(
            day.from,
            DateTime(day.from.year, day.from.month, day.from.day + day.days),
            limit: 100000,
          );
          for (final p in photos) {
            raw.add({'path': p.uri, 'isVideo': p.isVideo});
          }
        }
      } else {
        raw = await Get.find<CollectionsController>().allMembersOf(
          album.collection!,
        );
      }
      // Each photo once (a video that is several moments is one video).
      final seen = <String>{};
      final entries = <({String uri, bool isVideo})>[];
      for (final item in raw) {
        final uri = item['path'] as String?;
        if (uri == null || !seen.add(uri)) continue;
        entries.add((uri: uri, isVideo: item['isVideo'] as bool? ?? false));
      }
      final items = <ExportItem>[];
      for (var from = 0; from < entries.length; from += 300) {
        if (_closed) break;
        final chunk = entries.sublist(
          from,
          (from + 300).clamp(0, entries.length),
        );
        final infos = await NativeServices().exportItemInfo([
          for (final e in chunk) e.uri,
        ]);
        for (var i = 0; i < chunk.length; i++) {
          items.add(
            ExportItem(
              chunk[i].uri,
              chunk[i].isVideo,
              i < infos.length ? infos[i].size : -1,
            ),
          );
        }
        // The numbers tick up as the sizes come in.
        album.items = List.of(items);
        _updateSoon();
      }
      if (_closed) {
        // Given up on: looked up again next time.
        album.items = const [];
      } else {
        album.items = items;
        album.loaded = true;
      }
    } catch (e) {
      debugPrint('Could not look up ${album.name} for export: $e');
      album.items = const [];
      album.loaded = true;
    } finally {
      album.loading = false;
      update();
    }
  }

  // ---- the estimate ----

  int get totalImages => selectedAlbums.fold(0, (sum, a) => sum + a.images);
  int get totalVideos => selectedAlbums.fold(0, (sum, a) => sum + a.videos);
  int get totalFiles => totalImages + totalVideos;
  int get unreadable => selectedAlbums.fold(0, (sum, a) => sum + a.unreadable);

  /// Bytes of the files going in (a photo in two chosen albums is in the zip twice).
  int get totalBytes => selectedAlbums.fold(0, (sum, a) => sum + a.bytes);

  // What is worked out from every file of the chosen albums is kept until the albums, what is
  // in them, or the part size change: a screen rebuilds often, a big library takes a while.
  List<List<ExportItem>> _memoLists = const [];
  int _memoLimit = -1;
  List<int> _memoParts = const [];
  int _memoRepeatedBytes = 0, _memoRepeatedFiles = 0;

  void _derive() {
    final albums = selectedAlbums;
    final limit = activeLimit;
    if (limit == _memoLimit && albums.length == _memoLists.length) {
      var same = true;
      for (var i = 0; i < albums.length; i++) {
        if (!identical(albums[i].items, _memoLists[i])) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _memoLists = [for (final a in albums) a.items];
    _memoLimit = limit;
    _memoParts = _computePartSizes(albums, limit);
    _computeRepeated(albums);
  }

  /// Bytes that are only there because the same photo is in more than one of the chosen albums.
  int get repeatedBytes {
    _derive();
    return _memoRepeatedBytes;
  }

  int get repeatedFiles {
    _derive();
    return _memoRepeatedFiles;
  }

  void _computeRepeated(List<ExportAlbum> albums) {
    final counts = <String, int>{};
    final sizes = <String, int>{};
    for (final album in albums) {
      for (final item in album.items) {
        if (item.size < 0) continue;
        counts[item.uri] = (counts[item.uri] ?? 0) + 1;
        sizes[item.uri] = item.size;
      }
    }
    var bytes = 0, files = 0;
    counts.forEach((uri, n) {
      if (n > 1) {
        files += n - 1;
        bytes += sizes[uri]! * (n - 1);
      }
    });
    _memoRepeatedBytes = bytes;
    _memoRepeatedFiles = files;
  }

  /// How the files would be cut into zips of at most [activeLimit] bytes: the size of each (the
  /// same way the native side cuts them: album by album, images before videos, no file split).
  List<int> get partSizes {
    _derive();
    return _memoParts;
  }

  List<int> _computePartSizes(List<ExportAlbum> albums, int activeLimit) {
    final sizes = <int>[];
    final limit = activeLimit > 0 ? activeLimit - 256 * 1024 : 0;
    var current = 0;
    var any = false;
    for (final album in albums) {
      for (final videos in const [false, true]) {
        for (final item in album.items) {
          if (item.isVideo != videos || item.size < 0) continue;
          final cost = item.size + item.size ~/ 13000 + 500;
          if (limit > 0 && any && current + cost > limit) {
            sizes.add(current);
            current = 0;
            any = false;
          }
          current += cost;
          any = true;
        }
      }
    }
    if (any) sizes.add(current);
    return sizes;
  }

  /// The names the zip files will have (the same way the native side names them).
  List<String> zipFileNames(int count) {
    var base = (zipName.trim().isEmpty ? _defaultName() : zipName.trim())
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_')
        .trim();
    base = base.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
    if (base.length > 100) base = base.substring(0, 100).trim();
    if (base.isEmpty) base = 'Lost & Found export';
    return count <= 1
        ? ['$base.zip']
        : [for (var i = 1; i <= count; i++) '$base - part $i of $count.zip'];
  }

  bool get tooBigForDownloads =>
      folderUri == null && freeBytes >= 0 && totalBytes > freeBytes * 0.98;

  // ---- where it goes ----

  Future<void> pickFolder() async {
    final uri = await NativeServices().pickExportFolder();
    if (uri == null) return;
    folderUri = uri;
    folderLabel = _labelOf(uri);
    update();
  }

  void useDownloads() {
    folderUri = null;
    folderLabel = null;
    update();
  }

  // The last part of a tree uri's path, as a name for the folder.
  static String _labelOf(String uri) {
    try {
      final decoded = Uri.decodeComponent(uri);
      final tail = decoded.split('/tree/').last.split('/document/').first;
      final name = tail
          .split(':')
          .last
          .split('/')
          .where((s) => s.isNotEmpty)
          .lastOrNull;
      return name == null || name.isEmpty ? 'Chosen folder' : name;
    } catch (_) {
      return 'Chosen folder';
    }
  }

  // ---- making it ----

  bool get needsFolder => folderUri == null && !downloadsAvailable;

  bool get canStart =>
      !starting &&
      !status.running &&
      selected.isNotEmpty &&
      !loadingAny &&
      totalFiles > 0 &&
      !needsFolder;

  Future<void> start() async {
    if (!canStart) return;
    starting = true;
    update();
    folders = _planFolders();
    thumbs.clear();
    unawaited(_prefetchThumbs());
    final job = jsonEncode({
      'zipName': zipName.trim().isEmpty ? _defaultName() : zipName.trim(),
      'partLimitBytes': activeLimit,
      'includeList': includeList,
      'destination': {if (folderUri != null) 'treeUri': folderUri},
      'albums': [
        for (final album in selectedAlbums)
          {
            'name': album.name,
            'kind': album.isPerson
                ? 'person'
                : album.memory != null
                ? 'memory'
                : 'collection',
            'items': [
              for (final item in album.items)
                if (item.size >= 0) {'uri': item.uri, 'isVideo': item.isVideo},
            ],
          },
      ],
    });
    bool started;
    try {
      started = await NativeServices().startZipExport(job);
    } catch (e) {
      debugPrint('Could not start the zip export: $e');
      started = false;
    }
    starting = false;
    if (started) {
      savedLabel = folderUri == null
          ? null
          : (folderLabel ?? 'the folder you chose');
      playing = true;
      _watch();
    }
    await refreshStatus();
    if (!started && !status.running) {
      // Nothing is going on to show: say so, rather than leaving the button doing nothing.
      status = ZipExportStatus.fromMap(const {
        'id': -2,
        'phase': 'failed',
        'error': 'The zip could not be started. Please try again.',
      });
      update();
    }
  }

  /// The progress screen has played out: on to the result.
  void finishPlayback() {
    if (!playing) return;
    playing = false;
    update();
  }

  // The folders in the order the zip is filled (album by album, images then videos), each with
  // a share of the 0..1 line: mostly by size and by number of files, but never less than 3%, so
  // a small folder is still seen filling when the whole thing is over in a moment.
  List<ZipFolderPlan> _planFolders() {
    final plans = <ZipFolderPlan>[];
    for (final album in selectedAlbums) {
      for (final videos in const [false, true]) {
        final items = [
          for (final i in album.items)
            if (i.isVideo == videos && i.size >= 0) i,
        ];
        if (items.isEmpty) continue;
        plans.add(
          ZipFolderPlan(
            albumKey: album.key,
            album: album.name,
            videos: videos,
            items: items,
          ),
        );
      }
    }
    final totalBytes = plans.fold<int>(0, (sum, p) => sum + p.bytes);
    final totalCount = plans.fold<int>(0, (sum, p) => sum + p.count);
    final weights = [
      for (final p in plans)
        (0.6 * (totalBytes == 0 ? 0 : p.bytes / totalBytes) +
                0.4 * (totalCount == 0 ? 0 : p.count / totalCount))
            .clamp(0.03, 1.0),
    ];
    final sum = weights.fold<double>(0, (a, b) => a + b);
    var at = 0.0;
    for (var i = 0; i < plans.length; i++) {
      plans[i].start = at;
      at += weights[i] / sum;
      plans[i].end = i == plans.length - 1 ? 1.0 : at;
    }
    return plans;
  }

  // A few real thumbnails of each folder's files, ready for the progress screen.
  Future<void> _prefetchThumbs() async {
    final wanted = [for (final folder in folders) ...folder.sample];
    var next = 0;
    Future<void> worker() async {
      while (next < wanted.length) {
        final item = wanted[next++];
        if (thumbs.containsKey(item.uri)) continue;
        try {
          thumbs[item.uri] = await NativeServices().loadThumbnail(
            uri: item.uri,
            isVideo: item.isVideo,
            size: 160,
          );
        } catch (_) {
          // A missing thumbnail is just a plain tile.
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<void> cancel() async {
    await NativeServices().cancelZipExport();
    await refreshStatus();
  }

  /// Back to choosing albums after an export has ended.
  void another() {
    _seenId = status.id;
    status = ZipExportStatus.fromMap(const {});
    selected.clear();
    folders = [];
    thumbs.clear();
    playing = false;
    step = 0;
    _nameEdited = false;
    _renameForSelection();
    update();
  }

  Future<void> refreshStatus() async {
    try {
      final fresh = await NativeServices().zipExportStatus();
      // An end the user has already dismissed does not come back.
      status = !fresh.running && fresh.id == _seenId
          ? ZipExportStatus.fromMap(const {})
          : fresh;
    } catch (_) {
      // Keeps what it knew.
    }
    if (status.running) _watch();
    update();
  }

  void _watch() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 300), (_) async {
      await refreshStatus();
      if (!status.running) {
        _poll?.cancel();
        _poll = null;
      }
    });
  }

  @override
  void onClose() {
    _poll?.cancel();
    _soon?.cancel();
    super.onClose();
  }
}
