import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/palettes/people_palette.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

// The People tab's timeline, built like the timeline of a video editor: a column of faces on the
// left that stays put, and the years sliding by beside it. Drag to move through the years (it
// carries on a little when let go), pinch to zoom from the whole library down to single months,
// or jump with the zoom buttons. A line in the middle is the playhead: whoever has photos in the
// month under it lights up, everyone else dims. A thin overview of all the years sits at the top
// with a window showing where you are; drag it to jump.

const double _pad = AppSpacing.base;
const double _leftColumn = 64;

/// The column of names when the list is collapsed (no faces, so the names get more room).
const double _compactColumn = 92;

double _columnWidth(bool compact) => compact ? _compactColumn : _leftColumn;
const double _columnGap = AppSpacing.md;
const double _avatar = 40;
const double _stripHeight = 40;
const double _compactStripHeight = 30;

/// In the collapsed list a gap of up to this many empty months does not break a line.
const int _runGap = 2;

/// How close the zoom can go: this many pixels to a month (about a month a thumb wide).
const double _maxPixelsPerMonth = 48;

/// How many months show on opening (the last three years).
const double _openingMonths = 36;

/// A person's colour on the timeline: soft, a little dusty, and the same every time.
const List<Color> _tones = [
  PeoplePalette.red450, // terracotta
  AppColors.honey, // honey
  PeoplePalette.red400, // rose
  PeoplePalette.green450, // sage
  AppColors.primary, // the app's teal
  PeoplePalette.sky450, // dusty blue
  PeoplePalette.indigo450, // plum
  PeoplePalette.gold550, // olive
];

/// The stretches of months a person is in, as (first, last) places on the axis: months in a row
/// make one stretch, and a gap of only a month or two does not end it.
List<(int, int)> timelineRuns(List<int> offsets, {int maxGap = _runGap}) {
  final runs = <(int, int)>[];
  for (final o in offsets) {
    if (runs.isNotEmpty && o - runs.last.$2 <= maxGap + 1) {
      runs[runs.length - 1] = (runs.last.$1, o);
    } else {
      runs.add((o, o));
    }
  }
  return runs;
}

IconData _momentIcon(MilestoneKind kind) {
  switch (kind) {
    case MilestoneKind.firstTogether:
      return Icons.favorite_rounded;
    case MilestoneKind.comeback:
      return Icons.waving_hand_rounded;
    case MilestoneKind.lovelyRun:
      return Icons.auto_awesome_rounded;
  }
}

/// How an AnimatedSwitcher stacks its pictures, without ever having two children with the same key. The
/// default can: when what it shows goes A, B, A again before the first A has faded out (a caption
/// changing as the playhead crosses months, quickly), the old A and the new A are both in the stack and
/// Flutter complains. The old one is dropped here instead.
AnimatedSwitcherLayoutBuilder switcherStack({
  AlignmentGeometry alignment = Alignment.center,
  StackFit fit = StackFit.loose,
}) {
  return (Widget? current, List<Widget> previous) {
    final seen = <Key?>{if (current != null) current.key};
    final kept = <Widget>[];
    for (final w in previous.reversed) {
      if (w.key != null && !seen.add(w.key)) continue;
      kept.add(w);
    }
    return Stack(alignment: alignment, fit: fit, children: [...kept.reversed, if (current != null) current]);
  };
}

Color _toneFor(int personId) => _tones[((personId * 2654435761) & 0x7fffffff) % _tones.length];

/// Which rows have already come in and which strips have already developed, so they do not play
/// again on a scroll back or a change of order.
class TimelineMemory {
  final Set<int> entered = {};
  final Set<int> developed = {};
}

// ------------------------------------------------------------------------------------ window

/// Which stretch of the years is on screen, shared by the ruler, the overview and every strip.
/// Months here are absolute (year * 12 + month), so the view stays where it is when more dates
/// arrive and the axis grows.
class TimelineWindow extends ChangeNotifier {
  TimelineWindow(TickerProvider vsync)
    : _fling = AnimationController.unbounded(vsync: vsync),
      _tween = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 380)) {
    _fling.addListener(_onFling);
    _fling.addStatusListener(_onFlingStatus);
    _tween.addListener(_onTween);
    _tween.addStatusListener((_) => _updateMoving());
  }

  final AnimationController _fling, _tween;

  /// The month under the playhead (changes only when it moves on to another month).
  final ValueNotifier<int> centre = ValueNotifier(0);

  /// While two fingers are on the strips: the list must not scroll under them.
  final ValueNotifier<bool> pinching = ValueNotifier(false);

  /// True while anything moves the years - a finger, a glide, a settling, a zoom - and for a
  /// moment after: false only once it has come to rest on the middle of a month.
  final ValueNotifier<bool> moving = ValueNotifier(false);

  /// True from a finger touching the strips (moving or zooming them) until the years are at rest
  /// again: the preview makes room for the list meanwhile.
  final ValueNotifier<bool> stripActive = ValueNotifier(false);

  /// Counts the jumps to a month (a flag, the moments button): the list goes back to the top then, so
  /// the preview can open out where it jumped to.
  final ValueNotifier<int> jumps = ValueNotifier(0);
  Timer? _restTimer;
  bool _holding = false;

  bool get _busy => _dragging || _holding || pinching.value || _fling.isAnimating || _tween.isAnimating;

  bool _disposed = false;

  void _updateMoving() {
    if (_disposed) return;
    if (_busy) {
      _restTimer?.cancel();
      _restTimer = null;
      if (!moving.value) moving.value = true;
    } else if (moving.value && _restTimer == null) {
      // A short wait, so the glide ending and the settling starting do not flicker between.
      _restTimer = Timer(const Duration(milliseconds: 160), () {
        _restTimer = null;
        if (!_busy) {
          moving.value = false;
          stripActive.value = false;
        }
      });
    }
  }

  /// The first month on screen (a month plus a part of one), and pixels per month.
  double start = 0, ppm = 8;

  /// The width of a strip, and the stretch there is something to show (the end is not included).
  double width = 0, minMonth = 0, maxMonth = 1;

  // Once the person has moved or zoomed it, new dates arriving no longer reset the view.
  bool _touched = false;
  bool _dragging = false;

  double get span => width / ppm;

  /// The month under the playhead, with the part of it that has gone by (August 2021 halfway
  /// through is the number of August plus a half).
  double get centreMonth => start + span / 2;
  double get minPpm => width <= 0 ? 1 : math.min(_maxPixelsPerMonth, width / math.max(1, maxMonth - minMonth));

  /// How many years are in view.
  double get years => span / 12;

  void configure({required double width, required double minMonth, required double maxMonth}) {
    // Asked after a frame, by which time the screen can be gone.
    if (_disposed) return;
    if (width == this.width && minMonth == this.minMonth && maxMonth == this.maxMonth) return;
    this.width = width;
    this.minMonth = minMonth;
    this.maxMonth = maxMonth;
    if (!_touched) {
      _openOnLatest();
    } else {
      ppm = ppm.clamp(minPpm, _maxPixelsPerMonth);
      _clampStart();
    }
    _changed();
  }

  // Opens on the last three years, ending today.
  void _openOnLatest() {
    ppm = (width / _openingMonths).clamp(minPpm, _maxPixelsPerMonth);
    start = _highStart;
    _clampStart();
  }

  // The playhead can rest on any month, the first and the last included (so the view may show a
  // little empty space before the first month or after the last).
  double get _lowStart => minMonth + 0.5 - span / 2;
  double get _highStart => maxMonth - 0.5 - span / 2;

  void _clampStart() {
    start = start.clamp(_lowStart, _highStart);
  }

  void _changed() {
    if (_disposed) return;
    final month = (start + span / 2).floor();
    if (month != centre.value) {
      // A light tick on every new year while a finger is moving the years.
      if (_dragging && month ~/ 12 != centre.value ~/ 12) HapticFeedback.selectionClick();
      centre.value = month;
    }
    notifyListeners();
    _updateMoving();
  }

  void _stopMoving() {
    _flingSimulation = null;
    _springTarget = null;
    _fling.stop();
    _tween.stop();
  }

  // ---- finger on the strips ----

  void dragStart({bool fromStrip = false}) {
    if (fromStrip) stripActive.value = true;
    _stopMoving();
    _touched = true;
    _dragging = true;
    _updateMoving();
  }

  void dragBy(double pixels) {
    if (pinching.value || width <= 0) return;
    start -= pixels / ppm;
    _clampStart();
    _changed();
  }

  void dragEnd(double pixelsPerSecond) {
    _dragging = false;
    if (pinching.value || width <= 0) {
      _updateMoving();
      return;
    }
    final velocity = -pixelsPerSecond / ppm; // months per second
    if (pixelsPerSecond.abs() < 150) {
      snapToMonth(velocity: velocity);
      return;
    }
    // It carries on at the speed the finger let go and slows down the way a scroll does; once it is
    // nearly still it settles onto the middle of the next month along.
    _flingDirection = velocity.sign.toInt();
    final simulation = FrictionSimulation(_drag, start, velocity);
    _flingSimulation = simulation;
    _fling.animateWith(simulation);
    _updateMoving();
  }

  // Slower than a scroll's, so a flick glides a good way.
  static const double _drag = 0.12;

  // Below this many pixels a second the glide has done its work and the settling takes over.
  static const double _settleSpeed = 40;

  // The settling: a spring that is neither bouncy nor sluggish, so it takes over from the glide
  // with the speed it had and eases into the middle of the month.
  static const double _springStiffness = 150;
  static final double _springOmega = math.sqrt(_springStiffness);
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: _springStiffness, ratio: 1);

  FrictionSimulation? _flingSimulation; // set while gliding, null while settling
  double? _springTarget;
  int _flingDirection = 0;

  void _onFling() {
    start = _fling.value;
    if (_flingSimulation == null) {
      // Settling: a spring, which comes to rest exactly where it is headed.
      _changed();
      return;
    }
    _clampStart();
    // Stopped at either end: that is where it stays.
    if (start <= _lowStart || start >= _highStart) {
      _fling.stop();
      _flingSimulation = null;
      _changed();
      return;
    }
    final seconds = (_fling.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    final speed = (_flingSimulation?.dx(seconds) ?? 0).abs() * ppm;
    _changed();
    if (seconds > 0.05 && speed < _settleSpeed) {
      snapToMonth(direction: _flingDirection, velocity: _flingSimulation?.dx(seconds) ?? 0);
    }
  }

  void _onFlingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _flingSimulation == null) {
      final target = _springTarget;
      _springTarget = null;
      if (target != null) {
        start = target;
        _clampStart();
        _changed();
      }
    }
    _updateMoving();
  }

  // The first month on screen that puts the playhead in the middle of a month: the nearest to
  // [from], or - going [direction] (1 later, -1 earlier) - the next one along.
  double _snapped(double from, {int direction = 0}) {
    final centre = from + span / 2 - 0.5;
    final month = direction > 0 ? centre.ceil() : (direction < 0 ? centre.floor() : centre.round());
    return month + 0.5 - span / 2;
  }

  /// Settles the playhead onto the middle of a month, smoothly (the nearest, or the next one along
  /// when still going [direction]), carrying on with [velocity] (months a second) it already has.
  void snapToMonth({int direction = 0, double velocity = 0}) {
    if (width <= 0) return;
    _stopMoving();
    var target = _snapped(start, direction: direction);
    // Still going one way: not so close ahead that the spring would have to overshoot and come back.
    final going = direction != 0 ? direction : velocity.sign.toInt();
    if (going != 0) {
      final needed = velocity.abs() / _springOmega * 1.1;
      for (var i = 0; i < 3 && (target - start) * going < needed; i++) {
        target += going;
      }
    }
    target = target.clamp(_lowStart, _highStart);
    if ((target - start).abs() < 0.002) {
      start = target;
      _changed();
      return;
    }
    _flingSimulation = null;
    _springTarget = target;
    _fling.animateWith(SpringSimulation(_spring, start, target, velocity));
    _updateMoving();
  }

  /// A finger is on the overview (or something else that sets the place directly): the years count
  /// as moving until [holdEnd].
  void holdStart() {
    _stopMoving();
    _touched = true;
    _holding = true;
    _updateMoving();
  }

  void holdEnd() {
    _holding = false;
    snapToMonth();
  }

  // ---- two fingers: pinch ----

  final Map<int, Offset> _pointers = {};
  double _stripLeft = 0;
  double _pinchDistance = 1, _pinchPpm = 1, _pinchMonth = 0;

  void pointerDown(int id, Offset position, double stripLeft) {
    _pointers[id] = position;
    _stripLeft = stripLeft;
    if (_pointers.length == 2) {
      _stopMoving();
      _touched = true;
      final points = _pointers.values.toList();
      _pinchDistance = math.max(24, (points[0] - points[1]).distance);
      _pinchPpm = ppm;
      _pinchMonth = start + ((points[0].dx + points[1].dx) / 2 - _stripLeft) / ppm;
      pinching.value = true;
      stripActive.value = true;
      _updateMoving();
    }
  }

  void pointerMove(int id, Offset position) {
    if (!_pointers.containsKey(id)) return;
    _pointers[id] = position;
    if (!pinching.value || _pointers.length < 2 || width <= 0) return;
    final points = _pointers.values.toList();
    final distance = math.max(24, (points[0] - points[1]).distance);
    final focal = (points[0].dx + points[1].dx) / 2 - _stripLeft;
    ppm = (_pinchPpm * distance / _pinchDistance).clamp(minPpm, _maxPixelsPerMonth);
    start = _pinchMonth - focal / ppm;
    _clampStart();
    _changed();
  }

  void pointerUp(int id) {
    _pointers.remove(id);
    if (_pointers.length < 2 && pinching.value) {
      pinching.value = false;
      snapToMonth();
      _updateMoving();
    }
  }

  // ---- buttons and the overview ----

  /// Smoothly shows [years] years (everything, if that is more than there is), around the middle.
  void showYears(double years) {
    if (width <= 0) return;
    _touched = true;
    _stopMoving();
    final targetPpm = (width / (years * 12)).clamp(minPpm, _maxPixelsPerMonth);
    _animateTo(targetPpm, start + span / 2);
  }

  /// Glides to [month] (an absolute month) and rests on the middle of it - from a flag on a line or
  /// the button that goes to the next moment.
  void jumpToMonth(int month) {
    if (width <= 0) return;
    jumps.value++;
    _touched = true;
    _stopMoving();
    _animateTo(ppm, month + 0.5, milliseconds: 520);
  }

  /// Shows everything.
  void showAll() => showYears((maxMonth - minMonth) / 12 + 1);

  /// Moves the middle to [month] (from a tap or drag on the overview).
  void centreOn(double month, {bool animate = false}) {
    if (width <= 0) return;
    _touched = true;
    if (!_holding) _stopMoving();
    if (animate) {
      // Onto the middle of the month tapped, where the playhead rests.
      _animateTo(ppm, month.floor() + 0.5);
    } else {
      start = month - span / 2;
      _clampStart();
      _changed();
    }
  }

  double _fromStart = 0, _fromPpm = 8, _toPpm = 8, _toCentre = 0;

  Curve _curve = Curves.easeInOutCubic;

  void _animateTo(
    double targetPpm,
    double centreMonth, {
    int milliseconds = 380,
    Curve curve = Curves.easeInOutCubic,
  }) {
    _curve = curve;
    _tween.duration = Duration(milliseconds: milliseconds);
    _fromStart = start;
    _fromPpm = ppm;
    _toPpm = targetPpm;
    _toCentre = centreMonth;
    _tween.forward(from: 0);
  }

  void _onTween() {
    final t = _curve.transform(_tween.value);
    ppm = _fromPpm + (_toPpm - _fromPpm) * t;
    // The middle glides from where it was to where it is going.
    final fromCentre = _fromStart + (width / _fromPpm) / 2;
    final centreNow = fromCentre + (_toCentre - fromCentre) * t;
    start = centreNow - span / 2;
    _clampStart();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _restTimer?.cancel();
    _fling.removeStatusListener(_onFlingStatus);
    _fling.dispose();
    _tween.dispose();
    moving.dispose();
    stripActive.dispose();
    jumps.dispose();
    centre.dispose();
    pinching.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------------------------------ header

/// Above the list, while the dates are still being read: how far it is (nothing once done).
class TimelineIntro extends StatelessWidget {
  const TimelineIntro({
    super.key,
    required this.layout,
    required this.data,
    required this.now,
    this.finished = false,
  });

  final TimelineLayout layout;
  final TimelineData data;

  /// Nothing more is coming in (the dates that could not be found out are left).
  final bool finished;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: data.done || finished || data.total == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _Reading(done: data.total - data.pending, total: data.total),
            ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.done, required this.total});

  final int done, total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading dates  ·  ${_grouped(done)} of ${_grouped(total)}',
          style: textTheme.labelMedium?.copyWith(color: AppColors.ink80),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : done / total),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppColors.hairline,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

String _grouped(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Under the list: where the dates come from.
class TimelineFooter extends StatelessWidget {
  const TimelineFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, AppSpacing.xl, _pad, 0),
      child: Text(
        'Dates are when each photo or video was taken.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
    );
  }
}

/// How much of the years to show, as four buttons: everything, five years, one year, three months.
class TimelineZoomBar extends StatelessWidget {
  const TimelineZoomBar({super.key, required this.window});

  final TimelineWindow window;

  // The number of years each button shows (null: everything).
  static const _steps = [
    ('All', null),
    ('5 years', 5.0),
    ('1 year', 1.0),
    ('3 months', 0.25),
  ];

  bool _isActive(double? years) {
    if (window.width <= 0) return false;
    if (years == null) return window.ppm <= window.minPpm * 1.04;
    return (window.years - years).abs() / years < 0.12 && window.ppm > window.minPpm * 1.04;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: window,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [
            for (final (label, years) in _steps)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _isActive(years),
                  label: years == null ? 'Show all years' : 'Show $label',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (years == null) {
                        window.showAll();
                      } else {
                        window.showYears(years);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isActive(years) ? AppColors.canvas : AppColors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: _isActive(years) ? AppColors.hairline : AppColors.transparent),
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: textTheme.bodySmall?.copyWith(
                          color: _isActive(years) ? AppColors.primary : AppColors.ink80,
                          fontWeight: _isActive(years) ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pinned at the top of the list: the overview of all the years, and under it the ruler, with the
/// month under the playhead named at the left.
class TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  TimelineHeaderDelegate({required this.layout, required this.window, this.compact = false});

  final TimelineLayout layout;
  final TimelineWindow window;

  /// The collapsed list has a wider column of names.
  final bool compact;

  static const double _overview = 20;
  static const double _ruler = 30;
  static const double _height = 6 + _overview + 4 + _ruler + 2;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: overlapsContent ? AppColors.hairline : AppColors.transparent)),
      ),
      padding: const EdgeInsets.fromLTRB(_pad, 6, _pad, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Where the playhead is: the month, and how many people have photos in it.
          SizedBox(
            width: _columnWidth(compact),
            height: _overview + 4 + _ruler,
            child: ValueListenableBuilder<int>(
              valueListenable: window.centre,
              builder: (context, month, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      monthLabel(month),
                      maxLines: 1,
                      style: textTheme.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    () {
                      final n = layout.peopleIn(month);
                      return n == 1 ? '1 person' : '$n people';
                    }(),
                    maxLines: 1,
                    style: textTheme.labelSmall?.copyWith(color: AppColors.ink48, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _columnGap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                // The strips are this wide too: the shared window is told, once the frame is done.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  window.configure(
                    width: width,
                    minMonth: layout.startMonth.toDouble(),
                    maxMonth: layout.endMonth + 1.0,
                  );
                });
                return Column(
                  children: [
                    SizedBox(
                      height: _overview,
                      width: width,
                      child: _Overview(layout: layout, window: window),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: _ruler,
                      width: width,
                      child: CustomPaint(
                        painter: _RulerPainter(
                          window: window,
                          style: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                            color: AppColors.ink48,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant TimelineHeaderDelegate old) =>
      !identical(old.layout, layout) || !identical(old.window, window) || old.compact != compact;
}

/// All the years in one thin strip, with a window on the stretch that is on screen. Dragging it
/// (or tapping) moves the view there.
class _Overview extends StatelessWidget {
  const _Overview({required this.layout, required this.window});

  final TimelineLayout layout;
  final TimelineWindow window;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double monthAt(double dx) => layout.startMonth + dx / width * layout.monthCount;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => window.centreOn(monthAt(d.localPosition.dx), animate: true),
          onHorizontalDragStart: (d) {
            window.holdStart();
            window.centreOn(monthAt(d.localPosition.dx));
          },
          onHorizontalDragUpdate: (d) => window.centreOn(monthAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => window.holdEnd(),
          onHorizontalDragCancel: window.holdEnd,
          child: CustomPaint(painter: _OverviewPainter(layout: layout, window: window)),
        );
      },
    );
  }
}

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({required this.layout, required this.window}) : super(repaint: window);

  final TimelineLayout layout;
  final TimelineWindow window;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7));
    canvas.drawRRect(box, Paint()..color = AppColors.parchment);
    final months = layout.monthCount;
    if (months <= 0) return;
    canvas.save();
    canvas.clipRRect(box);
    final cw = size.width / months;
    final bar = Paint();
    for (var i = 0; i < layout.density.length; i++) {
      final v = layout.density[i];
      if (v <= 0) continue;
      final h = 3 + (size.height - 7) * v;
      bar.color = AppColors.primary.withValues(alpha: 0.25 + 0.5 * v);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * cw + 0.3, size.height - 3 - h, math.max(cw - 0.6, 1), h),
          const Radius.circular(1),
        ),
        bar,
      );
    }
    // The part that is on screen.
    if (window.width > 0) {
      final left = ((window.start - layout.startMonth) * cw).clamp(0.0, size.width);
      final right = ((window.start + window.span - layout.startMonth) * cw).clamp(0.0, size.width);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, 1, math.max(right, left + 6), size.height - 1),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = AppColors.primary.withValues(alpha: 0.10));
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.primary,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter old) => !identical(old.layout, layout);
}

const _monthInitials = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The years (and, zoomed in, the months) along the top of the strips.
class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.window, required this.style}) : super(repaint: window);

  final TimelineWindow window;
  final TextStyle style;

  void _text(Canvas canvas, String text, double x, double y, {double? centreIn}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = centreIn == null ? x : x + (centreIn - painter.width) / 2;
    painter.paint(canvas, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ppm = window.ppm;
    if (window.width <= 0 || ppm <= 0) return;
    canvas.clipRect(Offset.zero & size);
    final start = window.start;
    final end = start + size.width / ppm;
    final line = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;

    // Years: every year, or every few when they would run into each other.
    final yearWidth = ppm * 12;
    final step = yearWidth >= 46 ? 1 : (yearWidth >= 23 ? 2 : (yearWidth >= 11 ? 5 : 10));
    final firstYear = start ~/ 12;
    final lastYear = end ~/ 12;
    for (var y = firstYear; y <= lastYear; y++) {
      final x = (y * 12 - start) * ppm;
      final named = y % step == 0;
      if (x >= -1 && x <= size.width) {
        // A named year has its tick up by the label; the others (and, until the months show,
        // every year) a short one at the bottom, clear of the labels.
        if (named) canvas.drawLine(Offset(x, 0), Offset(x, 13), line);
        if (ppm < 11) canvas.drawLine(Offset(x, 22), Offset(x, 30), line);
      }
      if (!named) continue;
      // The year the left edge is in keeps its name there, until the next one pushes it off.
      var labelX = x + 3;
      if (x < 0) {
        final following = ((y + 1) * 12 - start) * ppm;
        labelX = math.min(3.0, following - 33);
      }
      // A year pushed mostly off the left edge is dropped, not shown as a fragment.
      if (labelX > size.width - 26 || labelX < -6) continue;
      _text(canvas, '$y', labelX, -1);
    }

    // Months, once there is room for them.
    if (ppm >= 11) {
      final names = ppm >= 30 ? _monthShort : _monthInitials;
      for (var m = start.floor(); m <= end.ceil(); m++) {
        final x = (m - start) * ppm;
        if (x < -ppm || x > size.width) continue;
        canvas.drawLine(Offset(x, 22), Offset(x, 30), line);
        _text(canvas, names[m % 12], x, 14, centreIn: ppm);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.style != style;
}

// -------------------------------------------------------------------------------------- rows

class TimelineRow extends StatefulWidget {
  const TimelineRow({
    super.key,
    required this.row,
    required this.layout,
    required this.window,
    required this.now,
    required this.datesDone,
    required this.memory,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.compact = false,
    this.preview,
  });

  /// The collapsed list: names and thin lines only, no faces.
  final bool compact;

  /// Where the person's photo of the month under the playhead comes from (their face is shown
  /// without it).
  final TimelinePreview? preview;

  final TimelineRowData row;
  final TimelineLayout layout;
  final TimelineWindow window;
  final DateTime now;

  /// Whether every date has been looked up (before that, what is missing is not "undated" yet).
  final bool datesDone;
  final TimelineMemory memory;

  /// Place in the list: the first rows come in one after another.
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  State<TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<TimelineRow> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _develop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void initState() {
    super.initState();
    final id = widget.row.person.id;
    if (widget.memory.entered.contains(id)) {
      _enter.value = 1;
    } else {
      widget.memory.entered.add(id);
      Future<void>.delayed(Duration(milliseconds: widget.index < 8 ? widget.index * 70 : 0), () {
        if (mounted) _enter.forward();
      });
    }
    if (widget.memory.developed.contains(id)) {
      _develop.value = 1;
    } else {
      _developWhenReady();
    }
  }

  @override
  void didUpdateWidget(covariant TimelineRow old) {
    super.didUpdateWidget(old);
    if (!_develop.isAnimating && _develop.value == 0) _developWhenReady();
  }

  // The strip develops once there is something on it, a moment after the row has come in.
  void _developWhenReady() {
    final id = widget.row.person.id;
    if (!widget.row.hasDates || widget.memory.developed.contains(id)) return;
    widget.memory.developed.add(id);
    final delay = Duration(milliseconds: 260 + (widget.index < 8 ? widget.index * 70 : 0));
    Future<void>.delayed(delay, () {
      if (mounted) _develop.forward();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _develop.dispose();
    _press.dispose();
    super.dispose();
  }

  // Leans a little, the same way every time (the way their tile on the grid does).
  double get _lean {
    final h = widget.row.person.id * 2654435761 & 0x7fffffff;
    var lean = ((h % 7) - 3) * 1.6;
    if (lean.abs() < 1.6) lean = h.isEven ? 2.2 : -2.2;
    return lean;
  }

  // The collapsed row: the name (dimmed while the playhead is on a month they are not in) and
  // one line along the years.
  Widget _compactContent(BuildContext context, Color tone) {
    final textTheme = Theme.of(context).textTheme;
    final row = widget.row;
    final person = row.person;
    final named = person.name != null;
    return Row(
      children: [
        SizedBox(
          width: _compactColumn,
          child: ValueListenableBuilder<int>(
            valueListenable: widget.window.centre,
            builder: (context, month, child) => AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: !row.hasDates || row.countAt(month - widget.layout.startMonth) > 0 ? 1 : 0.38,
              child: child,
            ),
            child: Row(
              children: [
                if (widget.selecting) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected ? AppColors.primary : AppColors.canvas,
                      border: Border.all(
                        color: widget.selected ? AppColors.primary : AppColors.hairline,
                        width: 1.5,
                      ),
                    ),
                    child: widget.selected
                        ? const Icon(Icons.check_rounded, size: 11, color: AppColors.onPrimary)
                        : null,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    named ? person.name! : 'Add name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: named ? AppColors.ink : AppColors.ink48,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: _columnGap),
        Expanded(
          child: _Strip(
            row: row,
            layout: widget.layout,
            window: widget.window,
            tone: tone,
            develop: _develop,
            onTap: widget.onTap,
            compact: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final row = widget.row;
    final person = row.person;
    final tone = _toneFor(person.id);
    final nowMonth = monthIndex(widget.now);
    final named = person.name != null;
    final caption = row.hasDates
        ? row.rangeLabel(nowMonth)
        : (widget.datesDone ? 'No dates found' : 'Looking up dates...');

    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: fade,
      builder: (context, child) => Opacity(
        opacity: fade.value,
        child: Transform.translate(offset: Offset(0, (1 - fade.value) * 14), child: child),
      ),
      child: Semantics(
        button: true,
        label: '${named ? person.name : 'Unnamed person'}, ${row.rangeLabel(nowMonth)}, ${row.photoCount} photos',
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: _pad - AppSpacing.sm),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: widget.compact ? AppSpacing.xs + 1 : AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: widget.selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.transparent,
            ),
            child: widget.compact ? _compactContent(context, tone) : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Their face and name stay put; they dim while the playhead is on a month they
                // are not in.
                SizedBox(
                  width: _leftColumn,
                  child: ValueListenableBuilder<int>(
                    valueListenable: widget.window.centre,
                    builder: (context, month, child) => AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: !row.hasDates || row.countAt(month - widget.layout.startMonth) > 0 ? 1 : 0.38,
                      child: child,
                    ),
                    child: Column(
                      children: [
                        _Avatar(
                          personId: person.id,
                          preview: widget.preview,
                          faceId: person.coverFaceId,
                          lean: _lean,
                          press: _press,
                          selecting: widget.selecting,
                          selected: widget.selected,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          named ? person.name! : 'Add name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
                            color: named ? AppColors.ink : AppColors.ink48,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: _columnGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Strip(
                        row: row,
                        layout: widget.layout,
                        window: widget.window,
                        tone: tone,
                        develop: _develop,
                        onTap: widget.onTap,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs + 1),
                        child: ValueListenableBuilder<int>(
                          valueListenable: widget.window.centre,
                          builder: (context, month, _) {
                            // The range ("Since 2019") - or, while the playhead is on a month they
                            // are in, what they have in that month (and no room for anything else).
                            final count = row.countAt(month - widget.layout.startMonth);
                            final moments = [
                              for (final m in row.milestones)
                                if (m.month == month) m,
                            ];
                            final moment = moments.isEmpty ? null : moments.first;
                            final here = count > 0 || moment != null;
                            final text = moment != null
                                ? moment.long
                                : (count > 0
                                      ? '${count == 1 ? '1 photo' : '$count photos'} in ${monthLabel(month)}'
                                      : caption);
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 120),
                                    layoutBuilder: switcherStack(alignment: Alignment.centerLeft),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          if (moment != null)
                                            WidgetSpan(
                                              alignment: PlaceholderAlignment.middle,
                                              child: Padding(
                                                padding: const EdgeInsets.only(right: 5),
                                                child: Icon(_momentIcon(moment.kind), size: 14, color: tone),
                                              ),
                                            ),
                                          TextSpan(text: text),
                                        ],
                                      ),
                                      key: ValueKey(text),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: here ? tone : AppColors.ink48,
                                        fontWeight: here ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                                if (widget.datesDone && row.undated > 0 && !here) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      row.undated == 1 ? '1 without a date' : '${row.undated} without a date',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: AppColors.ink48,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One person's strip: moved sideways by a finger and zoomed by a pinch, both through the shared
/// window.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.row,
    required this.layout,
    required this.window,
    required this.tone,
    required this.develop,
    required this.onTap,
    this.compact = false,
  });

  final TimelineRowData row;
  final TimelineLayout layout;
  final TimelineWindow window;
  final Color tone;
  final Animation<double> develop;
  final bool compact;

  /// A tap on the row (it opens the person).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (r) => r.onTap = onTap,
        ),
        // Only a sideways drag, so scrolling the list and tapping the row work as ever.
        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
          (r) => r
            ..onStart = ((_) => window.dragStart(fromStrip: true))
            ..onUpdate = ((d) => window.dragBy(d.delta.dx))
            ..onEnd = ((d) => window.dragEnd(d.velocity.pixelsPerSecond.dx))
            ..onCancel = (() => window.dragEnd(0)),
        ),
      },
      child: Listener(
        // Two fingers anywhere on the strips are a pinch (followed here, not through the gesture
        // arena, so the list can be told to stand still while it lasts).
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final box = context.findRenderObject() as RenderBox?;
          window.pointerDown(e.pointer, e.position, box == null ? 0 : box.localToGlobal(Offset.zero).dx);
        },
        onPointerMove: (e) => window.pointerMove(e.pointer, e.position),
        onPointerUp: (e) => window.pointerUp(e.pointer),
        onPointerCancel: (e) => window.pointerUp(e.pointer),
        child: SizedBox(
          height: compact ? _compactStripHeight : _stripHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _StripPainter(
              row: row,
              base: layout.startMonth,
              window: window,
              color: tone,
              develop: develop,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }
}

/// Their face on a small white print, leaning like their tile on the grid, with a tick when chosen.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.personId,
    required this.preview,
    required this.faceId,
    required this.lean,
    required this.press,
    required this.selecting,
    required this.selected,
  });

  final int personId;
  final TimelinePreview? preview;
  final int faceId;
  final double lean;
  final Animation<double> press;
  final bool selecting, selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatar,
      height: _avatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: press,
              builder: (context, child) => Transform.rotate(
                angle: lean * math.pi / 180 * (1 - 0.7 * press.value),
                child: child,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(color: AppColors.shadow.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  // Their face - or, once the playhead has settled on a month they are in, their own
                  // photo of that month, which fades in over it and back out when the playhead moves.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: SizedBox(
                      width: _avatar - 5,
                      height: _avatar - 5,
                      child: preview == null
                          ? FaceAvatar(faceId: faceId, size: _avatar - 5, square: true, radius: 8.5)
                          : ListenableBuilder(
                              listenable: preview!,
                              builder: (context, _) {
                                final photo = preview!.photoFor(personId);
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 380),
                                  switchInCurve: Curves.easeOutCubic,
                                  layoutBuilder: switcherStack(fit: StackFit.expand),
                                  child: photo == null
                                      ? FaceAvatar(
                                          key: const ValueKey('face'),
                                          faceId: faceId,
                                          size: _avatar - 5,
                                          square: true,
                                          radius: 0,
                                        )
                                      : PreviewImage(
                                          key: ValueKey(photo.cacheKey),
                                          photo: photo,
                                          loader: preview!.loader,
                                          // Faces sit in the upper part of a photo.
                                          alignment: const Alignment(0, -0.35),
                                        ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selecting)
            Positioned(
              right: -5,
              bottom: -5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : AppColors.canvas,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.hairline, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 13, color: AppColors.onPrimary) : null,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------- the strip

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.row,
    required this.base,
    required this.window,
    required this.color,
    required this.develop,
    this.compact = false,
  }) : _runs = compact ? timelineRuns(row.offsets) : const [],
       super(repaint: Listenable.merge([window, develop]));

  final bool compact;
  final List<(int, int)> _runs;

  final TimelineRowData row;

  /// The month the row's offsets count from.
  final int base;
  final TimelineWindow window;
  final Color color;

  /// 0 = nothing developed yet, 1 = the whole strip.
  final Animation<double> develop;

  static const double _inset = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final track = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9));
    canvas.drawRRect(track, Paint()..color = AppColors.parchment);
    final ppm = window.ppm;
    if (window.width <= 0 || ppm <= 0) return;

    canvas.save();
    canvas.clipRRect(track);
    final start = window.start;
    final end = start + w / ppm;
    final reveal = Curves.easeOutCubic.transform(develop.value);
    if (compact) {
      _paintCompact(canvas, size, reveal);
      canvas.restore();
      return;
    }

    // A faint line at every new year, like the edge of a frame.
    final tick = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var m = (start / 12).ceil() * 12; m <= end; m += 12) {
      final x = (m - start) * ppm;
      canvas.drawLine(Offset(x, _inset), Offset(x, h - _inset - 1), tick);
    }

    // The month under the playhead: a soft column behind its cell.
    final centreMonth = (start + w / ppm / 2).floor();
    final centreX = (centreMonth - start) * ppm;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(centreX - 1, 2, math.max(ppm, 3) + 2, h - 4), const Radius.circular(5)),
      Paint()..color = color.withValues(alpha: 0.16),
    );

    // Only the months in view are drawn (the offsets are in order).
    final maxCount = row.maxCount;
    final alone = row.offsets.length == 1;
    var i = _firstAtOrAfter(row.offsets, (start - base).floor());
    for (; i < row.offsets.length; i++) {
      final month = base + row.offsets[i];
      final x = (month - start) * ppm;
      if (x > w) break;
      // Developing sweeps from the left with a soft edge.
      final shown = ((reveal * 1.25 - x / w) * 5).clamp(0.0, 1.0);
      if (shown <= 0) continue;
      // The more photos, the darker and the taller (never less than a third of the strip).
      final t = maxCount <= 1 ? 1.0 : math.sqrt(row.counts[i] / maxCount);
      final cellW = alone ? math.max(7.0, ppm - 1) : math.max(ppm - math.min(1.0, ppm * 0.12), 2.4);
      final left = x + (ppm - cellW) / 2;
      final full = h - _inset * 2;
      final height = full * (0.38 + 0.62 * t) * Curves.easeOutBack.transform(shown).clamp(0.0, 1.2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, h - _inset - height, cellW, height),
        Radius.circular(math.min(cellW / 2, ppm > 20 ? 5 : 3)),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: (0.3 + 0.7 * t) * shown));
      if (month == centreMonth) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = AppColors.canvas,
        );
      }
    }

    // The playhead.
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.85)
        ..strokeWidth = 1.5,
    );

    canvas.restore();
  }

  // The collapsed strip: a thin rounded line for every stretch of months they are in, broken
  // where they are not. No heights, no counts - just when.
  void _paintCompact(Canvas canvas, Size size, double reveal) {
    final w = size.width, h = size.height;
    final ppm = window.ppm;
    final start = window.start;
    final thickness = h * 0.46;
    final y = (h - thickness) / 2;

    // Faint year lines.
    final tick = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var m = (start / 12).ceil() * 12; m <= start + w / ppm; m += 12) {
      final x = (m - start) * ppm;
      canvas.drawLine(Offset(x, 3), Offset(x, h - 3), tick);
    }

    // The line develops from the left, like the strips of the full list.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal * 1.1, h));
    final paint = Paint()..color = color.withValues(alpha: 0.9);
    for (final (first, last) in _runs) {
      final x1 = (base + first - start) * ppm;
      final x2 = (base + last + 1 - start) * ppm;
      if (x2 < 0 || x1 > w) continue;
      var left = x1 + 0.5, right = x2 - 0.5;
      // A single month is a dot, not a hair.
      if (right - left < thickness) {
        final mid = (left + right) / 2;
        left = mid - thickness / 2;
        right = mid + thickness / 2;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, y, right, y + thickness), Radius.circular(thickness / 2)),
        paint,
      );
    }
    canvas.restore();

    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.85)
        ..strokeWidth = 1.5,
    );
  }

  // The first place in [sorted] holding a value of at least [value].
  static int _firstAtOrAfter(List<int> sorted, int value) {
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) =>
      old.color != color ||
      old.base != base ||
      old.compact != compact ||
      !identical(old.row, row) ||
      !identical(old.window, window);
}

// ------------------------------------------------------------------------------------ order

/// The people for the timeline, after the search and in the order chosen.
enum TimelineSort { earliest, recent, mostPhotos, az }

String timelineSortLabel(TimelineSort sort) {
  switch (sort) {
    case TimelineSort.earliest:
      return 'Earliest first';
    case TimelineSort.recent:
      return 'Seen most recently';
    case TimelineSort.mostPhotos:
      return 'Most photos';
    case TimelineSort.az:
      return 'A to Z';
  }
}

List<TimelineRowData> sortTimelineRows(List<TimelineRowData> rows, TimelineSort sort, {required bool datesDone}) {
  final list = [...rows];
  int byPhotos(TimelineRowData a, TimelineRowData b) => b.photoCount.compareTo(a.photoCount);
  // Until every date is in, the order would keep changing under the finger: most photos first.
  if (!datesDone && (sort == TimelineSort.earliest || sort == TimelineSort.recent)) {
    return list..sort(byPhotos);
  }
  switch (sort) {
    case TimelineSort.earliest:
      list.sort((a, b) {
        if (a.hasDates != b.hasDates) return a.hasDates ? -1 : 1;
        if (!a.hasDates) return byPhotos(a, b);
        final c = a.firstMonth!.compareTo(b.firstMonth!);
        return c != 0 ? c : byPhotos(a, b);
      });
    case TimelineSort.recent:
      list.sort((a, b) {
        if (a.hasDates != b.hasDates) return a.hasDates ? -1 : 1;
        if (!a.hasDates) return byPhotos(a, b);
        final c = b.lastMonth!.compareTo(a.lastMonth!);
        return c != 0 ? c : byPhotos(a, b);
      });
    case TimelineSort.mostPhotos:
      list.sort(byPhotos);
    case TimelineSort.az:
      list.sort((a, b) {
        final an = a.person.name?.toLowerCase(), bn = b.person.name?.toLowerCase();
        if ((an == null) != (bn == null)) return an == null ? 1 : -1;
        if (an == null) return byPhotos(a, b);
        return an.compareTo(bn!);
      });
  }
  return list;
}

/// For the People tab: the people in [shown] (a search applied to everyone listed, so the axis does
/// not change with it) as rows, in the order [sort] gives.
List<TimelineRowData> timelineRowsFor(
  TimelineLayout layout,
  List<Person> shown,
  TimelineSort sort, {
  required bool datesDone,
}) {
  final ids = {for (final p in shown) p.id};
  return sortTimelineRows(
    [
      for (final row in layout.rows)
        if (ids.contains(row.person.id)) row,
    ],
    sort,
    datesDone: datesDone,
  );
}
