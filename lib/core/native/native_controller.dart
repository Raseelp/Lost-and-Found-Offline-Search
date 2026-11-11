import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/library/db/indexed_folder_db_helper.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';
import 'package:lost_and_found/core/media/meta_data_model.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';
import 'package:lost_and_found/core/native/native_services.dart';
import 'package:lost_and_found/features/search/services/query_words.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/core/permissions/permission_prompt.dart';

/// The state behind the Search, Collections and Library tabs: scans, searches, the search models and the permissions
/// they need.
class NativeController extends GetxController with WidgetsBindingObserver {
  static const _contentModeKey = 'scan_content_mode';
  static const _resultsLayoutKey = 'results_layout';
  static const _resultsLimitKey = 'results_limit';
  static const _searchContentModeKey = 'search_content_mode';
  static const _interruptedScanKey = 'interrupted_scan';
  /// Holds, for each folder id, how many files could not be embedded the last time that location finished scanning.
  static const _failedByFolderKey = 'failed_by_folder';

  @override
  onInit() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadPersistedPreferences();
    unawaited(_loadBenchLogs());
    unawaited(_loadIndexNudge());
    await checkModelsReady();
    await getAllFoldersList();
    await refreshLibraryStats();
    await checkBackgroundScanPermission();
    await _resumeActiveScanIfAny();
    await _checkForInterruptedScan();
    _refreshCollections();
    unawaited(refreshLatestScan());
    super.onInit();
  }

  /// Scores the collections again. Their counts and covers depend on the index, so anything that changes it (startup once
  /// the models are known, a finished scan, a clear) calls this. The collections controller is registered right after
  /// this one, so it may not exist yet at the very start.
  void _refreshCollections() {
    if (Get.isRegistered<CollectionsController>()) {
      unawaited(Get.find<CollectionsController>().refreshStats());
    }
  }

  /// Loads the standing preferences: the scan mode, the results layout, the results limit and the search mode. They are
  /// loaded once before anything else needs them, so the UI opens showing what the person picked last time. If loading
  /// fails the app opens with the defaults, since blocking startup is never worth it.
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

      final layoutName = prefs.getString(_resultsLayoutKey);
      if (layoutName != null) {
        resultsLayout = ResultsLayout.values.firstWhere(
          (l) => l.name == layoutName,
          orElse: () => ResultsLayout.bento,
        );
      }

      final limit = prefs.getDouble(_resultsLimitKey);
      if (limit != null) {
        sliderValue = limit.clamp(10, 100).toDouble();
      }

      final failedRaw = prefs.getString(_failedByFolderKey);
      if (failedRaw != null) {
        final decoded = jsonDecode(failedRaw) as Map;
        _failedByFolder
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k as String, v as int)));
        totalFailed = _failedByFolder.values.fold(0, (a, b) => a + b);
      }

      final searchModeName = prefs.getString(_searchContentModeKey);
      if (searchModeName != null) {
        searchContentMode = ContentMode.values.firstWhere(
          (m) => m.name == searchModeName,
          orElse: () => ContentMode.both,
        );
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
    searchFocusNode.dispose();
    super.onClose();
  }

  /// Checks the notification permission again on resume. A permanently denied permission hands off to the system
  /// settings screen (see [requestBackgroundScanPermission]) and returns at once, well before the person has answered,
  /// so checking right after that call reads the answer too early and leaves the "Enable" control showing stale state.
  /// The check on resume catches the real answer when the person comes back. The latest scan is read again too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkBackgroundScanPermission());
      unawaited(refreshLatestScan());
      if (_offerNotificationsPending) {
        _offerNotificationsPending = false;
        unawaited(_offerNotifications());
      }
    }
  }

  static const _notificationsOfferedKey = 'notifications_offered';
  bool _offerNotificationsPending = false;
  bool _offeringNotifications = false;

  /// After the first scan ends, finished or stopped, asks once whether the app may send notifications. The daily memory
  /// and the stories note are on by default and cannot come without it. Nothing is asked if it is already allowed, and
  /// a scan that ends while the app is in the background asks when the app is next opened.
  Future<void> _offerNotifications() async {
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

  Future<void> refreshLatestScan() async {
    final items = await NativeServices().takeLatestScan();
    if (items.isEmpty) return;
    latestScanUris = items.toSet();
    update();
  }

  /// Which home tab is showing: 0 Search, 1 Collections, 2 Library. It lives here and not in the state of the home
  /// screen, so that something opened from another tab, such as a photo inside a collection, can send the person to
  /// Search.
  int homeTab = 0;

  void setHomeTab(int index) {
    if (homeTab == index) return;
    homeTab = index;
    update();
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
  double sliderValue = 20;
  List<Map<String, dynamic>> searchResults = [];
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

  /// Whether the system will show the scan-progress notification (see ScanForegroundService on the native side). It is
  /// never requested automatically, because storage and media access is asked for right before a scan and asking for
  /// both at once overwhelms people. The scanning UI offers its own "Enable" control instead. This only reflects the
  /// current answer of the system, checked when the app opens and whenever a scan starts.
  bool backgroundNotificationsGranted = false;
  bool isSearching = false;
  bool isFetchingMetadata = false;
  bool showMetadata = false;
  String error = '';
  String scannedPath = '';
  /// Recognises one named person typed plainly, or picked with "@", inside the query itself. See
  /// [MentionTextEditingController] for how [runSearch] uses it.
  final MentionTextEditingController searchTextController =
      MentionTextEditingController(
        peopleProvider: () => Get.isRegistered<FacesController>()
            ? Get.find<FacesController>().people
            : const [],
      );
  /// The focus of the search box, held here so the Search button of the navigation bar can put the cursor in it.
  final FocusNode searchFocusNode = FocusNode();
  ContentMode selectedContentMode = ContentMode.both;
  /// What a search is filtered to include. It is separate from [selectedContentMode], which governs scanning (what to
  /// embed) and not searching (what to search across). The search filter sheet sets it through [setSearchContentMode].
  ContentMode searchContentMode = ContentMode.both;
  final Map<String, Uint8List> imageCache = {};

  /// The image attached for a reverse-image search. It is held here and shown as a preview chip until the person
  /// submits, just as typing text does not search until Search is pressed.
  String? pickedSearchImageUri;
  /// Set only when the attached image is really one frame of a video. The uri is then the video's and not a photo's. See
  /// [searchWithVideoFrame].
  int? pickedSearchVideoTimestampMs;
  Uint8List? pickedSearchImageBytes;

  /// The last submitted text query, if that is how the results on screen were found; null after an image search.
  /// [runSearch] sets it and [loadMatchExplanation] reads it when a result is opened.
  /// It is the phrase with the mentions stripped, because CLIP has no concept of a name. [lastMentionedPersonIds] and
  /// [lastMentionedPeopleNames] are kept separately, because [searchTextController] may have been edited for the next
  /// search by the time something asks.
  String? lastTextQuery;
  List<int> lastMentionedPersonIds = [];
  List<String> lastMentionedPeopleNames = [];

  /// The free text of the last search with any mentioned names put back in front of it. This is what a "save as
  /// collection" name or query field should show, since [lastTextQuery] alone drops the names.
  String get lastQueryWithMentions {
    final text = lastTextQuery ?? '';
    if (lastMentionedPeopleNames.isEmpty) return text;
    final names = lastMentionedPeopleNames.join(' and ');
    return text.isEmpty ? names : '$names $text';
  }

  /// Set when the results on screen came from an image search (a picked photo, "search with this image" or a video
  /// frame). "Save as collection" turns it into a photo-seeded collection. It is null after a text search.
  String? lastImageSeedUri;
  int? lastImageSeedTimestampMs;

  /// "Why this matched" for the result that is open (see [loadMatchExplanation]). It is empty until that resolves, or
  /// when there is nothing to explain, as after an image search or a query with no real content words.
  List<MapEntry<String, double>> matchExplanation = [];

  /// The results of "Similar to this", the small strip shown from the viewer in place of the full search. It has its own
  /// list and thumbnail cache, separate from [searchResults] and [imageCache], because those hold a different and much
  /// larger result set that a real search would clear and replace. See [loadSimilar].
  List<Map<String, dynamic>> similarResults = [];
  final Map<String, Uint8List> similarThumbCache = {};
  bool isLoadingSimilar = false;

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
  final Map<String, Uint8List> recentThumbBytes = {};
  final Set<String> _recentThumbInFlight = {};
  DateTime? _lastRecentThumbFetch;

  /// Throttles the live refresh of the stats of the Library tab during a scan (see [_maybeRefreshLibraryStatsLive]).
  DateTime? _lastLiveStatsRefresh;

  final db = IndexedFolderDbHelper.instance;
  ImageMetadata selectedMetadata = ImageMetadata.empty();

  List<IndexedFolder> allIndexedFoldersList = [];

  /// Whether the search (CLIP) models are ready. They are the only models downloaded, since the face models are part of
  /// the app. The setup screen shows until this is true.
  bool modelsReady = false;
  bool isCheckingModels = true;
  List<ModelStatus> modelStatuses = [];
  bool isDownloadingModels = false;
  ModelDownloadProgress downloadProgress = ModelDownloadProgress.empty();
  String downloadError = '';
  StreamSubscription<ModelDownloadProgress>? _downloadSub;

  /// The download speed in bytes per second over the last few seconds, smoothed. It is null until there is a reading.
  double? downloadBytesPerSecond;
  DateTime? _speedAt;
  int _speedBytes = 0;

  /// Time left at the current speed, or null while unknown.
  Duration? get downloadEta {
    final rate = downloadBytesPerSecond;
    final progress = downloadProgress;
    if (rate == null || rate <= 0 || progress.overallTotalBytes == 0) {
      return null;
    }
    final left = progress.overallTotalBytes - progress.overallBytesDownloaded;
    if (left <= 0) return null;
    return Duration(seconds: (left / rate).round());
  }

  void _updateDownloadSpeed(ModelDownloadProgress progress) {
    final now = DateTime.now();
    final at = _speedAt;
    if (at == null || progress.overallBytesDownloaded < _speedBytes) {
      _speedAt = now;
      _speedBytes = progress.overallBytesDownloaded;
      return;
    }
    final seconds = now.difference(at).inMilliseconds / 1000.0;
    if (seconds < 1.0) return;
    final instant = (progress.overallBytesDownloaded - _speedBytes) / seconds;
    downloadBytesPerSecond = downloadBytesPerSecond == null
        ? instant
        : downloadBytesPerSecond! * 0.6 + instant * 0.4;
    _speedAt = now;
    _speedBytes = progress.overallBytesDownloaded;
  }

  List<ModelStatus> get _searchModels =>
      modelStatuses.where((m) => m.group == 'search').toList();

  /// Size of the search (CLIP) models together.
  int get searchModelBytes =>
      _searchModels.fold<int>(0, (sum, m) => sum + m.sizeBytes);

  /// True once the search models are downloaded and verified.
  bool get searchModelsVerified =>
      _searchModels.isNotEmpty && _searchModels.every((m) => m.verified);

  /// What the setup screen's button would download (whatever isn't there yet).
  int get pendingDownloadBytes {
    var total = 0;
    if (!searchModelsVerified) total += searchModelBytes;
    return total;
  }

  /// Redoes the things computed while the models were missing. Collection counts and covers are empty then, and nothing
  /// else would redo them when the search models come back, by a finished download or a check that finds them.
  Future<void> _modelsBecameReady() async {
    await refreshLibraryStats();
    _refreshCollections();
  }

  Future<void> checkModelsReady() async {
    final wasReady = modelsReady;
    try {
      modelsReady = await NativeServices().areModelsReady();
      modelStatuses = await NativeServices().getModelInfo();
    } finally {
      isCheckingModels = false;
      update();
    }
    if (!wasReady && modelsReady) unawaited(_modelsBecameReady());
  }

  /// Downloads the search models if they are not on the device yet. Whatever happened, cancelled or failed, it ends by
  /// reading what is really on the device, because the setup screen goes by that.
  Future<void> startModelDownload() async {
    if (isDownloadingModels) return;

    isDownloadingModels = true;
    downloadError = '';
    downloadProgress = ModelDownloadProgress.empty();
    downloadBytesPerSecond = null;
    _speedAt = null;
    _speedBytes = 0;
    update();

    _downloadSub = NativeServices().modelDownloadProgressStream().listen((
      progress,
    ) {
      downloadProgress = progress;
      _updateDownloadSpeed(progress);
      update();
    });

    try {
      await NativeServices().downloadModels();
    } on PlatformException catch (e) {
      downloadError = e.message ?? e.code;
    } catch (e) {
      downloadError = e.toString();
    } finally {
      await _downloadSub?.cancel();
      _downloadSub = null;
      final wasReady = modelsReady;
      try {
        modelsReady = await NativeServices().areModelsReady();
        modelStatuses = await NativeServices().getModelInfo();
      } catch (_) {}
      isDownloadingModels = false;
      update();
      if (!wasReady && modelsReady) unawaited(_modelsBecameReady());
    }
  }

  Future<void> cancelModelDownload() async {
    await NativeServices().cancelModelDownload();
  }

  /// Deletes the downloaded (search) models. The app then falls back to the setup screen
  /// (see AppGate); the face models are part of the app and stay.
  Future<void> deleteModels() async {
    await NativeServices().deleteModels();
    downloadError = '';
    await checkModelsReady();
  }

  /// Picks an image and previews it without searching. As with typing text, nothing runs until the person submits.
  Future<void> pickSearchImage() async {
    final uri = await NativeServices().pickImageForSearching();
    if (uri == null) return;

    pickedSearchImageUri = uri;
    pickedSearchVideoTimestampMs = null;
    pickedSearchImageBytes = null;
    update();

    try {
      pickedSearchImageBytes = await NativeServices().loadImageBytes(
        uri: uri,
        isCompressed: true,
      );
    } catch (_) {
      // Only the preview is missing, the search works from the uri alone.
    }
    update();
  }

  /// "Search with this image" from the full-screen viewer. It attaches the photo as if it had been picked from the
  /// search bar and runs the same search. The text box is cleared, because stale text would show up again the moment the
  /// image chip is removed, even though an attached image takes priority in [runSearch]. The match explanation of the
  /// previous result goes too, since it described a different search.
  Future<void> searchWithImage({
    required String uri,
    required Uint8List bytes,
  }) {
    homeTab = 0;
    pickedSearchImageUri = uri;
    pickedSearchImageBytes = bytes;
    pickedSearchVideoTimestampMs = null;
    searchTextController.clear();
    matchExplanation = [];
    update();
    return runSearch();
  }

  /// The same from the video viewer, where the image is one frame of a video. The picked uri is the video's and the
  /// timestamp says which frame (see [runSearch]). The preview bytes are that same frame, fetched here because the chip
  /// of the search bar needs something to show.
  Future<void> searchWithVideoFrame({
    required String uri,
    required int timestampMs,
  }) async {
    homeTab = 0;
    pickedSearchImageUri = uri;
    pickedSearchVideoTimestampMs = timestampMs;
    pickedSearchImageBytes = null;
    searchTextController.clear();
    matchExplanation = [];
    update();

    try {
      pickedSearchImageBytes = await NativeServices().loadVideoThumbnail(
        uri: uri,
        timestampMs: timestampMs,
      );
    } catch (_) {
      // Only the preview is missing, the search does not need it.
    }
    update();

    await runSearch();
  }

  /// Counts the calls of [loadSimilar] and [clearSimilar]. The results are shared, single-instance state and nothing
  /// stops two calls from overlapping: the strip can be closed while a fetch is in flight, or opened again for a
  /// different photo before the first fetch finished. Without the token the call that resolves last would win, whether
  /// or not it is the one still wanted, and would fill the results for a photo the viewer has moved on from.
  int _similarToken = 0;

  /// Loads Similar to this: the same embedding search as [searchWithImage] and [searchWithVideoFrame], but a strip of
  /// about ten results in the viewer. A [timestampMs] means the seed is one frame of a video.
  /// The limit is 13 for the ten wanted, because the seed always comes back as its own best match and the extra three
  /// cover dropping it.
  /// Thumbnails load three at a time and the screen is updated once per three, because update() rebuilds the whole
  /// viewer screen.
  Future<void> loadSimilar({required String uri, int? timestampMs}) async {
    final token = ++_similarToken;
    similarResults = [];
    similarThumbCache.clear();
    isLoadingSimilar = true;
    update();

    try {
      final raw = timestampMs != null
          ? await NativeServices().searchByVideoFrame(
              uri: uri,
              timestampMs: timestampMs,
              limit: 13,
              contentMode: ContentMode.both,
            )
          : await NativeServices().searchByImage(
              uri: uri,
              limit: 13,
              contentMode: ContentMode.both,
            );
      if (token != _similarToken) {
        return;
      }

      similarResults = raw
          .where((item) => (item['path'] as String?) != uri)
          .take(10)
          .toList();
      update();

      const workers = 3;
      var next = 0;
      var sinceUpdate = 0;
      Future<void> worker() async {
        while (true) {
          if (token != _similarToken) return;
          final i = next++;
          if (i >= similarResults.length) return;
          final item = similarResults[i];
          try {
            final bytes = await NativeServices().loadThumbnail(
              uri: item['path'] as String,
              isVideo: item['isVideo'] as bool? ?? false,
              timestampMs: (item['timestampMs'] as num?)?.toInt() ?? 0,
              size: 300,
            );
            if (token != _similarToken) return;
            similarThumbCache[cacheKeyForResult(item)] = bytes;
          } catch (_) {}
          if (token == _similarToken && ++sinceUpdate >= 3) {
            sinceUpdate = 0;
            update();
          }
        }
      }

      await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    } on ModelsNotReadyError {
      // The viewer says elsewhere that the models are not ready.
    } catch (_) {
      // The viewer is fully usable without the strip.
    } finally {
      if (token == _similarToken) {
        isLoadingSimilar = false;
        update();
      }
    }
  }

  /// Empties the strip. A load still in flight is invalidated, so it cannot fill the results again afterwards.
  void clearSimilar() {
    _similarToken++;
    similarResults = [];
    similarThumbCache.clear();
    isLoadingSimilar = false;
  }

  /// Whether the search bar is in photo mode (find similar moments from a photo) rather than
  /// describing. A photo that is attached counts as photo mode whatever this says.
  bool searchPhotoMode = false;

  /// Switches the bar between describing and searching with a photo. Going back to describing
  /// lets go of an attached photo.
  void setSearchPhotoMode(bool value) {
    searchPhotoMode = value;
    if (!value && pickedSearchImageUri != null) {
      clearPickedSearchImage();
      return;
    }
    update();
  }

  void clearPickedSearchImage() {
    pickedSearchImageUri = null;
    pickedSearchImageBytes = null;
    pickedSearchVideoTimestampMs = null;
    update();
  }

  /// Puts the Search tab back to before any search: no results, an empty bar. A search still
  /// loading is dropped (its tiles stop loading).
  void clearSearch() {
    _searchRun++;
    isSearching = false;
    error = '';
    searchResults = [];
    imageCache.clear();
    matchExplanation = [];
    lastTextQuery = null;
    lastMentionedPersonIds = [];
    lastMentionedPeopleNames = [];
    lastImageSeedUri = null;
    lastImageSeedTimestampMs = null;
    pickedSearchImageUri = null;
    pickedSearchImageBytes = null;
    pickedSearchVideoTimestampMs = null;
    searchTextController.clear();
    update();
  }

  /// Counts the searches, so a search that was replaced by a newer one stops loading its tiles.
  int _searchRun = 0;

  /// The one submit action, whichever input is active. An attached image takes priority over typed text, and the two
  /// are never used together.
  /// People recognised in the text narrow the search to photos and videos with all of them in it. Their names are
  /// dropped from what is sent to CLIP, which has no concept of a name. Tiles load three at a time, because the native
  /// side decodes on three threads. A cleared or replaced search stops, and an older one leaves [isSearching] to the
  /// newer.
  Future<void> runSearch() async {
    final run = ++_searchRun;
    final imageUri = pickedSearchImageUri;
    final rawQuery = searchTextController.text.trim();
    if (imageUri == null && rawQuery.isEmpty) return;

    try {
      isSearching = true;
      error = '';
      update();
      searchResults = [];
      imageCache.clear();

      if (imageUri != null) {
        lastTextQuery = null;
        lastMentionedPersonIds = [];
        lastMentionedPeopleNames = [];
        final frameMs = pickedSearchVideoTimestampMs;
        lastImageSeedUri = imageUri;
        lastImageSeedTimestampMs = frameMs;
        final found = frameMs != null
            ? await NativeServices().searchByVideoFrame(
                uri: imageUri,
                timestampMs: frameMs,
                limit: sliderValue.round().toInt(),
                contentMode: searchContentMode,
              )
            : await NativeServices().searchByImage(
                uri: imageUri,
                limit: sliderValue.round().toInt(),
                contentMode: searchContentMode,
              );
        if (run != _searchRun) return;
        searchResults = found;
      } else {
        final mentionedPeople = <int, Person>{
          for (final p in searchTextController.recognizedPeople) p.id: p,
        }.values.toList();
        final mentionedIds = mentionedPeople.map((p) => p.id).toList();
        final query = searchTextController.queryWithoutMention;
        lastTextQuery = query;
        lastMentionedPersonIds = mentionedIds;
        lastMentionedPeopleNames = mentionedPeople.map((p) => p.name!).toList();
        lastImageSeedUri = null;
        lastImageSeedTimestampMs = null;
        final found = await NativeServices().searchImages(
          query: query,
          limitNumber: sliderValue.round().toInt(),
          contentMode: searchContentMode,
          personIds: mentionedIds,
        );
        if (run != _searchRun) return;
        searchResults = found;
      }

      debugPrint(searchResults.toString());

      final pending = [
        for (final item in searchResults)
          if (!imageCache.containsKey(cacheKeyForResult(item))) item,
      ];
      var nextPending = 0;
      Future<void> loadTiles() async {
        while (run == _searchRun && nextPending < pending.length) {
          final item = pending[nextPending++];
          final uri = item['path'] as String;
          final isVideo = item['isVideo'] as bool? ?? false;
          final timestampMs = (item['timestampMs'] as num?)?.toInt() ?? 0;
          try {
            if (isVideo) {
              final bytes = await NativeServices().loadVideoThumbnail(
                uri: uri,
                timestampMs: timestampMs,
              );
              imageCache[cacheKeyForResult(item)] = bytes;
            } else {
              final bytes = await NativeServices().loadImageBytes(
                uri: uri,
                isCompressed: true,
              );
              imageCache[cacheKeyForResult(item)] = bytes;
            }
          } catch (_) {}
        }
      }

      await Future.wait([for (var i = 0; i < 3; i++) loadTiles()]);
    } on ModelsNotReadyError {
      modelsReady = false;
      error = 'Models are not downloaded yet.';
    } finally {
      if (run == _searchRun) isSearching = false;
      update();
    }
  }

  String cacheKeyForResult(Map<String, dynamic> item) {
    final uri = item['path'] as String;
    final isVideo = item['isVideo'] as bool? ?? false;
    final timestampMs = (item['timestampMs'] as num?)?.toInt() ?? 0;
    return isVideo ? '$uri@$timestampMs' : uri;
  }

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
      final bytes = await NativeServices().loadThumbnail(
        uri: item.uri,
        isVideo: item.isVideo,
        timestampMs: item.timestampMs,
      );

      recentThumbBytes[key] = bytes;
      recentThumbnails.insert(0, item);
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
      final pickedUri = await NativeServices().pickFolderUri();
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

  /// Resumes a scan interrupted by the system killing the app mid-run (see [_checkForInterruptedScan]), with the same
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
    unawaited(checkBackgroundScanPermission());

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
    error = '';
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
      result = await NativeServices().scan(
        folderId: folderId,
        pickingMode: scanMode,
        uri: uri,
        contentMode: contentMode,
      );
    } on ModelsNotReadyError {
      modelsReady = false;
      error = 'Models are not downloaded yet.';
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
    _progressSub = NativeServices().scanProgressStream().listen((data) {
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
        unawaited(_offerNotifications());
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
    _refreshCollections();
  }

  /// Resyncs with a scan that is still going on the native side. Removing the app from Recents does not kill the process,
  /// since the foreground service keeps it alive so the scan can finish, but it recreates the Activity and the Flutter
  /// engine. A scan started before that keeps running natively with nothing telling the fresh Dart layer about it.
  /// [onInit] calls this, and it reads the same cache that the notification reads from.
  Future<void> _resumeActiveScanIfAny() async {
    final progress = await NativeServices().getActiveScanProgress();
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
  Future<void> _checkForInterruptedScan() async {
    if (isScanning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_interruptedScanKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map;
      interruptedScan = decoded.map(
        (k, v) => MapEntry(k as String, v as String),
      );
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
      await NativeServices().acknowledgeModelReset();
    } catch (e) {
      debugPrint('Failed to acknowledge the model reset: $e');
    }
  }

  /// Reads the stats of the library again. It also backs the live stat tiles of the Library tab: besides the calls after
  /// a scan finishes and after clearing or deleting, it is called periodically while a scan runs (see
  /// [_listenToScanProgress]), so the numbers climb in real time.
  Future<void> refreshLibraryStats() async {
    final stats = await NativeServices().getLibraryStats();
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

  Future<Uint8List> loadImageByURI({
    required String uri,
    bool? isCompressed,
  }) async {
    return await NativeServices().loadImageBytes(
      uri: uri,
      isCompressed: isCompressed ?? true,
    );
  }

  /// Loads the metadata of one photo or video. It resets the previous metadata first, so the sheet does not open with the
  /// metadata of the previous photo.
  Future<void> loadMetaDataByUri({
    required String uri,
    bool isVideo = false,
  }) async {
    showMetadata = false;
    selectedMetadata = ImageMetadata.empty();
    isFetchingMetadata = true;
    update();
    final data = await NativeServices().loadMetadataByUri(
      uri: uri,
      isVideo: isVideo,
    );
    if (data != null) {
      selectedMetadata = data;
    }
    isFetchingMetadata = false;
    update();
  }

  /// Shares a file. This and the other actions of the actions sheet of both viewers pass straight through to the native
  /// side, since the work (share intent, MediaStore copy, wallpaper, clipboard) only makes sense there. Feedback such as
  /// a snackbar is the job of the calling widget, because it needs a BuildContext that these do not have.
  Future<void> shareFile({required String uri, required bool isVideo}) {
    return NativeServices().shareFile(uri: uri, isVideo: isVideo);
  }

  Future<bool> saveFileCopy({required String uri, required bool isVideo}) {
    return NativeServices().saveCopyToGallery(uri: uri, isVideo: isVideo);
  }

  Future<bool> setPhotoAsWallpaper({required String uri}) {
    return NativeServices().setAsWallpaper(uri: uri);
  }

  Future<bool> copyImageToClipboard({required String uri}) {
    return NativeServices().copyImageToClipboard(uri: uri);
  }

  /// Loads "Why this matched" for a result. It is called when a result is opened and not for every result a search
  /// returns (see [NativeServices.explainMatch] for why it is lazy). [matchExplanation] stays empty, with no loading
  /// state and no error, whenever there is nothing honest to show: after an image search, or for a query with no real
  /// content words such as just "photos of it". The section of the UI that it backs does not appear then. A [query] is
  /// set when the result was opened from somewhere other than a text search, such as a collection, and explains the
  /// match by that phrase.
  Future<void> loadMatchExplanation({
    required String path,
    required bool isVideo,
    required int timestampMs,
    String? query,
  }) async {
    matchExplanation = [];

    query ??= lastTextQuery;
    if (query == null || query.isEmpty) {
      update();
      return;
    }
    final words = extractContentWords(query);
    if (words.isEmpty) {
      update();
      return;
    }
    update();

    final raw = await NativeServices().explainMatch(
      path: path,
      isVideo: isVideo,
      timestampMs: timestampMs,
      words: words,
    );

    final entries =
        raw
            .map(
              (m) => MapEntry(
                m['word'] as String,
                (m['score'] as num?)?.toDouble() ?? 0.0,
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    matchExplanation = entries.take(3).toList();
    update();
  }

  /// Shows "Stopping" right away: the scan only ends once the work in hand is finished, and
  /// without feedback a second tap looked necessary. Repeated taps are ignored meanwhile.
  Future<void> stopScanning() async {
    if (!isScanning || isStopping) return;
    isStopping = true;
    update();
    try {
      final asked = await NativeServices().cancelScanning();
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

    final embeddedForFolder = await NativeServices().getEmbeddingCountForFolder(
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

  /// Timing logs for indexing and face finding (adb logcat -s LostFoundBench). The
  /// switch itself lives natively, where the logs are written; this mirrors it.
  bool benchLogsEnabled = true;

  Future<void> _loadBenchLogs() async {
    try {
      benchLogsEnabled = await NativeServices().benchLogsEnabled();
      update();
    } catch (_) {
      // Stays on, the default.
    }
  }

  Future<void> setBenchLogsEnabled(bool value) async {
    benchLogsEnabled = value;
    update();
    await NativeServices().setBenchLogsEnabled(value);
  }

  /// The note that asks to finish indexing (see IndexNudge): on until turned off. The switch lives natively, where
  /// the note is made; this mirrors it.
  bool indexNudgeEnabled = true;

  Future<void> _loadIndexNudge() async {
    try {
      indexNudgeEnabled = await NativeServices().indexNudgeEnabled();
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
    await NativeServices().setIndexNudgeEnabled(on);
    return on;
  }

  Future<void> clearAllEmbeddings() async {
    _failedByFolder.clear();
    totalFailed = 0;
    unawaited(_persistFailedByFolder());
    await NativeServices().clearEmbeddings();
    await db.clearFolderList();
    await getAllFoldersList();
    await refreshLibraryStats();
    _refreshCollections();
    update();
  }

  Future<void> deleteEmbeddingsByFolderid({required String folderId}) async {
    await NativeServices().deleteEmbeddingsByFolderId(folderId: folderId);
  }

  Future<void> deleteFolderById({required String id}) async {
    await _recordFailedForFolder(id, 0);
    await deleteEmbeddingsByFolderid(folderId: id);
    await db.deleteById(id);
    await getAllFoldersList();
    await refreshLibraryStats();
    _refreshCollections();
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

  void toggleMetadata() {
    showMetadata = !showMetadata;
    update();
  }

  /// Closes the sheet, and never opens it. It is for anything that should only close it (tapping the photo, dragging
  /// the sheet down).
  void hideMetadata() {
    if (!showMetadata) return;
    showMetadata = false;
    update();
  }

  void setSliderValue(double value) {
    sliderValue = value;
    update();
    unawaited(_persistDouble(_resultsLimitKey, value));
  }

  Future<bool> requestMediaPermission({
    required ContentMode contentMode,
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

    return askPermission(AppPermission.media, only: required);
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
    unawaited(_persistString(_contentModeKey, contentMode.name));
  }

  /// Committed from the search filter sheet's draft state, only once the user taps Confirm (see _SearchFilterSheet).
  /// Whether this also re-runs the current search is that widget's call, not this setter's.
  void setSearchContentMode(ContentMode contentMode) {
    searchContentMode = contentMode;
    update();
    unawaited(_persistString(_searchContentModeKey, contentMode.name));
  }

  ResultsLayout resultsLayout = ResultsLayout.bento;

  void setResultsLayout(ResultsLayout layout) {
    resultsLayout = layout;
    update();
    unawaited(_persistString(_resultsLayoutKey, layout.name));
  }
/// Saves a preference. A failed write is only logged, because it is cosmetic: the default is used on the next launch.

  Future<void> _persistString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('Failed to persist "$key": $e');
    }
  }

  Future<void> _persistDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      debugPrint('Failed to persist "$key": $e');
    }
  }
}

/// What the Library tab's completion card shows once a scan runs to the end.
class ScanSummary {
  const ScanSummary({required this.total, required this.failed});

  final int total;
  final int failed;

  int get indexed => (total - failed).clamp(0, total);
}

enum PickingMode { device, folder }

enum ContentMode { both, videos, images }

enum ResultsLayout { list, grid2, grid3, grid4, bento }
