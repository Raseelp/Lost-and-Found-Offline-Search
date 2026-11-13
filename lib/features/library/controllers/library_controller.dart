import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/library/db/indexed_folder_db_helper.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';
import 'package:lost_and_found/core/permissions/permission_prompt.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
import 'package:lost_and_found/features/search/controllers/search_controller.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/core/storage/preferences.dart';
import 'package:lost_and_found/features/library/models/scan_models.dart';

class LibraryController extends GetxController with WidgetsBindingObserver {
  ModelDownloadController get _models => Get.find<ModelDownloadController>();
  AppSearchController get _search => Get.find<AppSearchController>();
  SettingsController get _settings => Get.find<SettingsController>();
  /// Opens the app's standing state in the order the Library tab needs it: its preferences, whether the search models are
  /// there, the folders and the stats, the notification answer, then any scan that was running or was cut short.
  @override
  onInit() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadPersistedPreferences();
    await _models.checkModelsReady();
    await getAllFoldersList();
    await refreshLibraryStats();
    await _settings.checkBackgroundScanPermission();
    await _resumeActiveScanIfAny();
    await checkForInterruptedScan();
    refreshCollections();
    unawaited(refreshLatestScan());
    super.onInit();
  }

  /// Scores the collections again. Their counts and covers depend on the index, so anything that changes it (startup once
  /// the models are known, a finished scan, a clear) calls this. The collections controller is registered right after
  /// the library one, so it may not exist yet at the very start.
  void refreshCollections() {
    if (Get.isRegistered<CollectionsController>()) {
      unawaited(Get.find<CollectionsController>().refreshStats());
    }
  }

  /// Loads the scan mode and the failed counts, once, before anything else needs them. If loading fails the app opens
  /// with the defaults, since blocking startup is never worth it.
  Future<void> _loadPersistedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final modeName = prefs.getString(_contentModeKey);
      if (modeName != null) {
        selectedContentMode = ContentMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => ContentMode.both,
        );
      }

      final lastRaw = prefs.getString(_lastPhotoKey);
      if (lastRaw != null) {
        final map = jsonDecode(lastRaw) as Map;
        lastPhoto = RecentEmbeddedItem(
          uri: map['uri'] as String? ?? '',
          isVideo: map['isVideo'] as bool? ?? false,
          timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
        );
      }

      final failedRaw = prefs.getString(_failedByFolderKey);
      if (failedRaw != null) {
        final decoded = jsonDecode(failedRaw) as Map;
        _failedByFolder
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k as String, v as int)));
        totalFailed = _failedByFolder.values.fold(0, (a, b) => a + b);
      }

      update();
    } catch (e) {
      debugPrint('Failed to load persisted preferences: $e');
    }
  }

  @override
  void onClose() {
    _thumbUpdateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  /// Reads the latest scan and the numbers of the library again when the app comes back, as new photos and videos may
  /// have been indexed by themselves meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshLatestScan());
      if (!isScanning) unawaited(refreshLibraryStats());
    }
  }


  static const _contentModeKey = 'scan_content_mode';

  static const _interruptedScanKey = 'interrupted_scan';

  /// The newest photo or video the scan indexed, kept so the Library can show it after the app is opened again.
  static const _lastPhotoKey = 'last_scan_photo';

  /// Holds, for each folder id, how many files could not be embedded the last time that location finished scanning.
  static const _failedByFolderKey = 'failed_by_folder';

  /// The items the latest indexing scan stored, which are tagged as new wherever they are shown. They are kept for this
  /// run of the app only, and a scan that stored nothing leaves them as they were. A scan that ended while the app was
  /// closed leaves its items to be taken by [refreshLatestScan] (see LatestScan).
  Set<String> latestScanUris = {};

  bool isInLatestScan(String uri) => latestScanUris.contains(uri);

  /// [items] (media with a 'path') with the ones the latest scan indexed first and the rest in
  /// their order; the very same list when none of them is. A grid and the loading of its
  /// thumbnails both use this, so what shows first is what loads first.
  List<Map<String, dynamic>> newFirst(List<Map<String, dynamic>> items) {
    if (latestScanUris.isEmpty) return items;
    final fresh = <Map<String, dynamic>>[], rest = <Map<String, dynamic>>[];
    for (final item in items) {
      (isInLatestScan(item['path'] as String? ?? '') ? fresh : rest).add(item);
    }
    return fresh.isEmpty ? items : [...fresh, ...rest];
  }

  static const _autoShownKept = 24;

  /// When new photos and videos were last indexed by themselves, in milliseconds since 1970, or 0. The Library counts it
  /// as a time of scanning.
  int autoIndexedAtMs = 0;

  /// What indexing by itself stored since the app was opened, for the card on the Search tab. It is taken from the native
  /// side once, so it is held here for as long as the app stays open, and the next time the app is opened it holds only
  /// what was stored in between. A few of the items are kept to show, newest first.
  AutoIndexedBatch autoIndexed = const AutoIndexedBatch();

  /// Takes what the latest scan stored and what indexing by itself stored since. The scan's items replace the ones held
  /// (a scan after it has started over), and the others are added to them.
  Future<void> refreshLatestScan() async {
    final service = LibraryService();
    final items = await service.takeLatestScan();
    final auto = await service.takeAutoIndexed();
    final at = await service.autoIndexedAt();
    final shown = await service.takeAutoShown();
    var changed = false;
    if (shown.count > 0) {
      autoIndexed = AutoIndexedBatch(
        photos: autoIndexed.photos + shown.photos,
        videos: autoIndexed.videos + shown.videos,
        items: [...shown.items, ...autoIndexed.items].take(_autoShownKept).toList(),
      );
      changed = true;
    }
    if (items.isNotEmpty) {
      latestScanUris = items.toSet();
      changed = true;
    }
    if (auto.isNotEmpty) {
      latestScanUris = {...latestScanUris, ...auto};
      changed = true;
      refreshCollections();
    }
    if (at != autoIndexedAtMs) {
      autoIndexedAtMs = at;
      changed = true;
    }
    if (changed) update();
  }

  int total = 0;

  int embedded = 0;

  int skipped = 0;

  /// The count of raw embedding vectors, where a video contributes several, one per frame. [totalImages] and
  /// [totalVideos] count distinct media items, and [indexSizeBytes] is the size on disk of the embeddings store itself.
  /// [refreshLibraryStats] keeps the four in step.
  int totalEmbeddings = 0;

  /// The search model that made an index the app dropped when it switched to another one (0: none was). While it
  /// is set the Library tab tells the person that their photos have to be scanned again.
  int modelResetFrom = 0;

  int totalImages = 0;

  int totalVideos = 0;

  int indexSizeBytes = 0;

  bool isScanning = false;

  /// Stop was tapped and the scan is finishing the work in hand (a batch of photos, a video's frames, a face batch)
  /// before it ends, which can take a few seconds. The Library tab shows "Stopping" and ignores further taps until the
  /// final tick of the scan clears it.
  bool isStopping = false;

  /// Set when a scan was still running last time the app process existed but is not any more, because the system killed
  /// the app and the scan was not finished or stopped, and no live scan was found to reconnect to. Null means there is
  /// nothing to offer resuming. The keys are folderId, uri, mode and contentMode.
  Map<String, String>? interruptedScan;

  /// The files that could not be embedded (corrupt, unsupported or unreadable) as of the last completed scan of each
  /// location, shown as the "Failed" tile of the Library tab. A failed file is not stored, so every rescan tries it
  /// again, which is why a finished library can still count a few files as new.
  final Map<String, int> _failedByFolder = {};

  int totalFailed = 0;

  /// Set when a scan runs all the way to the end, neither cancelled nor failed. It drives the completion card of the
  /// Library tab, and the card or the start of the next scan clears it.
  ScanSummary? scanSummary;

  void dismissScanSummary() {
    if (scanSummary == null) return;
    scanSummary = null;
    update();
  }

  Future<void> _persistFailedByFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_failedByFolderKey, jsonEncode(_failedByFolder));
    } catch (e) {
      debugPrint('Failed to persist failed counts: $e');
    }
  }

  Future<void> _recordFailedForFolder(String folderId, int failed) async {
    if (failed > 0) {
      _failedByFolder[folderId] = failed;
    } else {
      _failedByFolder.remove(folderId);
    }
    totalFailed = _failedByFolder.values.fold(0, (a, b) => a + b);
    update();
    await _persistFailedByFolder();
  }

  String scannedPath = '';

  ContentMode selectedContentMode = ContentMode.both;

  late StreamSubscription<Map<String, dynamic>> _progressSub;

  IndexedFolder scanResult = IndexedFolder.empty();

  /// Recent throughput, recomputed from consecutive progress events. It reacts within a couple of seconds to a change
  /// of speed, where an average over the whole scan would be dragged down by its history.
  double recentEmbeddingsPerSecond = 0;

  IndexedFolder? _previousProgress;

  /// The most thumbnails kept for the "Recently indexed" strip, a small newest-first list of files shown while a scan is
  /// running. The strip has its own cache and not [imageCache], because a search running at the same time clears
  /// [imageCache] on every run (see [runSearch]) and that would blank the strip mid-scan. Fetching is throttled by
  /// [_recentThumbFetchThrottle], since the scan can embed several files per progress tick and fetching a thumbnail for
  /// each would compete with the scan for I/O and CPU.
  static const int _maxRecentThumbnails = 10;

  static const Duration _recentThumbFetchThrottle = Duration(milliseconds: 300);

  /// How many thumbnails are read at once, so that the square can show a whole round of photos together.
  static const int _recentThumbParallel = 4;

  /// Makes thumbnails that arrive together repaint the page once and not once each.
  Timer? _thumbUpdateTimer;

  void _scheduleThumbUpdate() {
    if (_thumbUpdateTimer != null) return;
    _thumbUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      _thumbUpdateTimer = null;
      update();
    });
  }

  /// While faces follow the scan: how many photos wait for the next face batch, how long since the last batch ended, the
  /// rule they fill towards, and when this was reported.
  int? faceQueueCount;

  int faceQueueMs = 0;

  int faceBatchPhotos = 60;

  int faceBatchMs = 30000;

  DateTime faceQueueAt = DateTime.now();

  List<RecentEmbeddedItem> recentThumbnails = [];

  /// The newest item the scan indexed, from this run of the app or the one before.
  RecentEmbeddedItem? lastPhoto;

  DateTime? _lastPhotoSavedAt;

  /// Saves [lastPhoto], at most every few seconds unless [force] is set, so a fast scan does not write all the time.
  Future<void> _saveLastPhoto({bool force = false}) async {
    final item = lastPhoto;
    if (item == null || item.uri.isEmpty) return;
    final now = DateTime.now();
    final saved = _lastPhotoSavedAt;
    if (!force && saved != null && now.difference(saved) < const Duration(seconds: 4)) return;
    _lastPhotoSavedAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastPhotoKey,
        jsonEncode({'uri': item.uri, 'isVideo': item.isVideo, 'timestampMs': item.timestampMs}),
      );
    } catch (e) {
      debugPrint('Failed to save the last photo: $e');
    }
  }

  /// The picture for a key of [recentThumbBytes], or for the saved [lastPhoto] when it is not among them.
  Future<Uint8List> thumbnailFor(String key) async {
    final cached = recentThumbBytes[key];
    if (cached != null) return cached;
    final item = lastPhoto;
    if (item == null || _recentThumbKey(item) != key) throw StateError('No picture for $key');
    return MediaService().loadThumbnail(uri: item.uri, isVideo: item.isVideo, timestampMs: item.timestampMs);
  }

  final Map<String, Uint8List> recentThumbBytes = {};

  final Set<String> _recentThumbInFlight = {};

  DateTime? _lastRecentThumbFetch;

  /// Throttles the live refresh of the stats of the Library tab during a scan (see [_maybeRefreshLibraryStatsLive]).
  DateTime? _lastLiveStatsRefresh;

  final db = IndexedFolderDbHelper.instance;

  List<IndexedFolder> allIndexedFoldersList = [];

  String _recentThumbKey(RecentEmbeddedItem item) {
    return item.isVideo ? '${item.uri}@${item.timestampMs}' : item.uri;
  }

  /// Starts the reads of the thumbnails not fetched yet, a few at a time and not more often than the throttle, so a fast
  /// scan cannot turn this into a thumbnail flood. The [items] are newest first.
  void _maybeFetchNextRecentThumbnail(List<RecentEmbeddedItem> items) {
    if (items.isEmpty) return;

    final now = DateTime.now();
    if (_lastRecentThumbFetch != null &&
        now.difference(_lastRecentThumbFetch!) < _recentThumbFetchThrottle) {
      return;
    }

    var started = 0;
    for (final item in items) {
      if (_recentThumbInFlight.length >= _recentThumbParallel) break;
      final key = _recentThumbKey(item);
      if (recentThumbBytes.containsKey(key) ||
          _recentThumbInFlight.contains(key)) {
        continue;
      }
      _recentThumbInFlight.add(key);
      _fetchRecentThumbnail(item, key);
      started++;
    }
    if (started > 0) _lastRecentThumbFetch = now;
  }

  /// Reads the small thumbnail of one item for the "Recently indexed" strip. It is small because the chip draws it at
  /// most 300 pixels wide, and a video's frame is made while holding the lock that the video decoding of the scan needs.
  /// The strip is cosmetic, so a missed thumbnail is never worth showing an error. When the oldest item leaves the
  /// strip its bytes are dropped only if no other item in the strip needs them, as the same file could reappear under
  /// the same key.
  Future<void> _fetchRecentThumbnail(
    RecentEmbeddedItem item,
    String key,
  ) async {
    try {
      final bytes = await MediaService().loadThumbnail(
        uri: item.uri,
        isVideo: item.isVideo,
        timestampMs: item.timestampMs,
      );

      recentThumbBytes[key] = bytes;
      recentThumbnails.insert(0, item);
      lastPhoto = item;
      unawaited(_saveLastPhoto());
      if (recentThumbnails.length > _maxRecentThumbnails) {
        final removed = recentThumbnails.removeLast();
        if (!recentThumbnails.any(
          (e) => _recentThumbKey(e) == _recentThumbKey(removed),
        )) {
          recentThumbBytes.remove(_recentThumbKey(removed));
        }
      }
      _scheduleThumbUpdate();
    } catch (_) {
      // The strip is cosmetic.
    } finally {
      _recentThumbInFlight.remove(key);
    }
  }

  Future<void> pickAndScanFolders({required bool isScanEntirePhone}) async {
    if (isScanning) return;

    final PickingMode scanMode = isScanEntirePhone
        ? PickingMode.device
        : PickingMode.folder;
    final ContentMode contentMode = selectedContentMode;

    String folderId;
    String uri;

    if (isScanEntirePhone) {
      folderId = IndexedFolderIdentity.device;
      uri = '';
    } else {
      final pickedUri = await LibraryService().pickFolderUri();
      if (pickedUri == null) {
        return;
      }
      uri = pickedUri;
      folderId = pickedUri;
    }

    await _beginScan(
      folderId: folderId,
      uri: uri,
      scanMode: scanMode,
      contentMode: contentMode,
    );
  }

  /// Resumes a scan interrupted by the system killing the app mid-run (see [checkForInterruptedScan]), with the same
  /// folderId and uri as before and no picker. The picker can be skipped for a folder scan because SafPickerActivity
  /// takes a persistable URI permission grant when the folder is first picked, so it is still valid after an app
  /// restart.
  Future<void> resumeInterruptedScan() async {
    final marker = interruptedScan;
    if (marker == null || isScanning) return;

    final scanMode = marker['mode'] == 'device'
        ? PickingMode.device
        : PickingMode.folder;
    final contentMode = ContentMode.values.firstWhere(
      (m) => m.name == marker['contentMode'],
      orElse: () => ContentMode.both,
    );

    await _beginScan(
      folderId: marker['folderId'] ?? '',
      uri: marker['uri'] ?? '',
      scanMode: scanMode,
      contentMode: contentMode,
    );
  }

  /// Forgets the interrupted scan when the person chose not to resume it, so it is not offered at every launch.
  Future<void> dismissInterruptedScan() async {
    interruptedScan = null;
    update();
    await _clearInterruptedScanMarker();
  }

  /// Starts a scan. [pickAndScanFolders] and [resumeInterruptedScan] share it.
  /// The notification permission is not requested here, because storage and media access is asked for right below and
  /// a second prompt would be one too many. The marker of an interrupted scan is written before the scan starts, not
  /// only on each progress tick, so that a kill before the first tick still leaves a marker to resume from. A clean
  /// finish, a stop or an immediate failure clears it.
  Future<void> _beginScan({
    required String folderId,
    required String uri,
    required PickingMode scanMode,
    required ContentMode contentMode,
  }) async {
    unawaited(_settings.checkBackgroundScanPermission());

    isScanning = true;
    isStopping = false;
    interruptedScan = null;
    scanSummary = null;
    scanResult = IndexedFolder.empty();
    recentEmbeddingsPerSecond = 0;
    _previousProgress = null;
    recentThumbnails = [];
    recentThumbBytes.clear();
    _recentThumbInFlight.clear();
    _lastRecentThumbFetch = null;
    _lastLiveStatsRefresh = null;
    _search.error = '';
    update();

    unawaited(
      _persistInterruptedScanMarker(
        folderId: folderId,
        uri: uri,
        scanMode: scanMode,
        contentMode: contentMode,
      ),
    );

    _listenToScanProgress();

    bool? result;
    try {
      result = await LibraryService().scan(
        folderId: folderId,
        pickingMode: scanMode,
        uri: uri,
        contentMode: contentMode,
      );
    } on ModelsNotReadyError {
      _models.modelsReady = false;
      _models.update();
      _search.error = 'Models are not downloaded yet.';
      result = null;
    }

    if (result == null || result == false) {
      isScanning = false;
      isStopping = false;
      _progressSub.cancel();
      unawaited(_clearInterruptedScanMarker());

      if (result != null) {
        scanResult = IndexedFolder.empty();
        update();
      }

      return;
    }
  }

  /// Follows the progress of a live scan, started in this session or resumed on app start. The bookkeeping for a
  /// normal finish runs here, when the last tick with done set arrives.
  /// The speed is measured over the time of indexing itself, because the waits while faces are found would make it
  /// look slow. A tick that embedded nothing is ignored, because a rate of 0 would flip the UI back to measuring
  /// speed. Only a scan that reached the end counts as completed, because a cancelled scan reports done too, with
  /// processed short of total.
  void _listenToScanProgress() {
    _progressSub = LibraryService().scanProgressStream().listen((data) {
      final newResult = IndexedFolder.fromMap(data);

      final prev = _previousProgress;
      if (prev != null) {
        final embeddedDelta = newResult.embedded - prev.embedded;
        final msDelta = newResult.activeMs - prev.activeMs;
        if (msDelta > 200 && embeddedDelta > 0) {
          recentEmbeddingsPerSecond = embeddedDelta / (msDelta / 1000.0);
        }
      }
      _previousProgress = newResult;
      scanResult = newResult;
      if (data['stopping'] == true) isStopping = true;
      final queued = data['faceQueue'];
      if (!newResult.done && queued is num) {
        faceQueueCount = queued.toInt();
        faceQueueMs = (data['faceQueueMs'] as num?)?.toInt() ?? 0;
        faceBatchPhotos = (data['faceBatchPhotos'] as num?)?.toInt() ?? 60;
        faceBatchMs = (data['faceBatchMs'] as num?)?.toInt() ?? 30000;
        faceQueueAt = DateTime.now();
      } else {
        faceQueueCount = null;
      }
      _maybeFetchNextRecentThumbnail(newResult.recentItems);
      _maybeRefreshLibraryStatsLive();

      if (scanResult.done) {
        isScanning = false;
        isStopping = false;
        _progressSub.cancel();
        unawaited(_saveLastPhoto(force: true));
        unawaited(_clearInterruptedScanMarker());
        final completed =
            scanResult.total > 0 && scanResult.processed >= scanResult.total;
        if (completed) {
          scanSummary = ScanSummary(
            total: scanResult.total,
            failed: scanResult.failed,
          );
          unawaited(_recordFailedForFolder(scanResult.id, scanResult.failed));
        }
        if (scanResult.id.isNotEmpty) {
          unawaited(_finishScan(folderId: scanResult.id));
        }
        unawaited(refreshLatestScan());
        unawaited(_settings.offerNotifications());
        if (completed && Get.isRegistered<StoriesController>()) {
          unawaited(Get.find<StoriesController>().scheduleReminderWhenReady());
        }
      }

      update();
    });
  }

  Future<void> _finishScan({required String folderId}) async {
    await addIndexedFolderToDb(indexedFolder: scanResult, folderId: folderId);
    await refreshLibraryStats();
    await getAllFoldersList();
    refreshCollections();
  }

  /// Resyncs with a scan that is still going on the native side. Removing the app from Recents does not kill the process,
  /// since the foreground service keeps it alive so the scan can finish, but it recreates the Activity and the Flutter
  /// engine. A scan started before that keeps running natively with nothing telling the fresh Dart layer about it.
  /// [onInit] calls this, and it reads the same cache that the notification reads from.
  Future<void> _resumeActiveScanIfAny() async {
    final progress = await LibraryService().getActiveScanProgress();
    if (progress == null) return;

    final restored = IndexedFolder.fromMap(progress);
    if (restored.done) return;

    scanResult = restored;
    _previousProgress = restored;
    recentEmbeddingsPerSecond = 0;
    isScanning = true;
    isStopping = progress['stopping'] == true;
    recentThumbnails = [];
    recentThumbBytes.clear();
    _recentThumbInFlight.clear();
    _lastRecentThumbFetch = null;
    _maybeFetchNextRecentThumbnail(restored.recentItems);

    _listenToScanProgress();
    update();
  }

  /// Offers to resume a scan that the system killed. [onInit] calls it right after [_resumeActiveScanIfAny], so it only
  /// matters when that found nothing still running natively. If a marker is still persisted then, the process that ran
  /// the scan is gone without a clean finish or stop, which for a scan with a foreground service and a wake lock means
  /// the system killed it (see [_persistInterruptedScanMarker] for when the marker is written and cleared). Showing that
  /// as "tap to resume" turns a silent failure into a one-tap fix, because the embedImages() call already skips by hash
  /// whatever it finished before, so resuming picks up where it left off.
  ///
  /// The Library does not show that as a banner of its own. The scan card shows it as paused, where the scan got to, and
  /// its button picks the scan up again. What the scan last reported is read from the native side. If that says the scan
  /// ended after all (it finished, or was stopped, while the app was away), there is nothing to resume: the scan is
  /// recorded as a scan that ended, as it would have been if the app had been open, and so is one that failed. A scan of a
  /// folder leaves the choice of where to look on One folder, so that the button picks that folder up again.
  @visibleForTesting
  Future<void> checkForInterruptedScan() async {
    if (isScanning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_interruptedScanKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map;
      final marker = decoded.map((k, v) => MapEntry(k as String, v as String));

      final last = await LibraryService().lastScanProgress();
      final reached = last == null ? null : IndexedFolder.fromMap(last);
      if (reached != null) {
        if (reached.total > 0) scanResult = reached;
        if (reached.done) {
          await _clearInterruptedScanMarker();
          update();
          if (reached.total > 0 && reached.id.isNotEmpty) {
            unawaited(
              _finishScan(folderId: reached.id).catchError((Object e) => debugPrint('Failed to record the ended scan: $e')),
            );
          }
          return;
        }
      }
      interruptedScan = marker;
      scanWholePhone = marker['mode'] != 'folder';
      update();
    } catch (e) {
      debugPrint('Failed to read interrupted-scan marker: $e');
    }
  }

  Future<void> _persistInterruptedScanMarker({
    required String folderId,
    required String uri,
    required PickingMode scanMode,
    required ContentMode contentMode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _interruptedScanKey,
        jsonEncode({
          'folderId': folderId,
          'uri': uri,
          'mode': scanMode.name,
          'contentMode': contentMode.name,
        }),
      );
    } catch (e) {
      debugPrint('Failed to persist interrupted-scan marker: $e');
    }
  }

  Future<void> _clearInterruptedScanMarker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_interruptedScanKey);
    } catch (e) {
      debugPrint('Failed to clear interrupted-scan marker: $e');
    }
  }

  /// The person has seen that the index was dropped for another search model, and what to do about it.
  Future<void> acknowledgeModelReset() async {
    modelResetFrom = 0;
    update();
    try {
      await LibraryService().acknowledgeModelReset();
    } catch (e) {
      debugPrint('Failed to acknowledge the model reset: $e');
    }
  }

  /// Reads the stats of the library again. It also backs the live stat tiles of the Library tab: besides the calls after
  /// a scan finishes and after clearing or deleting, it is called periodically while a scan runs (see
  /// [_listenToScanProgress]), so the numbers climb in real time.
  Future<void> refreshLibraryStats() async {
    final stats = await LibraryService().getLibraryStats();
    totalEmbeddings = stats.totalEmbeddings;
    modelResetFrom = stats.modelResetFrom;
    totalImages = stats.images;
    totalVideos = stats.videos;
    indexSizeBytes = stats.sizeBytes;
    update();
  }

  /// Calls [refreshLibraryStats] at most every two seconds and not on every progress tick, which comes twice a second.
  /// It re-reads the whole embeddings store from disk, and doing that on every tick would compete with the I/O of the
  /// scan for a large library, for no real benefit.
  void _maybeRefreshLibraryStatsLive() {
    final now = DateTime.now();
    if (_lastLiveStatsRefresh != null &&
        now.difference(_lastLiveStatsRefresh!) < const Duration(seconds: 2)) {
      return;
    }
    _lastLiveStatsRefresh = now;
    unawaited(refreshLibraryStats());
  }

  /// Shows "Stopping" right away: the scan only ends once the work in hand is finished, and
  /// without feedback a second tap looked necessary. Repeated taps are ignored meanwhile.
  Future<void> stopScanning() async {
    if (!isScanning || isStopping) return;
    isStopping = true;
    update();
    try {
      final asked = await LibraryService().cancelScanning();
      if (!asked && isScanning) {
        isStopping = false;
        update();
      }
    } catch (_) {
      // The stop never reached the scan: offer the button again.
      isStopping = false;
      update();
    }
  }

  /// embedded is fetched fresh from native rather than accumulated here,
  /// since native's per-scan numbers only describe that one scan.
  Future<void> addIndexedFolderToDb({
    required IndexedFolder indexedFolder,
    required String folderId,
  }) async {
    if (indexedFolder.path.isEmpty) return;

    final embeddedForFolder = await LibraryService().getEmbeddingCountForFolder(
      folderId: folderId,
    );

    final toSave = indexedFolder.copyWith(
      id: folderId,
      embedded: embeddedForFolder,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await db.upsertFolder(folder: toSave);
    update();
  }

  Future<void> clearAllEmbeddings() async {
    _failedByFolder.clear();
    totalFailed = 0;
    unawaited(_persistFailedByFolder());
    await LibraryService().clearEmbeddings();
    autoIndexedAtMs = 0;
    autoIndexed = const AutoIndexedBatch();
    await db.clearFolderList();
    await getAllFoldersList();
    await refreshLibraryStats();
    refreshCollections();
    update();
  }

  Future<void> deleteEmbeddingsByFolderid({required String folderId}) async {
    await LibraryService().deleteEmbeddingsByFolderId(folderId: folderId);
  }

  Future<void> deleteFolderById({required String id}) async {
    await _recordFailedForFolder(id, 0);
    await deleteEmbeddingsByFolderid(folderId: id);
    await db.deleteById(id);
    await getAllFoldersList();
    await refreshLibraryStats();
    refreshCollections();
  }

  Future<void> getAllFoldersList() async {
    allIndexedFoldersList = await db.getAllFolders();
    update();
  }

  /// Milliseconds indexing has left at the speed so far; null until enough has been done for the figure to mean
  /// something. It is based on the whole-scan average, because an estimate that jumps with every wobble of the recent
  /// rate is more distracting than useful.
  int? get scanEtaMs {
    if (!isScanning) return null;
    final total = scanResult.total;
    final processed = scanResult.processed;
    if (total <= 0 || processed < 20 || processed >= total) return null;
    if (scanResult.elapsedMs < 8000) return null;

    final msPerItem = scanResult.elapsedMs / processed;
    return (msPerItem * (total - processed)).round();
  }

  String? get scanEtaText {
    final ms = scanEtaMs;
    return ms == null ? null : formatDuration(milliseconds: ms);
  }

  String formatDuration({required num milliseconds}) {
    if (milliseconds <= 0) return '0 Seconds';

    int totalSeconds = (milliseconds / 1000).floor();

    final int days = totalSeconds ~/ 86400;
    totalSeconds %= 86400;

    final int hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;

    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;

    final List<String> parts = [];

    if (days > 0) parts.add('$days ${days == 1 ? 'Day' : 'Days'}');
    if (hours > 0) parts.add('$hours ${hours == 1 ? 'Hour' : 'Hours'}');
    if (minutes > 0) {
      parts.add('$minutes ${minutes == 1 ? 'Minute' : 'Minutes'}');
    }
    if (seconds > 0) {
      parts.add('$seconds ${seconds == 1 ? 'Second' : 'Seconds'}');
    }

    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;

    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  Future<bool> requestMediaPermission({
    required ContentMode contentMode,
    Future<bool> Function()? explain,
  }) async {
    if (!Platform.isAndroid) return true;

    final bool needsImages =
        contentMode == ContentMode.images || contentMode == ContentMode.both;
    final bool needsVideos =
        contentMode == ContentMode.videos || contentMode == ContentMode.both;

    final List<Permission> required = [
      if (needsImages) Permission.photos,
      if (needsVideos) Permission.videos,
    ];

    if (required.isEmpty) return true;

    return askPermission(AppPermission.media, only: required, explain: explain);
  }

  getPickingModeString({required PickingMode pickingMode}) {
    switch (pickingMode) {
      case PickingMode.device:
        return 'device';
      case PickingMode.folder:
        return 'folder';
    }
  }

  getContentModeString({required ContentMode contentMode}) {
    switch (contentMode) {
      case ContentMode.both:
        return 'both';
      case ContentMode.images:
        return 'images';
      case ContentMode.videos:
        return 'videos';
    }
  }

  /// Where the next scan looks: the whole phone (how it always starts), or one folder that is
  /// picked when the chip is tapped.
  bool scanWholePhone = true;

  void setScanWholePhone(bool value) {
    if (scanWholePhone == value) return;
    scanWholePhone = value;
    update();
  }

  void toggleSelectedContentMode({required ContentMode contentMode}) {
    selectedContentMode = contentMode;
    update();
    unawaited(persistString(_contentModeKey, contentMode.name));
  }
}
