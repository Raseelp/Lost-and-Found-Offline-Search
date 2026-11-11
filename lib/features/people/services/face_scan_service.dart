import 'package:flutter/services.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';

/// Running the face scan and its settings.
class FaceScanService {
  static const _faceProgressChannel = EventChannel('lostandfound/faceProgress');

  /// Live status ticks from the face scan (also delivered while it runs in the
  /// background). Same fields as [FaceStatus].
  Stream<FaceStatus> faceProgress() => _faceProgressChannel
      .receiveBroadcastStream()
      .map((e) => FaceStatus.fromMap(e as Map<dynamic, dynamic>));

  /// Starts the face scan; does nothing if it is already running. True if it is running, false if there was nothing
  /// for it to do.
  Future<bool> startFaceScan() async {
    return await nativeChannel.invokeMethod<bool>('startFaceScan') ?? false;
  }

  /// Stops the face scan and keeps it stopped (nothing restarts it automatically).
  Future<void> pauseFaceScan() => nativeChannel.invokeMethod('pauseFaceScan');

  /// Lets the face scan run again (and starts it if there is anything to do).
  Future<void> resumeFaceScan() => nativeChannel.invokeMethod('resumeFaceScan');

  Future<FaceStatus> faceStatus() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('faceStatus');
    return FaceStatus.fromMap(map!);
  }

  Future<void> regroupFaces() => nativeChannel.invokeMethod('regroupFaces');

  /// Forgets every face and person (names too); the next scan starts over.
  Future<void> resetFaces() => nativeChannel.invokeMethod('resetFaces');

  Future<void> setFaceSettings({
    bool? thorough,
    bool? refine,
    String? strictness,
    bool? scanVideos,
    String? videoDensity,
  }) => nativeChannel.invokeMethod('setFaceSettings', {
    'thorough': thorough,
    'refine': refine,
    'strictness': strictness,
    'scanVideos': scanVideos,
    'videoDensity': videoDensity,
  });

  /// Runs the one-off speed test for this phone again.
  Future<void> retuneFaces() => nativeChannel.invokeMethod('retuneFaces');

  /// The face models found on the device (bundled or dropped into [FaceModels.dir]).
  Future<FaceModels> faceModels() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('faceModels');
    return FaceModels.fromMap(map!);
  }

  Future<void> selectFaceModel({
    required String kind,
    required String id,
  }) async {
    await nativeChannel.invokeMethod('selectFaceModel', {'kind': kind, 'id': id});
  }
}
