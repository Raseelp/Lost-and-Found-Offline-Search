import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lost_and_found/core/media/meta_data_model.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// Photo and video pictures, their file details and the phone's video limits.
class MediaService {
  /// [maxDimension] overrides the native default cap on compressed decodes (see MAX_COMPRESSED_DIMENSION in
  /// MainActivity.kt) for this one call. It is for the rare, much larger showcase tiles of a bento grid, which need
  /// more source resolution to look sharp. Null keeps the cheaper default cap.
  Future<Uint8List> loadImageBytes({
    required String uri,
    required bool isCompressed,
    int? maxDimension,
  }) async {
    final bytes = await nativeChannel.invokeMethod<List<int>>('loadImageBytes', {
      'uri': uri,
      'compress': isCompressed,
      if (maxDimension != null) 'maxDimension': maxDimension,
    });

    return Uint8List.fromList(bytes!);
  }

  /// A small copy of a photo turned upright (as the face scan sees it), so the boxes it found
  /// line up with it.
  Future<Uint8List> loadUprightPhoto(String uri, {int maxSide = 360}) async {
    final bytes = await nativeChannel.invokeMethod<List<int>>('loadUprightPhoto', {
      'uri': uri,
      'maxSide': maxSide,
    });
    return Uint8List.fromList(bytes!);
  }

  /// Whether battery saver is on, and how many video decoders the phone can run at once.
  Future<({bool powerSave, int maxDecoders})> videoEnv() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('videoEnv');
    return (
      powerSave: map?['powerSave'] == true,
      maxDecoders: (map?['maxDecoders'] as num?)?.toInt() ?? 1,
    );
  }

  /// A small JPEG sized for a grid or a card, far cheaper than [loadImageBytes], which returns a full-screen-sized
  /// image. [maxDimension] is the same override as in [loadImageBytes], for a bento showcase tile that is a video.
  Future<Uint8List> loadThumbnail({
    required String uri,
    required bool isVideo,
    int timestampMs = 0,
    int size = 400,
  }) async {
    final bytes = await nativeChannel.invokeMethod<List<int>>('loadThumbnail', {
      'uri': uri,
      'isVideo': isVideo,
      'timestampMs': timestampMs,
      'size': size,
    });
    return Uint8List.fromList(bytes!);
  }

  Future<Uint8List> loadVideoThumbnail({
    required String uri,
    required int timestampMs,
    int? maxDimension,
  }) async {
    final bytes = await nativeChannel.invokeMethod<List<int>>('loadVideoThumbnail', {
      'uri': uri,
      'timestampMs': timestampMs,
      if (maxDimension != null) 'maxDimension': maxDimension,
    });
    return Uint8List.fromList(bytes!);
  }

  Future<ImageMetadata?> loadMetadataByUri({
    required String uri,
    bool isVideo = false,
  }) async {
    try {
      final result = await nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
        'loadMetadataByUri',
        {'uri': uri, 'isVideo': isVideo},
      );

      return result != null ? ImageMetadata.fromMap(result) : null;
    } on Exception catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }
}
