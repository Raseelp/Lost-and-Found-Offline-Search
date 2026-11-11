import 'package:flutter/widgets.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// What the viewer does with a photo or video: share, save a copy, set as wallpaper and copy.
class MediaActionsService {
  /// Hands the file to Android's own share sheet. No bytes cross the platform channel, just the content URI already
  /// in hand.
  Future<bool> shareFile({required String uri, required bool isVideo}) async {
    try {
      return await nativeChannel.invokeMethod<bool>('shareFile', {
            'uri': uri,
            'isVideo': isVideo,
          }) ??
          false;
    } catch (e) {
      debugPrint('shareFile failed: $e');
      return false;
    }
  }

  /// Copies the file into the Photos or Gallery app's own storage. Useful when the original was indexed from a folder
  /// that app cannot see (an arbitrary SAF tree, a downloads folder and so on).
  Future<bool> saveCopyToGallery({
    required String uri,
    required bool isVideo,
  }) async {
    try {
      return await nativeChannel.invokeMethod<bool>('saveCopyToGallery', {
            'uri': uri,
            'isVideo': isVideo,
          }) ??
          false;
    } catch (e) {
      debugPrint('saveCopyToGallery failed: $e');
      return false;
    }
  }

  Future<bool> setAsWallpaper({required String uri}) async {
    try {
      return await nativeChannel.invokeMethod<bool>('setAsWallpaper', {
            'uri': uri,
          }) ??
          false;
    } catch (e) {
      debugPrint('setAsWallpaper failed: $e');
      return false;
    }
  }

  Future<bool> copyImageToClipboard({required String uri}) async {
    try {
      return await nativeChannel.invokeMethod<bool>('copyImageToClipboard', {
            'uri': uri,
          }) ??
          false;
    } catch (e) {
      debugPrint('copyImageToClipboard failed: $e');
      return false;
    }
  }
}
