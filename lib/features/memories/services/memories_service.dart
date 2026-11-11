import 'package:flutter/widgets.dart';
import 'package:lost_and_found/features/memories/models/memories.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// On this day, the daily memory and the reminders that open the app.
class MemoriesService {
  /// Brings the dates of everything indexed up to date, for up to [budgetMs]; call again while
  /// [pending] is above 0.
  Future<({int total, int pending})> memoryPrepare({int budgetMs = 600}) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'memoryPrepare',
      {'budgetMs': budgetMs},
    );
    return (
      total: (map?['total'] as num?)?.toInt() ?? 0,
      pending: (map?['pending'] as num?)?.toInt() ?? 0,
    );
  }

  /// Today's date in the past years of the library.
  Future<OnThisDay> onThisDay() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('onThisDay');
    return map == null ? OnThisDay.empty : OnThisDay.fromMap(map);
  }

  /// Every photo and video from [from] up to [to] (one day of a past year).
  Future<List<PreviewPhoto>> memoryDay(
    DateTime from,
    DateTime to, {
    int limit = 2000,
  }) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('memoryDay', {
      'startMs': from.millisecondsSinceEpoch,
      'endMs': to.millisecondsSinceEpoch,
      'limit': limit,
    });
    return [
      for (final e in (map?['items'] as List? ?? const []))
        PreviewPhoto.fromMap(e as Map<dynamic, dynamic>),
    ];
  }

  Future<MemorySettings> memorySettings() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'memorySettings',
    );
    return map == null ? const MemorySettings() : MemorySettings.fromMap(map);
  }

  Future<MemorySettings> setMemorySettings({bool? enabled}) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'setMemorySettings',
      {if (enabled != null) 'enabled': enabled},
    );
    return map == null ? const MemorySettings() : MemorySettings.fromMap(map);
  }

  /// When each of [uris] was taken (0: not known) and whether it is a screenshot or a screen recording; a file the
  /// catalog does not have is left out. For choosing the pictures of a story.
  Future<Map<String, ({int takenMs, bool junk})>> mediaDates(List<String> uris) async {
    if (uris.isEmpty) return const {};
    try {
      final list = await nativeChannel.invokeListMethod<dynamic>('mediaDates', {'uris': uris});
      return {
        for (final e in (list ?? const []).cast<Map>())
          e['uri'] as String: (takenMs: (e['takenMs'] as num?)?.toInt() ?? 0, junk: e['junk'] == true),
      };
    } catch (e) {
      debugPrint('mediaDates failed: $e');
      return const {};
    }
  }

  /// Sends today's memory at once, to see what it looks like. The message says what happened.
  Future<String> memoryTest() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>('memoryTest');
    final message = map?['message'] as String? ?? '';
    return map?['sent'] != null ? 'Sent: $message' : message;
  }

  /// The home tab a tapped notification wants shown since this was last asked (taken once): the Library tab for the
  /// scan's notification, the Search tab for the stories note. Null: none.
  Future<int?> takeOpenTab() async {
    final tab = await nativeChannel.invokeMethod<int>('takeOpenTab') ?? -1;
    return tab < 0 ? null : tab;
  }

  /// The note that asks to finish indexing: whether it is on (it is, until turned off).
  Future<bool> indexNudgeEnabled() async =>
      await nativeChannel.invokeMethod<bool>('getIndexNudge') ?? true;

  Future<void> setIndexNudgeEnabled(bool value) =>
      nativeChannel.invokeMethod('setIndexNudge', {'enabled': value});

  /// Whether "Index now" on that note was pressed since this was last asked (taken once).
  Future<bool> takeIndexNow() async =>
      await nativeChannel.invokeMethod<bool>('takeIndexNow') ?? false;

  /// The memory a tapped notification wants opened (taken once): its kind and year, or null.
  Future<({String kind, int year, int personId})?> takeLaunchMemory() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'takeLaunchMemory',
    );
    if (map == null) return null;
    return (
      kind: map['kind'] as String? ?? '',
      year: (map['year'] as num?)?.toInt() ?? 0,
      personId: (map['personId'] as num?)?.toInt() ?? 0,
    );
  }
}
