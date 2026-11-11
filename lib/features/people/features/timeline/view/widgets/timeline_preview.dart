import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/people_timeline.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/features/people/features/timeline/services/timeline_service.dart';
import 'package:lost_and_found/features/people/models/person.dart';
part 'timeline_preview/preview_loader.dart';
part 'timeline_preview/preview_image.dart';
part 'timeline_preview/bento_rects.dart';
part 'timeline_preview/timeline_lens.dart';
part 'timeline_preview/moment_chip.dart';

/// What the timeline's photos need: the picks for the filmstrip, the place of the playhead in them, and each person's
/// photo for the month the playhead has settled on.
///
/// The faces in the left column turn into the person's own photo from the month under the playhead, once it has
/// stayed on a month for a moment.
class TimelinePreview extends ChangeNotifier {
  TimelinePreview({required this.window}) {
    window.centre.addListener(_onCentre);
    window.moving.addListener(_onMoving);
    window.stripActive.addListener(notifyListeners);
  }

  final TimelineWindow window;
  final PreviewLoader loader = PreviewLoader();

  TimelineLayout _layout = TimelineLayout.empty;

  /// Set on dispose. Answers that arrive after it are dropped.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The chosen photos and videos, in the order they were taken.
  List<PreviewPhoto> picks = const [];

  /// For each month of the axis, how many picks it has, and the place of its first, or of the next one for an empty
  /// month.
  List<int> _count = const [];
  List<int> _first = const [];
  int _base = 0;

  Object? _fetchedFor;
  bool _fetching = false;
  bool _fetchAgain = false;

  /// Tells it the axis and people showing. [dataVersion] changes whenever the dates change, and then the picks are
  /// chosen again.
  void update(TimelineLayout layout, {required Object dataVersion, required bool datesDone}) {
    _layout = layout;
    if (datesDone && !identical(_fetchedFor, dataVersion)) {
      _fetchedFor = dataVersion;
      _scheduleFetch();
    } else if (picks.isNotEmpty && (_base != layout.startMonth || _count.length != layout.monthCount)) {
      scheduleMicrotask(_reindex);
    }
  }

  Timer? _fetchTimer;
  DateTime? _lastFetch;

  /// Chooses the picks again, but not more than every few seconds. While photos are being scanned the dates change
  /// all the time, and every choosing reads all the faces.
  void _scheduleFetch() {
    final last = _lastFetch;
    final wait = last == null ? Duration.zero : const Duration(seconds: 4) - DateTime.now().difference(last);
    _fetchTimer?.cancel();
    if (wait <= Duration.zero) {
      unawaited(_fetchPicks());
    } else {
      _fetchTimer = Timer(wait, () => unawaited(_fetchPicks()));
    }
  }

  /// Fetches the picks. What was shown for the month the playhead is on, the people's photos and the photos of the
  /// month, is asked for again.
  Future<void> _fetchPicks() async {
    if (_disposed) return;
    _lastFetch = DateTime.now();
    if (_fetching) {
      _fetchAgain = true;
      return;
    }
    _fetching = true;
    try {
      do {
        _fetchAgain = false;
        picks = await TimelineService().timelinePicks();
        if (_disposed) return;
        _byMonth.clear();
        _media.clear();
        _reindex();
        if (settled) unawaited(_loadPeople(_settledMonth));
        if (!window.moving.value) unawaited(_loadMonth(window.centre.value));
      } while (_fetchAgain);
    } catch (e) {
      debugPrint('timelinePicks failed: $e');
    } finally {
      _fetching = false;
    }
  }

  /// Counts the picks of each month of the axis. Picks are in date order, so the first of each month is the running
  /// total before it.
  void _reindex() {
    final months = _layout.monthCount;
    _base = _layout.startMonth;
    final count = List<int>.filled(math.max(months, 0), 0);
    final kept = <PreviewPhoto>[];
    for (final p in picks) {
      final o = p.month - _base;
      if (o < 0 || o >= months) continue;
      count[o]++;
      kept.add(p);
    }
    final first = List<int>.filled(count.length, 0);
    var run = 0;
    for (var i = 0; i < count.length; i++) {
      first[i] = run;
      run += count[i];
    }
    _count = count;
    _first = first;
    _shown = kept;
    _prefetchAround(front: false);
    notifyListeners();
  }

  /// The picks that fall on the axis, the ones the lens walks through.
  List<PreviewPhoto> _shown = const [];
  List<PreviewPhoto> get shown => _shown;

  /// How many picks the month [month] has.
  int countIn(int month) {
    final o = month - _base;
    return o < 0 || o >= _count.length ? 0 : _count[o];
  }

  /// Where the playhead is in [shown], given as a photo's number with a fraction between two. [monthFloat] is a month
  /// and the part of it gone by. The photos of a month share its length, so a month with many has the row linger, and
  /// an empty one holds it still between the photos either side.
  double indexAt(double monthFloat) {
    if (_count.isEmpty) return 0;
    final rel = monthFloat - _base;
    final month = rel.floor().clamp(0, _count.length - 1);
    final part = (rel - month).clamp(0.0, 1.0);
    final c = _count[month];
    return c > 0 ? _first[month] + part * c - 0.5 : _first[month] - 0.5;
  }

  /// Fetches the small versions of the photos near the playhead first, then everyone else's.
  void _prefetchAround({required bool front}) {
    if (_shown.isEmpty) return;
    final centre = indexAt(window.centreMonth).round().clamp(0, _shown.length - 1);
    final order = <PreviewPhoto>[];
    for (var d = 0; d < _shown.length; d++) {
      if (centre + d < _shown.length) order.add(_shown[centre + d]);
      if (d > 0 && centre - d >= 0) order.add(_shown[centre - d]);
    }
    loader.prefetch(front ? order.take(40) : order, front: front);
  }

  /// Whether the playhead has stayed on a month for a moment. The sharp photos and the people's photos wait for that,
  /// so a fast drag costs nothing.
  bool settled = true;
  Timer? _settleTimer;
  int _settledMonth = -1;

  void _onCentre() {
    if (settled) {
      settled = false;
      notifyListeners();
    }
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 90), _onSettled);
  }

  /// Called when the playhead has stayed on a month. Resting on a month, also when the timeline has just opened, fills
  /// the preview with its photos.
  void _onSettled() {
    settled = true;
    _settledMonth = window.centre.value;
    notifyListeners();
    unawaited(_loadPeople(_settledMonth));
    if (!window.moving.value) unawaited(_loadMonth(_settledMonth));
    _prefetchAround(front: true);
  }

  final LinkedHashMap<int, Map<int, PreviewPhoto>> _byMonth = LinkedHashMap();

  /// [personId]'s clearest photo of the month the playhead is on, once it has settled there. Null while it is moving,
  /// or when they have none then.
  PreviewPhoto? photoFor(int personId) {
    if (!settled || _settledMonth != window.centre.value) return null;
    return _byMonth[_settledMonth]?[personId];
  }

  Future<void> _loadPeople(int month) async {
    if (_byMonth.containsKey(month)) {
      notifyListeners();
      return;
    }
    final lit = [
      for (final row in _layout.rows)
        if (row.countAt(month - _layout.startMonth) > 0) row.person.id,
    ];
    final found = <int, PreviewPhoto>{};
    if (lit.isNotEmpty) {
      try {
        final from = DateTime(month ~/ 12, month % 12 + 1);
        final to = DateTime(month ~/ 12, month % 12 + 2);
        for (final photo in await TimelineService().timelineMonthPhotos(from, to, lit)) {
          found[photo.personId] = photo;
        }
      } catch (e) {
        debugPrint('timelineMonthPhotos failed: $e');
      }
    }
    _byMonth[month] = found;
    while (_byMonth.length > 24) {
      _byMonth.remove(_byMonth.keys.first);
    }
    notifyListeners();
  }

  final LinkedHashMap<int, MonthMedia> _media = LinkedHashMap();

  /// The photos of [month], the best few and how many in all, once they are known.
  MonthMedia? mediaFor(int month) => _media[month];

  /// When the years have come to rest on a month, its photos are fetched to fill the preview. As they were just moved,
  /// the preview may open out whatever the list is doing.
  void _onMoving() {
    if (!window.moving.value) {
      if (_scrollCollapsed) {
        _scrollCollapsed = false;
        notifyListeners();
      }
      unawaited(_loadMonth(window.centre.value));
    }
  }

  /// Fetches the photos of [month]. Their small versions are made at once, so the tiles have something to show as they
  /// open.
  Future<void> _loadMonth(int month) async {
    if (_media.containsKey(month)) {
      notifyListeners();
      return;
    }
    try {
      final from = DateTime(month ~/ 12, month % 12 + 1);
      final to = DateTime(month ~/ 12, month % 12 + 2);
      final found = await TimelineService().timelineMonthMedia(from, to, limit: 9);
      _media[month] = MonthMedia(found.total, found.photos);
      while (_media.length > 12) {
        _media.remove(_media.keys.first);
      }
      loader.prefetch(found.photos, front: true);
    } catch (e) {
      debugPrint('timelineMonthMedia failed: $e');
      _media[month] = const MonthMedia(0, []);
    }
    notifyListeners();
  }

  /// The person with [id], if they are on the timeline.
  Person? personById(int id) {
    for (final row in _layout.rows) {
      if (row.person.id == id) return row.person;
    }
    return null;
  }

  /// The moments of several people, such as the whole gang, a reunion or people appearing for the first time, in
  /// [month].
  List<GroupMoment> groupsIn(int month) => _layout.groupsIn(month);

  /// The moments that fall in [month], such as a first photo together, a return or a lovely run.
  List<({TimelineRowData row, Milestone milestone})> momentsIn(int month) => _layout.momentsIn(month);

  /// How many months one pixel of dragging the lens moves the timeline. A photo's width of dragging is one photo,
  /// which is a part of the month it is in.
  double monthsPerLensPixel(double step) => 1 / (math.max(1, countIn(window.centre.value)) * step);

  /// Set when the person scrolls the list up or down the page. The preview slims with it and stays slim, since they
  /// have gone to look at the list. Cleared when the list is back at the top, or when the years have been moved again
  /// by a slide along a line or a drag of the row, because then they want to see the month wherever the list is.
  bool _scrollCollapsed = false;

  /// Called when the person is scrolling the list, with a finger on it or while it is still gliding.
  void userScrolling() {
    if (_scrollCollapsed) return;
    _scrollCollapsed = true;
    notifyListeners();
  }

  /// Tells where the list is scrolled to. Back at the top, the preview may open out again.
  void setListOffset(double pixels) {
    if (_scrollCollapsed && pixels <= 6) {
      _scrollCollapsed = false;
      notifyListeners();
    }
  }

  /// Whether the preview should stay out of the way of the list, because it was scrolled away from the top or a finger
  /// is moving the strips.
  bool get compact => _scrollCollapsed || window.stripActive.value;

  @override
  void dispose() {
    _disposed = true;
    _fetchTimer?.cancel();
    window.stripActive.removeListener(notifyListeners);
    window.moving.removeListener(_onMoving);
    window.centre.removeListener(_onCentre);
    _settleTimer?.cancel();
    super.dispose();
  }
}

/// The photos of one month: the best few, and how many there are in all.
class MonthMedia {
  const MonthMedia(this.total, this.photos);

  final int total;
  final List<PreviewPhoto> photos;
}
