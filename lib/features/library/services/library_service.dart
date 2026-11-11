import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/library/models/library_stats.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

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
    final NativeController nativeController = Get.find();
    try {
      final String pickingModeString = nativeController.getPickingModeString(
        pickingMode: pickingMode,
      );
      final String contentModeString = nativeController.getContentModeString(
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
