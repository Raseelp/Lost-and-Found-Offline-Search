import 'package:flutter/services.dart';
import 'package:lost_and_found/features/memories/models/memories.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// The Then and now pair of a person and its pictures.
class ThenNowService {
  /// A person's clearest photo of their first year and of their latest, or null when there is not
  /// enough to compare.
  Future<ThenNow?> thenAndNow(int personId) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('thenAndNow', {
      'personId': personId,
    });
    return map == null ? null : ThenNow.fromMap(map);
  }

  /// The head-and-shoulders picture of the face at [side] in its photo.
  Future<Uint8List?> portraitCrop(ThenNowSide side, {int size = 640}) {
    return nativeChannel.invokeMethod<Uint8List>('portraitCrop', {
      'uri': side.uri,
      'boxL': side.boxL,
      'boxT': side.boxT,
      'boxR': side.boxR,
      'boxB': side.boxB,
      'photoW': side.photoW,
      'photoH': side.photoH,
      'size': size,
      'margin': side.margin,
      'lift': side.lift,
    });
  }
}
