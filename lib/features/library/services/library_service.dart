import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/library/models/library_stats.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/core/media/content_mode.dart';
import 'package:lost_and_found/features/library/models/scan_models.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';

/// Scanning folders, the index size and the library's statistics.
class LibraryService {
  static const _progressChannel = EventChannel('lostandfound/progress');

  /// Opens the folder picker and returns the picked tree URI, or null if cancelled. It is separate from the scan so
  /// the caller can derive a stable folder identity from the URI before the scan starts.
  Future<String?> pickFolderUri() async {
    try {
      return await nativeChannel.invokeMethod<String>('pickFolder');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        debugPrint('Folder picking cancelled by user');
        return null;
      }
      rethrow;
    }
  }

  Future<bool?> scan({
    required String folderId,
    required PickingMode pickingMode,
    required String uri,
    required ContentMode contentMode,
  }) async {
    final LibraryController library = Get.find();
    try {
      final String pickingModeString = library.getPickingModeString(
        pickingMode: pickingMode,
      );
      final String contentModeString = library.getContentModeString(
        contentMode: contentMode,
      );
      final result = await nativeChannel.invokeMethod('scanImagesAndOrVideos', {
        'mode': pickingModeString,
        'uri': uri,
        'folderId': folderId,
        'contentMode': contentModeString,
      });
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'MODELS_NOT_READY') throw const ModelsNotReadyError();
      debugPrint('Error in scan: ${e.toString()}');
      return null;
    } catch (e) {
      debugPrint('Unexpected error: ${e.toString()}');
      return null;
    }
  }

  /// The items the latest indexing scan stored, if the app has not taken them yet (they are
  /// given out once). Empty when there are none, or on any failure.
  Future<List<String>> takeLatestScan() async {
    try {
      return await nativeChannel.invokeListMethod<String>('takeLatestScan') ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  /// The items that indexing of new photos and videos by itself stored since the app last asked (given out once). Empty
  /// when there are none, or on any failure.
  Future<List<String>> takeAutoIndexed() async {
    try {
      return await nativeChannel.invokeListMethod<String>('takeAutoIndexed') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// What indexing by itself stored since the app last asked (given out once): how many photos and videos, and a few of
  /// them to show. All zero and no items when there is nothing, or on any failure.
  Future<AutoIndexedBatch> takeAutoShown() async {
    try {
      final map = await nativeChannel.invokeMapMethod<String, dynamic>('takeAutoShown');
      if (map == null) return const AutoIndexedBatch();
      return AutoIndexedBatch(
        photos: (map['photos'] as num?)?.toInt() ?? 0,
        videos: (map['videos'] as num?)?.toInt() ?? 0,
        items: [
          for (final item in (map['items'] as List? ?? const []))
            if (item is Map && item['uri'] is String) (uri: item['uri'] as String, video: item['video'] == true),
        ],
      );
    } catch (_) {
      return const AutoIndexedBatch();
    }
  }

  /// The last progress the scan reported, kept by the native side, for when the scan ended or was cut short while the app
  /// was away. Null when there is none, or on any failure.
  Future<Map<String, dynamic>?> lastScanProgress() async {
    try {
      return await nativeChannel.invokeMapMethod<String, dynamic>('lastScanProgress');
    } catch (_) {
      return null;
    }
  }

  /// When indexing by itself last stored something, in milliseconds since 1970, or 0.
  Future<int> autoIndexedAt() async {
    try {
      return await nativeChannel.invokeMethod<int>('autoIndexedAt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// What auto indexing picks up: 'both' (the default), 'images' or 'videos'.
  Future<String> autoIndexContent() async {
    try {
      return await nativeChannel.invokeMethod<String>('getAutoIndexContent') ?? 'both';
    } catch (_) {
      return 'both';
    }
  }

  /// Sets what auto indexing picks up ('both', 'images' or 'videos').
  Future<void> setAutoIndexContent(String mode) async {
    try {
      await nativeChannel.invokeMethod('setAutoIndexContent', {'mode': mode});
    } catch (_) {
      // It keeps the last one it was given.
    }
  }

  Stream<Map<String, dynamic>> scanProgressStream() {
    return _progressChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event),
    );
  }

  Future<bool> cancelScanning() async {
    return await nativeChannel.invokeMethod<bool>('cancelEmbedding') ?? false;
  }

  /// The latest progress tick for a scan that is still running natively, or null if none is. It brings a recreated
  /// Dart layer back in step with a scan it did not start, for example after the app was removed from Recents and
  /// reopened.
  Future<Map<String, dynamic>?> getActiveScanProgress() async {
    final result = await nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getActiveScanProgress',
    );
    return result != null ? Map<String, dynamic>.from(result) : null;
  }

  Future<void> deleteEmbeddingsByFolderId({required String folderId}) async {
    await nativeChannel.invokeMethod<bool>('deleteEmbeddingsByFolderId', {
      'folderId': folderId,
    });
  }

  Future<int> getEmbeddingCount() async {
    return await nativeChannel.invokeMethod<int>('getEmbeddingCount') ?? 0;
  }

  /// Backs the Library tab's stat tiles: total embeddings, distinct image and video counts, and the index's on-disk
  /// size, in one call.
  Future<LibraryStats> getLibraryStats() async {
    final result = await nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getLibraryStats',
    );
    return result != null ? LibraryStats.fromMap(result) : LibraryStats.empty();
  }

  /// How many photos and videos the phone's gallery holds, or null when the app may not read it.
  Future<({int photos, int videos})?> getPhoneMediaCounts() async {
    final result = await nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getPhoneMediaCounts',
    );
    if (result == null) return null;
    return (
      photos: (result['photos'] as num?)?.toInt() ?? 0,
      videos: (result['videos'] as num?)?.toInt() ?? 0,
    );
  }

  /// A few of the most recently indexed photos and videos, newest first, to show as pictures. A video comes with the moment
  /// of one of its frames.
  Future<({List<String> photos, List<({String uri, int timestampMs})> videos})> getIndexedSamples({
    required int photos,
    required int videos,
  }) async {
    final result = await nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getIndexedSamples',
      {'photos': photos, 'videos': videos},
    );
    return (
      photos: [for (final uri in (result?['photos'] as List? ?? const [])) uri as String],
      videos: [
        for (final v in (result?['videos'] as List? ?? const []))
          (
            uri: (v as Map)['uri'] as String,
            timestampMs: (v['timestampMs'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }

  /// Whether new photos and videos are indexed by themselves (see AutoIndex on the native side). On until turned off.
  Future<bool> autoIndexEnabled() async => await nativeChannel.invokeMethod<bool>('getAutoIndex') ?? true;

  Future<void> setAutoIndexEnabled(bool value) => nativeChannel.invokeMethod('setAutoIndex', {'enabled': value});

  Future<int> getEmbeddingCountForFolder({required String folderId}) async {
    return await nativeChannel.invokeMethod<int>('getEmbeddingCountForFolder', {
          'folderId': folderId,
        }) ??
        0;
  }

  /// The person has been told that their index was dropped because the search model changed.
  Future<void> acknowledgeModelReset() async {
    await nativeChannel.invokeMethod('acknowledgeModelReset');
  }

  Future<void> clearEmbeddings() async {
    await nativeChannel.invokeMethod('clearEmbeddings');
  }
}

/// Photos and videos that were indexed by themselves: how many of each, and a few of them to show, newest first.
class AutoIndexedBatch {
  const AutoIndexedBatch({this.photos = 0, this.videos = 0, this.items = const []});

  final int photos;
  final int videos;
  final List<({String uri, bool video})> items;

  int get count => photos + videos;
}
