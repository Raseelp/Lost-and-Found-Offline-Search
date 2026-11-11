import 'package:lost_and_found/core/native/native_channel.dart';

/// Facts about the phone and this build, each asked once.
class DeviceService {
  static Future<Map<String, dynamic>?>? _buildInfo;

  /// Which build of the app this is (version, build number, the commit it was made from), asked once.
  Future<Map<String, dynamic>?> buildInfo() => _buildInfo ??= nativeChannel
      .invokeMapMethod<String, dynamic>('buildInfo')
      .then<Map<String, dynamic>?>((m) => m)
      .catchError((_) => null);

  static Future<Map<String, dynamic>?>? _deviceChip;

  /// The name of this phone's processor (maker, model, cores, architecture), asked once.
  Future<Map<String, dynamic>?> deviceChip() => _deviceChip ??= nativeChannel
      .invokeMapMethod<String, dynamic>('deviceChip')
      .then<Map<String, dynamic>?>((m) => m)
      .catchError((_) => null);

  /// The phone's Android version (API level). Asked once; 0 when it cannot be told.
  Future<int> androidSdk() async {
    try {
      return _sdk ??= await nativeChannel.invokeMethod<int>('androidSdk') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static int? _sdk;
}
