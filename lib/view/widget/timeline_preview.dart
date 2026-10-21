import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/people_timeline.dart';

// The photos on the People timeline.
//
//  * The lens: a row of photos in date order, centred on the playhead, the one in the middle
//    large and the neighbours smaller. The playhead's place in time is turned into a place in the
//    row, so winding through a busy month steps through its photos one by one, and an empty month
//    holds the row still.
//  * The faces in the left column turn into the person's own photo from the month under the
//    playhead, once it has stayed on a month for a moment.
//
// Everything is made to show at once: small versions of every chosen photo are fetched in the
// background (the ones nearest the playhead first), the sharp version of the middle ones is only
// asked for once the playhead has slowed down, and a request for a picture nobody wants any more
// is dropped before it starts.

// ---------------------------------------------------------------------------------- loading

class _Job {
  _Job(this.photo, this.large, [this.sharp = false]);

  final PreviewPhoto photo;
  final bool large;

  /// The biggest version (which is [large] too); what a picture shown big is finally sharpened to.
  final bool sharp;
  final List<Completer<Uint8List?>> waiters = [];
  final List<bool Function()> wanted = [];
  bool ahead = false;

  String get id => '${sharp ? 'H' : (large ? 'L' : 'S')}${photo.cacheKey}';

  // Made ahead of time, or somebody still wants it.
  bool get stillWanted => ahead && waiters.isEmpty || wanted.any((w) => w());

  void finish(Uint8List? bytes) {
    for (final w in waiters) {
      if (!w.isCompleted) w.complete(bytes);
    }
    waiters.clear();
  }
}

/// Small, large and sharp versions of the timeline's photos, kept in memory. At most a few are made at once
/// (more only slow each other down), the newest request goes first (it is what is on screen now),
/// and a request nobody wants any more is dropped before it starts.
class PreviewLoader {
  static const int smallSize = 120;
  static const int largeSize = 400;

  /// For a picture shown big (the middle of the lens, a memory's main photo): the large one is not enough there.
  static const int sharpSize = 1080;
  static const int _maxRunning = 3;
  static const int _keepSmall = 900;
  static const int _keepLarge = 40;
  static const int _keepSharp = 10;

  /// Whether a picture shown [logical] big, on a screen with [pixelRatio], needs more than the large version.
  static bool wantsSharp(Size logical, double pixelRatio) => logical.longestSide * pixelRatio > largeSize * 1.1;

  final LinkedHashMap<String, Uint8List> _small = LinkedHashMap();
  final LinkedHashMap<String, Uint8List> _large = LinkedHashMap();
  final LinkedHashMap<String, Uint8List> _sharp = LinkedHashMap();
  final Map<String, _Job> _jobs = {};
  final List<_Job> _now = []; // wanted now; newest last
  final List<_Job> _ahead = []; // made ahead of time, in the order given
  final Set<String> _failed = {};
  int _running = 0;

  /// What is in memory already (the sharpest version when [sharp], the large one when [large], else the small one).
  Uint8List? peek(PreviewPhoto photo, {required bool large, bool sharp = false}) {
    final cache = sharp ? _sharp : (large ? _large : _small);
    final bytes = cache.remove(photo.cacheKey);
    if (bytes != null) cache[photo.cacheKey] = bytes; // most recently used goes last
    return bytes;
  }

  bool failed(PreviewPhoto photo) => _failed.contains('S${photo.cacheKey}');

  /// The picture, from memory or made now. [wanted] says whether it is still needed once its turn
  /// comes (a frame that has slid away no longer needs it).
  Future<Uint8List?> get(PreviewPhoto photo, {required bool large, bool sharp = false, bool Function()? wanted}) {
    final cached = peek(photo, large: large, sharp: sharp);
    if (cached != null) return Future.value(cached);
    final id = '${sharp ? 'H' : (large ? 'L' : 'S')}${photo.cacheKey}';
    if (_failed.contains(id)) return Future.value(null);

    var job = _jobs[id];
    if (job == null) {
      job = _Job(photo, large, sharp);
      _jobs[id] = job;
      _now.add(job);
    } else if (_ahead.remove(job)) {
      _now.add(job); // asked for now after all
    }
    final completer = Completer<Uint8List?>();
    job.waiters.add(completer);
    job.wanted.add(wanted ?? () => true);
    _pump();
    return completer.future;
  }

  /// Makes the small versions of [photos] when there is nothing more urgent. With [front] they go
  /// before what is already waiting (the ones near where the playhead is now).
  void prefetch(Iterable<PreviewPhoto> photos, {bool front = false}) {
    final fresh = <_Job>[];
    for (final photo in photos) {
      final id = 'S${photo.cacheKey}';
      if (_small.containsKey(photo.cacheKey) || _jobs.containsKey(id) || _failed.contains(id)) continue;
      final job = _Job(photo, false)..ahead = true;
      _jobs[id] = job;
      fresh.add(job);
    }
    if (front) {
      _ahead.insertAll(0, fresh);
    } else {
      _ahead.addAll(fresh);
    }
    _pump();
  }

  void _pump() {
    while (_running < _maxRunning) {
      final _Job job;
      if (_now.isNotEmpty) {
        job = _now.removeLast();
      } else if (_ahead.isNotEmpty) {
        job = _ahead.removeAt(0);
      } else {
        return;
      }
      if (!job.stillWanted) {
        _jobs.remove(job.id);
        job.finish(null);
        continue;
      }
      _running++;
      NativeServices()
          .loadThumbnail(
            uri: job.photo.uri,
            isVideo: job.photo.isVideo,
            timestampMs: job.photo.tsMs,
            size: job.sharp ? sharpSize : (job.large ? largeSize : smallSize),
          )
          .then<Uint8List?>((bytes) => bytes)
          .catchError((_) => null)
          .then((bytes) {
            _running--;
            _jobs.remove(job.id);
            if (bytes == null) {
              _failed.add(job.id);
            } else {
              final cache = job.sharp ? _sharp : (job.large ? _large : _small);
              cache[job.photo.cacheKey] = bytes;
              final keep = job.sharp ? _keepSharp : (job.large ? _keepLarge : _keepSmall);
              while (cache.length > keep) {
                cache.remove(cache.keys.first);
              }
            }
            job.finish(bytes);
            _pump();
          });
    }
  }
}

/// A picture of the timeline, shown as soon as there is anything of it: the small version at once, then the
/// large one when [large] and it has arrived, then - when [sharp], for a picture shown big - the sharp one. Each
/// better version fades in over the one before, so nothing jumps or blinks while it sharpens.
class PreviewImage extends StatefulWidget {
  const PreviewImage({
    super.key,
    required this.photo,
    required this.loader,
    this.large = false,
    this.sharp = false,
    this.alignment = Alignment.center,
    this.fill = AppColors.parchment,
  });

  final PreviewPhoto photo;
  final PreviewLoader loader;
  final bool large;

  /// Also fetch the biggest version, once the large one is in.
  final bool sharp;
  final Alignment alignment;

  /// What shows until the picture is there.
  final Color fill;

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  // What is on show, and a better version fading in over it. _top is the best version either of them is.
  Uint8List? _shown;
  Uint8List? _incoming;
  bool _incomingReady = false; // decoded, so it is at least starting to show
  int _top = 0; // 0 nothing yet, 1 small, 2 large, 3 sharp

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PreviewImage old) {
    super.didUpdateWidget(old);
    if (old.photo.cacheKey != widget.photo.cacheKey) {
      _shown = null;
      _incoming = null;
      _incomingReady = false;
      _top = 0;
    }
    if (old.photo.cacheKey != widget.photo.cacheKey || old.large != widget.large || old.sharp != widget.sharp) _resolve();
  }

  void _resolve() {
    final photo = widget.photo, loader = widget.loader;
    final wantLarge = widget.large || widget.sharp;
    final sharp = widget.sharp ? loader.peek(photo, large: true, sharp: true) : null;
    final large = wantLarge ? loader.peek(photo, large: true) : null;
    final small = loader.peek(photo, large: false);
    final best = sharp ?? large ?? small;
    final rank = sharp != null ? 3 : (large != null ? 2 : (small != null ? 1 : 0));
    if (best != null && rank > _top) {
      _top = rank;
      // Already in memory: shown at once if there is nothing yet, else faded in over what is there.
      if (_shown == null && _incoming == null) {
        _shown = best;
      } else {
        _incoming = best;
        _incomingReady = false;
      }
    }

    final key = photo.cacheKey;
    if (_top < 1) _fetch(key, 1);
    if (wantLarge && _top < 2) {
      _fetch(key, 2);
    } else if (widget.sharp && _top == 2) {
      _fetch(key, 3);
    }
  }

  void _fetch(String key, int rank) {
    bool wanted() =>
        mounted && widget.photo.cacheKey == key && (rank <= 1 || widget.large || widget.sharp) && (rank < 3 || widget.sharp);
    widget.loader.get(widget.photo, large: rank >= 2, sharp: rank == 3, wanted: wanted).then((b) {
      if (b == null || !wanted()) return;
      _deliver(b, rank);
      // The sharp version follows the large one (not asked for at the same time: a picture that is only passing by
      // never needs it).
      if (rank == 2 && widget.sharp) _fetch(key, 3);
    });
  }

  void _deliver(Uint8List bytes, int rank) {
    if (rank <= _top) return;
    setState(() {
      _top = rank;
      // One that is already showing becomes what is shown, and this one fades in over it. One that has not been
      // decoded yet is dropped: it would leave a hole where the picture was.
      if (_incoming != null && _incomingReady) _shown = _incoming;
      _incoming = bytes;
      _incomingReady = false;
    });
  }

  // The fade of the newest version has ended: it is what is shown now.
  void _promote() {
    if (!mounted || _incoming == null) return;
    setState(() {
      _shown = _incoming;
      _incoming = null;
      _incomingReady = false;
    });
  }

  Widget _image(Uint8List bytes) {
    return Image.memory(
      bytes,
      key: ObjectKey(bytes),
      fit: BoxFit.cover,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, sync) {
        final ready = frame != null || sync;
        if (ready && identical(bytes, _incoming)) _incomingReady = true;
        return AnimatedOpacity(
          opacity: ready ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          onEnd: _promote,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown, incoming = _incoming;
    return ColoredBox(
      color: widget.fill,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shown != null) _image(shown),
          if (incoming != null) _image(incoming),
        ],
      ),
    );
  }
}

/// The photos of one month: the best few, and how many there are in all.
class MonthMedia {
  const MonthMedia(this.total, this.photos);

  final int total;
  final List<PreviewPhoto> photos;
}

// ---------------------------------------------------------------------------- the controller

/// What the timeline's photos need: the picks for the filmstrip, the place of the playhead in
/// them, and each person's photo for the month the playhead has settled on.
class TimelinePreview extends ChangeNotifier {
  TimelinePreview({required this.window}) {
    window.centre.addListener(_onCentre);
    window.moving.addListener(_onMoving);
    window.stripActive.addListener(notifyListeners);
  }

  final TimelineWindow window;
  final PreviewLoader loader = PreviewLoader();

  TimelineLayout _layout = TimelineLayout.empty;

  // Set on dispose: answers that arrive after it are dropped.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---- the filmstrip ----

  /// The chosen photos and videos, in the order they were taken.
  List<PreviewPhoto> picks = const [];

  // For each month of the axis: how many picks it has, and the place of its first (or of the next
  // one, for an empty month).
  List<int> _count = const [];
  List<int> _first = const [];
  int _base = 0;

  Object? _fetchedFor;
  bool _fetching = false;
  bool _fetchAgain = false;

  /// Tells it the axis and people now showing. [dataVersion] changes whenever the dates change;
  /// then the picks are chosen again.
  void update(TimelineLayout layout, {required Object dataVersion, required bool datesDone}) {
    _layout = layout;
    if (datesDone && !identical(_fetchedFor, dataVersion)) {
      _fetchedFor = dataVersion;
      _scheduleFetch();
    } else if (picks.isNotEmpty && (_base != layout.startMonth || _count.length != layout.monthCount)) {
      scheduleMicrotask(_reindex);
    }
  }

  // The picks are chosen again when the dates change, but not more than every few seconds: while photos
  // are being scanned the dates change all the time, and every choosing reads all the faces.
  Timer? _fetchTimer;
  DateTime? _lastFetch;

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
        picks = await NativeServices().timelinePicks();
        if (_disposed) return;
        _byMonth.clear();
        _media.clear();
        _reindex();
        // What was shown for the month it is on (people's photos, the month's photos) is asked for again.
        if (settled) unawaited(_loadPeople(_settledMonth));
        if (!window.moving.value) unawaited(_loadMonth(window.centre.value));
      } while (_fetchAgain);
    } catch (e) {
      debugPrint('timelinePicks failed: $e');
    } finally {
      _fetching = false;
    }
  }

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
    // Picks are in date order, so the first of each month is the running total before it.
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

  // The picks that fall on the axis (the ones the lens walks through).
  List<PreviewPhoto> _shown = const [];
  List<PreviewPhoto> get shown => _shown;

  /// How many picks the month [month] has.
  int countIn(int month) {
    final o = month - _base;
    return o < 0 || o >= _count.length ? 0 : _count[o];
  }

  /// Where the playhead (at [monthFloat], a month and the part of it gone by) is in [shown]: a
  /// photo's number, with a fraction between two. The photos of a month share its length, so a
  /// month with many has the row linger, and an empty one holds it still between the photos
  /// either side.
  double indexAt(double monthFloat) {
    if (_count.isEmpty) return 0;
    final rel = monthFloat - _base;
    final month = rel.floor().clamp(0, _count.length - 1);
    final part = (rel - month).clamp(0.0, 1.0);
    final c = _count[month];
    return c > 0 ? _first[month] + part * c - 0.5 : _first[month] - 0.5;
  }

  // The small versions of the photos near the playhead first, then everyone else's.
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

  // ---- settling ----

  /// Whether the playhead has stayed on a month for a moment (the sharp photos and the people's
  /// photos wait for that, so a fast drag costs nothing).
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

  void _onSettled() {
    settled = true;
    _settledMonth = window.centre.value;
    notifyListeners();
    unawaited(_loadPeople(_settledMonth));
    // Resting on a month (also when the timeline has just opened): its photos fill the preview.
    if (!window.moving.value) unawaited(_loadMonth(_settledMonth));
    _prefetchAround(front: true);
  }

  // ---- each person's photo of the month ----

  final LinkedHashMap<int, Map<int, PreviewPhoto>> _byMonth = LinkedHashMap();

  /// [personId]'s clearest photo of the month the playhead is on - once it has settled there; null
  /// while it is moving, or when they have none then.
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
        for (final photo in await NativeServices().timelineMonthPhotos(from, to, lit)) {
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

  // ---- the month at rest ----

  final LinkedHashMap<int, MonthMedia> _media = LinkedHashMap();

  /// The photos of [month] (the best few, and how many in all), once they are known.
  MonthMedia? mediaFor(int month) => _media[month];

  void _onMoving() {
    // The years have come to rest on a month: its photos are fetched, to fill the preview - and, as
    // they were just moved, it may open out whatever the list is doing.
    if (!window.moving.value) {
      if (_scrollCollapsed) {
        _scrollCollapsed = false;
        notifyListeners();
      }
      unawaited(_loadMonth(window.centre.value));
    }
  }

  Future<void> _loadMonth(int month) async {
    if (_media.containsKey(month)) {
      notifyListeners();
      return;
    }
    try {
      final from = DateTime(month ~/ 12, month % 12 + 1);
      final to = DateTime(month ~/ 12, month % 12 + 2);
      final found = await NativeServices().timelineMonthMedia(from, to, limit: 9);
      _media[month] = MonthMedia(found.total, found.photos);
      while (_media.length > 12) {
        _media.remove(_media.keys.first);
      }
      // Small versions at once, so the tiles have something to show as they open.
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

  /// The moments of several people (the whole gang, new faces, a reunion) in [month].
  List<GroupMoment> groupsIn(int month) => _layout.groupsIn(month);

  /// The moments (first photo together, a return, a lovely run) that fall in [month].
  List<({TimelineRowData row, Milestone milestone})> momentsIn(int month) => _layout.momentsIn(month);

  /// How many months one pixel of dragging the lens moves the timeline: a photo's width of
  /// dragging is one photo, which is a part of the month it is in.
  double monthsPerLensPixel(double step) => 1 / (math.max(1, countIn(window.centre.value)) * step);

  // ---- making room for the list ----

  // Set when the person scrolls the list (up or down the page): the preview slims with it and stays
  // slim, since they have gone to look at the list. Cleared when the list is back at the top, or when
  // the years have been moved again (a slide along a line, a drag of the row): then they want to see
  // the month, wherever the list is.
  bool _scrollCollapsed = false;

  /// The person is scrolling the list (a finger on it, or it still gliding).
  void userScrolling() {
    if (_scrollCollapsed) return;
    _scrollCollapsed = true;
    notifyListeners();
  }

  /// Where the list is scrolled to: back at the top, the preview may open out again.
  void setListOffset(double pixels) {
    if (_scrollCollapsed && pixels <= 6) {
      _scrollCollapsed = false;
      notifyListeners();
    }
  }

  /// Whether the preview should stay out of the way of the list: it was scrolled away from the
  /// top, or a finger is moving the strips.
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

// ------------------------------------------------------------------------------------- bento

/// How [count] pictures are laid out in a box [size]: the first (the hero) biggest, the rest
/// around it, no gaps but [gap]. [heroRight] puts the hero on the right instead of the left.
List<Rect> bentoRects(int count, Size size, {bool heroRight = false, double gap = 4}) {
  if (count <= 0) return const [];
  final w = size.width, h = size.height;
  var rects = <Rect>[];
  if (count == 1) {
    rects = [Rect.fromLTWH(0, 0, w, h)];
  } else if (count == 2) {
    final cw = (w - gap) / 2;
    rects = [Rect.fromLTWH(0, 0, cw, h), Rect.fromLTWH(cw + gap, 0, cw, h)];
  } else if (count == 3) {
    final big = (w - gap) * 0.6, small = (w - gap) - big, ch = (h - gap) / 2;
    rects = [
      Rect.fromLTWH(0, 0, big, h),
      Rect.fromLTWH(big + gap, 0, small, ch),
      Rect.fromLTWH(big + gap, ch + gap, small, ch),
    ];
  } else {
    // Four columns; the hero is two across and two down, the rest fill the cells round it a row at
    // a time, the last row stretched so nothing is left empty.
    const cols = 4;
    final rows = count <= 5 ? 2 : (count <= 9 ? 3 : 4);
    final cw = (w - gap * (cols - 1)) / cols, ch = (h - gap * (rows - 1)) / rows;
    rects.add(Rect.fromLTWH(0, 0, cw * 2 + gap, ch * 2 + gap));
    var left = count - 1;
    for (var r = 0; r < rows && left > 0; r++) {
      final first = r < 2 ? 2 : 0;
      final available = cols - first;
      final used = math.min(available, left);
      left -= used;
      final rowWidth = available * cw + (available - 1) * gap;
      final each = (rowWidth - (used - 1) * gap) / used;
      final x0 = first * (cw + gap);
      for (var k = 0; k < used; k++) {
        rects.add(Rect.fromLTWH(x0 + k * (each + gap), r * (ch + gap), each, ch));
      }
    }
  }
  if (heroRight) {
    rects = [for (final r in rects) Rect.fromLTWH(w - r.right, r.top, r.width, r.height)];
  }
  return rects;
}

// ------------------------------------------------------------------------------------- lens

/// The photos under the top bar. While the years move: a row of photos in date order, the one at
/// the playhead large (and dragging the row moves the years). When they come to rest on a month,
/// the preview grows and that month opens out into all its photos around the one that was in the
/// middle; moving again folds them back into one.
class TimelineLens extends StatefulWidget {
  const TimelineLens({super.key, required this.preview, required this.window, this.onOpenMonth});

  final TimelinePreview preview;
  final TimelineWindow window;

  /// A photo of the opened-out month was tapped: take the person to that month's photos.
  final void Function(int month, PreviewPhoto photo)? onOpenMonth;

  @override
  State<TimelineLens> createState() => _TimelineLensState();
}

class _TimelineLensState extends State<TimelineLens> with TickerProviderStateMixin {
  // 0 = the row of photos, 1 = the month opened out.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    reverseDuration: const Duration(milliseconds: 340),
  );

  // 0 = the row at its size, 1 = shrunk to a slim row (the list is being scrolled).
  late final AnimationController _shrink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 340),
  );

  static const double _slimHeight = 118;

  @override
  void initState() {
    super.initState();
    widget.preview.addListener(_sync);
    widget.window.moving.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_sync);
    widget.window.moving.removeListener(_sync);
    _open.dispose();
    _shrink.dispose();
    super.dispose();
  }

  // The month the preview opened out for, and the photo that led it: kept while it folds back, even
  // though the playhead has moved on by then.
  int? _openedMonth;
  PreviewPhoto? _openedHero;

  void _sync() {
    if (!mounted) return;
    // Only a finger on the strips makes the row itself slimmer; a scrolled list does that by
    // scrolling (the header collapses with it).
    final compact = widget.preview.compact;
    if (widget.window.stripActive.value) {
      if (_shrink.status != AnimationStatus.forward && _shrink.status != AnimationStatus.completed) _shrink.forward();
    } else if (_shrink.status != AnimationStatus.reverse && _shrink.status != AnimationStatus.dismissed) {
      _shrink.reverse();
    }
    final media = widget.preview.mediaFor(widget.window.centre.value);
    final want = !compact &&
        !widget.window.moving.value &&
        media != null &&
        media.photos.isNotEmpty &&
        widget.preview.shown.isNotEmpty;
    if (want) {
      if (_open.status != AnimationStatus.forward && _open.status != AnimationStatus.completed) {
        final photos = widget.preview.shown;
        final idx = widget.preview.indexAt(widget.window.centreMonth);
        _openedMonth = widget.window.centre.value;
        _openedHero = photos[idx.round().clamp(0, photos.length - 1)];
        _open.forward();
      }
    } else if (_open.status != AnimationStatus.reverse && _open.status != AnimationStatus.dismissed) {
      _open.reverse();
    }
  }

  // Frame sizes follow the height the row has.
  static double _frameHeight(double collapsed) => collapsed * 0.705;
  static double _frameWidth(double collapsed) => _frameHeight(collapsed) * 0.71;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final rowHeight = (screen * 0.27).clamp(168.0, 224.0);
    final opened = (screen * 0.43).clamp(250.0, 360.0);
    const gap = AppSpacing.sm;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.window, widget.preview, _open, _shrink]),
      builder: (context, _) {
        final photos = widget.preview.shown;
        if (photos.isEmpty) return const SliverToBoxAdapter(child: SizedBox(width: double.infinity));
        final t = _open.value;
        // The row, or - while a finger is on the strips - a slimmer one; opened out it grows from there.
        final base = rowHeight + (_slimHeight - rowHeight) * Curves.easeOutCubic.transform(_shrink.value);
        final full = base + (opened - base) * Curves.easeInOutCubic.transform(t);
        // A header of the list that is pinned and collapses as the list scrolls: scrolling down
        // slims it step by step, scrolling back up grows it step by step.
        // Opened out, it keeps the room it needs even when the list is scrolled (the month was opened
        // on purpose); folded it can collapse to the slim row.
        final least = _slimHeight + (opened - _slimHeight) * Curves.easeInOutCubic.transform(t);
        return SliverPersistentHeader(
          pinned: true,
          delegate: _LensDelegate(
            maxHeight: full + gap,
            minHeight: least + gap,
            builder: (context, shrinkOffset) {
              final height = math.max(least, full - shrinkOffset);
              final slim = ((full - height) / math.max(1.0, full - _slimHeight)).clamp(0.0, 1.0);
              final rowNow = base + (_slimHeight - base) * slim;
              return Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.base, 0, AppSpacing.base, gap),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // The row can be dragged too: it moves the years.
                  onHorizontalDragStart: (_) => widget.window.dragStart(),
                  onHorizontalDragUpdate: (d) =>
                      widget.window.dragBy(d.delta.dx * _toStripPixels(_frameWidth(rowNow))),
                  onHorizontalDragEnd: (d) => widget.window.dragEnd(
                    d.velocity.pixelsPerSecond.dx * _toStripPixels(_frameWidth(rowNow)),
                  ),
                  onHorizontalDragCancel: () => widget.window.dragEnd(0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: SizedBox(
                      height: height,
                      width: double.infinity,
                      child: ColoredBox(
                        color: AppColors.parchment,
                        child: LayoutBuilder(
                          builder: (context, box) => _body(context, box.maxWidth, rowNow, opened, t, photos),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Dragging the row by a pixel moves the strips by this many pixels (it is in photos, the strips
  // in months).
  double _toStripPixels(double frameWidth) =>
      widget.preview.monthsPerLensPixel(frameWidth * 0.9) * widget.window.ppm;

  // Where frame [i] is in the row (in the preview's top-left corner coordinates).
  Rect _frameRect(int i, double idx, double width, double collapsed) {
    final fw = _frameWidth(collapsed), fh = _frameHeight(collapsed);
    final dist = i - idx;
    final a = dist.abs();
    final scale = math.max(0.5, 1.25 - 0.3 * a);
    final w = fw * scale, h = fh * scale;
    final offset = a < 1 ? a * fw * 0.9 : fw * 0.9 + (a - 1) * fw * 0.62;
    final x = width / 2 + (dist < 0 ? -offset : offset) - w / 2;
    return Rect.fromLTWH(x, (collapsed - h) / 2, w, h);
  }

  Widget _body(
    BuildContext context,
    double width,
    double collapsed,
    double opened,
    double t,
    List<PreviewPhoto> photos,
  ) {
    final preview = widget.preview, window = widget.window;
    final month = window.centre.value;
    final idx = preview.indexAt(window.centreMonth);
    // Opened (or folding back) it is the month it was opened for that shows, not where the
    // playhead has got to since.
    final openMonth = _openedMonth ?? month;
    var heroIndex = idx.round().clamp(0, photos.length - 1);
    final led = _openedHero;
    if (led != null && t > 0) {
      final found = photos.indexWhere((p) => p.key == led.key);
      if (found >= 0) heroIndex = found;
    }

    return Stack(
      children: [
        // The row of photos - fading out as the month opens.
        if (t < 0.6)
          Positioned.fill(
            child: Opacity(
              opacity: (1 - t * 1.8).clamp(0.0, 1.0),
              child: _row(context, width, collapsed, photos, idx, month),
            ),
          ),
        // The month opened out.
        if (t > 0)
          ..._opened(context, width, collapsed, opened, t, photos[heroIndex], _frameRect(heroIndex, idx, width, collapsed), openMonth),
        // Where the playhead is.
        Positioned(
          left: width / 2 - 3,
          bottom: 0,
          child: Opacity(
            opacity: (1 - t * 2).clamp(0.0, 1.0),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, double width, double collapsed, List<PreviewPhoto> photos, double idx, int month) {
    final textTheme = Theme.of(context).textTheme;
    final preview = widget.preview;
    final first = math.max(0, idx.floor() - 5);
    final last = math.min(photos.length - 1, idx.floor() + 6);

    // Farthest first, so the nearest paint on top.
    final order = [for (var i = first; i <= last; i++) i]..sort((a, b) => (b - idx).abs().compareTo((a - idx).abs()));
    final children = <Widget>[];
    for (final i in order) {
      final photo = photos[i];
      final dist = i - idx;
      final a = dist.abs();
      final rect = _frameRect(i, idx, width, collapsed);
      final near = a < 1.5;
      children.add(
        Positioned(
          key: ValueKey(photo.cacheKey),
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.canvas, width: 2.5),
              boxShadow: a < 0.8
                  ? [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6))]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7.5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PreviewImage(
                    photo: photo,
                    loader: preview.loader,
                    // The sharp one only for the middle few, and once the playhead is still.
                    large: near && preview.settled,
                    // The one in the middle, big on the screen, is sharpened once the playhead is still.
                    sharp: a < 0.8 && preview.settled && PreviewLoader.wantsSharp(rect.size, MediaQuery.devicePixelRatioOf(context)),
                    fill: AppColors.hairline,
                  ),
                  if (near)
                    // On the outer corner, so the frame in front does not cover it.
                    Positioned(
                      left: dist > 0.4 ? null : 6,
                      right: dist > 0.4 ? 6 : null,
                      bottom: 4,
                      child: Text(
                        _dayLabel(photo.taken),
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.onMedia,
                          fontWeight: FontWeight.w600,
                          shadows: const [Shadow(color: AppColors.scrim54, blurRadius: 4)],
                        ),
                      ),
                    ),
                  if (photo.isVideo)
                    const Positioned(
                      right: 5,
                      top: 5,
                      child: Icon(Icons.play_circle_fill_rounded, size: 18, color: AppColors.onMedia),
                    ),
                  // Frames further out are veiled, not see-through: they sit behind the next one.
                  if (a > 0.3)
                    Positioned.fill(
                      child: ColoredBox(
                        color: AppColors.parchment.withValues(alpha: math.min(0.6, 0.17 * a)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ...children,
        // A month with nothing in it: the row waits, and says why.
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              layoutBuilder: switcherStack(),
              child: preview.countIn(month) == 0
                  ? Container(
                      key: const ValueKey('empty'),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.canvas.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'No photos in ${monthLabel(month)}',
                        style: textTheme.labelSmall?.copyWith(color: AppColors.ink80),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('full')),
            ),
          ),
        ),
      ],
    );
  }

  // The month's photos in a bento: the one that was in the middle of the row grows into the big
  // tile, and the others come out from behind it, one after another.
  List<Widget> _opened(
    BuildContext context,
    double width,
    double collapsed,
    double opened,
    double t,
    PreviewPhoto middle,
    Rect middleRect,
    int month,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final media = widget.preview.mediaFor(month);
    if (media == null || media.photos.isEmpty) return const [];

    // The middle photo leads; the rest follow in the order they were taken.
    final photos = <PreviewPhoto>[
      middle,
      for (final p in media.photos)
        if (p.key != middle.key) p,
    ].take(9).toList();
    const pad = 8.0;
    final area = Size(width - pad * 2, opened - pad * 2);
    final rects = bentoRects(photos.length, area, heroRight: month.isOdd);
    final remaining = media.total - photos.length;

    final out = <Widget>[];
    for (var i = photos.length - 1; i >= 0; i--) {
      final target = rects[i].shift(const Offset(pad, pad));
      // The hero starts where the middle frame was; the rest start small, behind it.
      final from = i == 0 ? middleRect : Rect.fromCenter(center: middleRect.center, width: middleRect.width * 0.55, height: middleRect.height * 0.55);
      final begin = i == 0 ? 0.0 : math.min(0.55, 0.14 + 0.05 * i);
      final local = Curves.easeOutCubic.transform(((t - begin) / (1 - begin)).clamp(0.0, 1.0));
      final rect = Rect.lerp(from, target, local)!;
      final radius = 10 + 4 * local;
      out.add(
        Positioned(
          key: ValueKey('open${photos[i].cacheKey}'),
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: Opacity(
            opacity: i == 0 ? 1 : local,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: t >= 0.8 && widget.onOpenMonth != null ? () => widget.onOpenMonth!(month, photos[i]) : null,
              child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: i == 0 || local > 0.3
                    ? [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.16 * (i == 0 ? 1 : local)), blurRadius: 12, offset: const Offset(0, 4))]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PreviewImage(
                      photo: photos[i],
                      loader: widget.preview.loader,
                      large: true,
                      // The big tiles of the opened month, once they have settled into place.
                      sharp: t >= 0.8 && PreviewLoader.wantsSharp(target.size, MediaQuery.devicePixelRatioOf(context)),
                      fill: AppColors.hairline,
                      alignment: const Alignment(0, -0.25),
                    ),
                    if (photos[i].isVideo)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(Icons.play_circle_fill_rounded, size: 20, color: AppColors.onMedia),
                      ),
                    // The last tile says how many more there are.
                    if (i == photos.length - 1 && remaining > 0)
                      Positioned.fill(
                        child: ColoredBox(
                          color: AppColors.scrim.withValues(alpha: 0.45),
                          child: Center(
                            child: Text(
                              '+$remaining',
                              style: textTheme.titleMedium?.copyWith(color: AppColors.onMedia, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      );
    }

    // The moments of the month, as chips across the top: who, and what happened - the two that matter most
    // (a first photo together is the same moment for both of them: one chip, both faces).
    final candidates = <({int importance, _MomentChip chip})>[];
    final pairs = <String>{};
    for (final m in widget.preview.momentsIn(month)) {
      final other = m.milestone.withId;
      IconData icon;
      switch (m.milestone.kind) {
        case MilestoneKind.firstTogether:
          icon = Icons.favorite_rounded;
        case MilestoneKind.comeback:
          icon = Icons.waving_hand_rounded;
        case MilestoneKind.lovelyRun:
          icon = Icons.auto_awesome_rounded;
      }
      if (m.milestone.kind == MilestoneKind.firstTogether && other != null) {
        final a = m.row.person.id;
        if (!pairs.add(a < other ? '$a-$other' : '$other-$a')) continue;
        final friend = widget.preview.personById(other);
        if (friend != null) {
          candidates.add((
            importance: m.milestone.importance,
            chip: _MomentChip(people: [m.row.person, friend], icon: icon, text: 'First photo together'),
          ));
          continue;
        }
      }
      candidates.add((
        importance: m.milestone.importance,
        chip: _MomentChip(people: [m.row.person], icon: icon, text: m.milestone.short),
      ));
    }
    for (final g in widget.preview.groupsIn(month)) {
      candidates.add((
        importance: g.importance,
        chip: _MomentChip(people: g.people.take(3).toList(), icon: groupIcon(g.kind), text: g.short),
      ));
    }
    candidates.sort((a, b) => b.importance.compareTo(a.importance));
    final moments = [for (final c in candidates.take(2)) c.chip];
    if (moments.isNotEmpty) {
      out.add(
        Positioned(
          left: 14,
          right: 14,
          top: 14,
          child: IgnorePointer(
            child: Opacity(
              opacity: ((t - 0.75) / 0.25).clamp(0.0, 1.0),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs + 2,
                children: moments,
              ),
            ),
          ),
        ),
      );
    }

    // The month and how many photos it has, on the big tile (shrinking to fit if it is narrow).
    final hero = rects[0].shift(const Offset(pad, pad));
    out.add(
      Positioned(
        left: hero.left + 8,
        width: hero.width - 16,
        top: hero.bottom - 34,
        child: Opacity(
          opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.scrim.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${monthLabel(month)}  ·  ${media.total == 1 ? '1 photo' : '${media.total} photos'}',
                  style: textTheme.labelMedium?.copyWith(color: AppColors.onMedia, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return out;
  }

  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dayLabel(DateTime t) => '${_short[t.month - 1]} ${t.day}';
}

/// A little card on the opened-out month: the person's face, an icon, and what happened.
class _MomentChip extends StatelessWidget {
  const _MomentChip({required this.people, required this.icon, required this.text});

  final List<Person> people;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One face, or two overlapping for a pair.
          SizedBox(
            width: 24.0 + (people.length - 1) * 16,
            height: 24,
            child: Stack(
              children: [
                for (var i = 0; i < people.length; i++)
                  Positioned(
                    left: i * 16.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.canvas, width: 1.5),
                      ),
                      child: FaceAvatar(faceId: people[i].coverFaceId, size: 24),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The preview as a header of the list: pinned, as tall as it is at rest at the top, and collapsing to a
/// slim row as the list is scrolled (the way a collapsing app bar does).
class _LensDelegate extends SliverPersistentHeaderDelegate {
  _LensDelegate({required this.maxHeight, required this.minHeight, required this.builder});

  final double maxHeight, minHeight;
  final Widget Function(BuildContext context, double shrinkOffset) builder;

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => builder(context, shrinkOffset);

  @override
  bool shouldRebuild(covariant _LensDelegate old) => true;
}
