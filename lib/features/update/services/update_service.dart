import 'package:flutter/services.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';

/// Asking Google Play for an update of the app, and starting it. All of it happens between the phone and Google Play.
class UpdateService {
  static const _statusChannel = EventChannel('lostandfound/updateStatus');

  /// What Google Play says about an update. A build that did not come from Play finds none.
  Future<UpdateInfo> check() async {
    final map = await nativeChannel.invokeMapMethod<Object?, Object?>('checkForUpdate');
    return UpdateInfo.fromMap(map ?? const {});
  }

  /// Starts the update, which Google Play asks the person to agree to. The answer is 'accepted', 'declined' or
  /// 'failed'. The download then goes on in the background, and [events] says how it is going.
  Future<String> start() async => await nativeChannel.invokeMethod<String>('startUpdate') ?? 'failed';

  /// Installs a downloaded update. The app closes and opens again in the new version.
  Future<void> complete() => nativeChannel.invokeMethod<void>('completeUpdate');

  Stream<UpdateEvent> get events => _statusChannel.receiveBroadcastStream().map(
    (event) => UpdateEvent.fromMap(event as Map<Object?, Object?>),
  );
}
