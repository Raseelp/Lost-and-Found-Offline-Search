import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/media/meta_data_model.dart';
import 'package:lost_and_found/features/search/services/query_words.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/search/services/search_service.dart';
import 'package:lost_and_found/features/viewer/services/media_actions_service.dart';
import 'package:lost_and_found/features/search/controllers/search_controller.dart';
import 'package:lost_and_found/core/media/content_mode.dart';

class ViewerController extends GetxController {
  AppSearchController get _search => Get.find<AppSearchController>();

  bool isFetchingMetadata = false;

  bool showMetadata = false;

  final Map<String, Uint8List> imageCache = {};

  /// "Why this matched" for the result that is open (see [loadMatchExplanation]). It is empty until that resolves, or
  /// when there is nothing to explain, as after an image search or a query with no real content words.
  List<MapEntry<String, double>> matchExplanation = [];

  /// The results of "Similar to this", the small strip shown from the viewer in place of the full search. It has its own
  /// list and thumbnail cache, separate from [searchResults] and [imageCache], because those hold a different and much
  /// larger result set that a real search would clear and replace. See [loadSimilar].
  List<Map<String, dynamic>> similarResults = [];

  final Map<String, Uint8List> similarThumbCache = {};

  bool isLoadingSimilar = false;

  ImageMetadata selectedMetadata = ImageMetadata.empty();

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
          ? await SearchService().searchByVideoFrame(
              uri: uri,
              timestampMs: timestampMs,
              limit: 13,
              contentMode: ContentMode.both,
            )
          : await SearchService().searchByImage(
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
            final bytes = await MediaService().loadThumbnail(
              uri: item['path'] as String,
              isVideo: item['isVideo'] as bool? ?? false,
              timestampMs: (item['timestampMs'] as num?)?.toInt() ?? 0,
              size: 300,
            );
            if (token != _similarToken) return;
            similarThumbCache[_search.cacheKeyForResult(item)] = bytes;
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

  Future<Uint8List> loadImageByURI({
    required String uri,
    bool? isCompressed,
  }) async {
    return await MediaService().loadImageBytes(
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
    final data = await MediaService().loadMetadataByUri(
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
    return MediaActionsService().shareFile(uri: uri, isVideo: isVideo);
  }

  Future<bool> saveFileCopy({required String uri, required bool isVideo}) {
    return MediaActionsService().saveCopyToGallery(uri: uri, isVideo: isVideo);
  }

  Future<bool> setPhotoAsWallpaper({required String uri}) {
    return MediaActionsService().setAsWallpaper(uri: uri);
  }

  Future<bool> copyImageToClipboard({required String uri}) {
    return MediaActionsService().copyImageToClipboard(uri: uri);
  }

  /// Loads "Why this matched" for a result. It is called when a result is opened and not for every result a search
  /// returns (see [SearchService.explainMatch] for why it is lazy). [matchExplanation] stays empty, with no loading
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

    query ??= _search.lastTextQuery;
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

    final raw = await SearchService().explainMatch(
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
}
