import 'package:flutter/widgets.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// The stories reminder.
class StoriesService {
  /// The "your stories have refreshed" notification: [enabled] turns it on or off, [atMs] sets it for that time
  /// (replacing the one waiting), [cancel] takes it away. [ringsJson] is who will be in the row of rings it shows when
  /// opened out, as text: a list of objects with a title and either a faceId or a cover and video flag. It is kept for
  /// when the note is made. Returns whether it is on and whether the system lets the app show notifications.
  Future<({bool enabled, bool allowed})> storiesReminder({
    bool? enabled,
    int? atMs,
    bool cancel = false,
    String? ringsJson,
  }) async {
    try {
      final map = await nativeChannel.invokeMapMethod<String, dynamic>('storiesReminder', {
        if (enabled != null) 'enabled': enabled,
        if (atMs != null) 'atMs': atMs,
        if (cancel) 'cancel': true,
        if (ringsJson != null) 'ringsJson': ringsJson,
      });
      return (enabled: map?['enabled'] != false, allowed: map?['allowed'] == true);
    } catch (e) {
      debugPrint('storiesReminder failed: $e');
      return (enabled: true, allowed: false);
    }
  }

  /// Shows the "your stories have refreshed" note at once with these rings ([ringsJson], as for [storiesReminder]), to
  /// see what it looks like. Whether it was shown (it is not when the system does not let the app show notifications).
  Future<bool> storiesReminderTest(String ringsJson) async {
    try {
      return await nativeChannel.invokeMethod<bool>('storiesReminderTest', {'ringsJson': ringsJson}) ?? false;
    } catch (e) {
      debugPrint('storiesReminderTest failed: $e');
      return false;
    }
  }
}
