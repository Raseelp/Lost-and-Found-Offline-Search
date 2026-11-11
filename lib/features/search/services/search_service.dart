import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/search/services/tokenizer/clip_tokenizer.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';

/// Searching by words, by a photo or by a video frame, and why a result matched.
class SearchService {
  /// [personIds] non-empty means the box also had one or more recognised people in it ("@Person and @Person2" or
  /// plain names typed and matched). [query] is then just the words left over after those names were taken out, and
  /// results are restricted to photos and videos with all of them in it before being ranked against those words.
  Future<List<Map<String, dynamic>>> searchImages({
    required String query,
    required int limitNumber,
    required ContentMode contentMode,
    List<int>? personIds,
  }) async {
    final tokenizer = await ClipTokenizer.load();
    final tokens = tokenizer.tokenize(query);
    final LibraryController nativeController = Get.find();

    debugPrint('tokens generated for the query $query ${tokens.toString()}');
    try {
      final results = await nativeChannel
          .invokeMethod<List<dynamic>>('searchByText', {
            'tokens': tokens,
            'topK': limitNumber,
            'contentMode': nativeController.getContentModeString(
              contentMode: contentMode,
            ),
            'personIds': personIds,
          });

      return results!
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchByImage({
    required String uri,
    int limit = 20,
    required ContentMode contentMode,
  }) async {
    final LibraryController nativeController = Get.find();
    try {
      final results = await nativeChannel
          .invokeMethod<List<dynamic>>("searchByImage", {
            "uri": uri,
            "topK": limit,
            "contentMode": nativeController.getContentModeString(
              contentMode: contentMode,
            ),
          });

      return results!
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      rethrow;
    }
  }

  /// Raw (unnormalized) text embedding for an already-tokenized prompt. Collections average these into their query
  /// embedding.
  Future<List<double>> encodeText(List<int> tokens) async {
    try {
      final result = await nativeChannel.invokeMethod<List<dynamic>>('encodeText', {
        'tokens': tokens,
      });
      return (result ?? const []).map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      rethrow;
    }
  }

  /// Raw embedding of a photo, or of one frame of a video when [timestampMs] is given.
  Future<List<double>> encodeImage({
    required String uri,
    int? timestampMs,
  }) async {
    try {
      final result = await nativeChannel.invokeMethod<List<dynamic>>('encodeImage', {
        'uri': uri,
        'timestampMs': timestampMs,
      });
      return (result ?? const []).map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      rethrow;
    }
  }

  /// Image search seeded by one moment of a video rather than a picked photo.
  Future<List<Map<String, dynamic>>> searchByVideoFrame({
    required String uri,
    required int timestampMs,
    int limit = 20,
    required ContentMode contentMode,
  }) async {
    final LibraryController nativeController = Get.find();
    try {
      final results = await nativeChannel
          .invokeMethod<List<dynamic>>('searchByVideoFrame', {
            'uri': uri,
            'timestampMs': timestampMs,
            'topK': limit,
            'contentMode': nativeController.getContentModeString(
              contentMode: contentMode,
            ),
          });

      return results!
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      rethrow;
    }
  }

  /// Scores each candidate word's own embedding against one result, for the result the person opened ("why this
  /// matched"). Empty list, not an error, when the embedding cannot be found any more (deleted or embedded again since
  /// the search ran) or anything else goes wrong, because it is a detail that is never worth showing a failure for.
  Future<List<Map<String, dynamic>>> explainMatch({
    required String path,
    required bool isVideo,
    required int timestampMs,
    required List<String> words,
  }) async {
    if (words.isEmpty) return [];

    final tokenizer = await ClipTokenizer.load();
    final wordArgs = words
        .map((w) => {'word': w, 'tokens': tokenizer.tokenize(w)})
        .toList();

    try {
      final results = await nativeChannel.invokeMethod<List<dynamic>>(
        'explainMatch',
        {
          'path': path,
          'isVideo': isVideo,
          'timestampMs': timestampMs,
          'words': wordArgs,
        },
      );

      return (results ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('explainMatch failed: $e');
      return [];
    }
  }

  pickImageForSearching() async {
    return await nativeChannel.invokeMethod('pickImage');
  }
}
