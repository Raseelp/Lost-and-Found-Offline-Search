import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/people/models/person.dart';
import 'package:lost_and_found/features/search/services/search_service.dart';
import 'package:lost_and_found/features/viewer/controllers/viewer_controller.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';
import 'package:lost_and_found/features/home/controllers/home_controller.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/core/storage/preferences.dart';
import 'package:lost_and_found/features/search/models/results_layout.dart';

class AppSearchController extends GetxController {
  HomeController get _home => Get.find<HomeController>();
  ModelDownloadController get _models => Get.find<ModelDownloadController>();
  ViewerController get _viewer => Get.find<ViewerController>();
  @override
  onInit() async {
    await _loadPersistedPreferences();
    super.onInit();
  }

  /// Loads the results layout, the results limit and the search mode, once. If loading fails the app opens with the
  /// defaults.
  Future<void> _loadPersistedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

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
    searchFocusNode.dispose();
    super.onClose();
  }


  static const _resultsLayoutKey = 'results_layout';

  static const _resultsLimitKey = 'results_limit';

  static const _searchContentModeKey = 'search_content_mode';

  double sliderValue = 20;

  List<Map<String, dynamic>> searchResults = [];

  bool isSearching = false;

  String error = '';

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

  /// What a search is filtered to include. It is separate from [selectedContentMode], which governs scanning (what to
  /// embed) and not searching (what to search across). The search filter sheet sets it through [setSearchContentMode].
  ContentMode searchContentMode = ContentMode.both;

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

  /// Picks an image and previews it without searching. As with typing text, nothing runs until the person submits.
  Future<void> pickSearchImage() async {
    final uri = await SearchService().pickImageForSearching();
    if (uri == null) return;

    pickedSearchImageUri = uri;
    pickedSearchVideoTimestampMs = null;
    pickedSearchImageBytes = null;
    update();

    try {
      pickedSearchImageBytes = await MediaService().loadImageBytes(
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
    _home.setHomeTab(0);
    pickedSearchImageUri = uri;
    pickedSearchImageBytes = bytes;
    pickedSearchVideoTimestampMs = null;
    searchTextController.clear();
    _viewer.matchExplanation = [];
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
    _home.setHomeTab(0);
    pickedSearchImageUri = uri;
    pickedSearchVideoTimestampMs = timestampMs;
    pickedSearchImageBytes = null;
    searchTextController.clear();
    _viewer.matchExplanation = [];
    update();

    try {
      pickedSearchImageBytes = await MediaService().loadVideoThumbnail(
        uri: uri,
        timestampMs: timestampMs,
      );
    } catch (_) {
      // Only the preview is missing, the search does not need it.
    }
    update();

    await runSearch();
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
    _viewer.imageCache.clear();
    _viewer.matchExplanation = [];
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
      _viewer.imageCache.clear();

      if (imageUri != null) {
        lastTextQuery = null;
        lastMentionedPersonIds = [];
        lastMentionedPeopleNames = [];
        final frameMs = pickedSearchVideoTimestampMs;
        lastImageSeedUri = imageUri;
        lastImageSeedTimestampMs = frameMs;
        final found = frameMs != null
            ? await SearchService().searchByVideoFrame(
                uri: imageUri,
                timestampMs: frameMs,
                limit: sliderValue.round().toInt(),
                contentMode: searchContentMode,
              )
            : await SearchService().searchByImage(
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
        final found = await SearchService().searchImages(
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
          if (!_viewer.imageCache.containsKey(cacheKeyForResult(item))) item,
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
              final bytes = await MediaService().loadVideoThumbnail(
                uri: uri,
                timestampMs: timestampMs,
              );
              _viewer.imageCache[cacheKeyForResult(item)] = bytes;
            } else {
              final bytes = await MediaService().loadImageBytes(
                uri: uri,
                isCompressed: true,
              );
              _viewer.imageCache[cacheKeyForResult(item)] = bytes;
            }
          } catch (_) {}
        }
      }

      await Future.wait([for (var i = 0; i < 3; i++) loadTiles()]);
    } on ModelsNotReadyError {
      _models.modelsReady = false;
      _models.update();
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

  void setSliderValue(double value) {
    sliderValue = value;
    update();
    unawaited(persistDouble(_resultsLimitKey, value));
  }

  /// Committed from the search filter sheet's draft state, only once the user taps Confirm (see _SearchFilterSheet).
  /// Whether this also re-runs the current search is that widget's call, not this setter's.
  void setSearchContentMode(ContentMode contentMode) {
    searchContentMode = contentMode;
    update();
    unawaited(persistString(_searchContentModeKey, contentMode.name));
  }

  ResultsLayout resultsLayout = ResultsLayout.bento;

  void setResultsLayout(ResultsLayout layout) {
    resultsLayout = layout;
    update();
    unawaited(persistString(_resultsLayoutKey, layout.name));
  }
/// Saves a preference. A failed write is only logged, because it is cosmetic: the default is used on the next launch.
}
