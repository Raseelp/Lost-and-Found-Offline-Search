import 'package:lost_and_found/core/native/native_channel.dart';

/// The diagnostics switches in Settings.
class SettingsService {
  /// The performance logs (adb logcat -s LostFoundBench): on unless turned off.
  Future<bool> benchLogsEnabled() async =>
      await nativeChannel.invokeMethod<bool>('getBenchLogs') ?? true;

  Future<void> setBenchLogsEnabled(bool value) =>
      nativeChannel.invokeMethod('setBenchLogs', {'enabled': value});

  /// The app's recent log, as text to copy into a bug report.
  Future<String> appLogs() async =>
      await nativeChannel.invokeMethod<String>('appLogs') ?? '';
}
