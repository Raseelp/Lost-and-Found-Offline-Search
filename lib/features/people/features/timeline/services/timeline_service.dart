import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// The people timeline and the photos picked for it.
class TimelineService {
  /// When everyone appears, month by month. Looks up the dates of photos and videos not looked at
  /// yet for up to [budgetMs] first, so call again while [TimelineData.pending] is above 0.
  Future<TimelineData> peopleTimeline({int budgetMs = 800}) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'peopleTimeline',
      {'budgetMs': budgetMs},
    );
    return TimelineData.fromMap(map!);
  }

  /// The best few photos and videos of every month with people in them, in date order (the
  /// filmstrip on the timeline).
  Future<List<PreviewPhoto>> timelinePicks() async {
    final list = await nativeChannel.invokeListMethod<dynamic>('timelinePicks');
    return [
      for (final e in list ?? const [])
        PreviewPhoto.fromMap(e as Map<dynamic, dynamic>),
    ];
  }

  /// Each of [personIds]' clearest photo or video taken from [from] up to [to] (people with
  /// nothing then are left out).
  Future<List<PreviewPhoto>> timelineMonthPhotos(
    DateTime from,
    DateTime to,
    List<int> personIds,
  ) async {
    final list = await nativeChannel
        .invokeListMethod<dynamic>('timelineMonthPhotos', {
          'startMs': from.millisecondsSinceEpoch,
          'endMs': to.millisecondsSinceEpoch,
          'personIds': personIds,
        });
    return [
      for (final e in list ?? const [])
        PreviewPhoto.fromMap(e as Map<dynamic, dynamic>),
    ];
  }

  /// The best [limit] photos and videos from [from] up to [to], and how many there are in all.
  Future<({int total, List<PreviewPhoto> photos})> timelineMonthMedia(
    DateTime from,
    DateTime to, {
    int limit = 9,
    int burstMs = 20000,
  }) async {
    final map = await nativeChannel
        .invokeMapMethod<String, dynamic>('timelineMonthMedia', {
          'startMs': from.millisecondsSinceEpoch,
          'endMs': to.millisecondsSinceEpoch,
          'limit': limit,
          'burstMs': burstMs,
        });
    return (
      total: (map?['total'] as num?)?.toInt() ?? 0,
      photos: [
        for (final e in (map?['items'] as List? ?? const []))
          PreviewPhoto.fromMap(e as Map<dynamic, dynamic>),
      ],
    );
  }
}
