import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/people_palette.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_preview.dart';
import 'package:lost_and_found/features/people/models/person.dart';
part 'people_timeline/shared.dart';
part 'people_timeline/timeline_header_delegate.dart';
part 'people_timeline/avatar.dart';
part 'people_timeline/strip.dart';
part 'people_timeline/strip_painter.dart';
part 'people_timeline/timeline_row.dart';
part 'people_timeline/timeline_intro.dart';
part 'people_timeline/timeline_zoom_bar.dart';
part 'people_timeline/overview_painter.dart';
part 'people_timeline/ruler_painter.dart';
part 'people_timeline/timeline_rows_for.dart';

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

  /// True while anything moves the years (a finger, a glide, a settling, a zoom) and for a moment after: false only
  /// once it has come to rest on the middle of a month.
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

  /// Once the person has moved or zoomed it, new dates arriving no longer reset the view.
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

  /// Opens on the last three years, ending today.
  void _openOnLatest() {
    ppm = (width / _openingMonths).clamp(minPpm, _maxPixelsPerMonth);
    start = _highStart;
    _clampStart();
  }

  /// The playhead can rest on any month, the first and the last included (so the view may show a
  /// little empty space before the first month or after the last).
  double get _lowStart => minMonth + 0.5 - span / 2;
  double get _highStart => maxMonth - 0.5 - span / 2;

  void _clampStart() {
    start = start.clamp(_lowStart, _highStart);
  }

  void _changed() {
    if (_disposed) return;
    final month = (start + span / 2).floor();
    if (month != centre.value) {
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
    final velocity = -pixelsPerSecond / ppm;
    if (pixelsPerSecond.abs() < 150) {
      snapToMonth(velocity: velocity);
      return;
    }
    _flingDirection = velocity.sign.toInt();
    final simulation = FrictionSimulation(_drag, start, velocity);
    _flingSimulation = simulation;
    _fling.animateWith(simulation);
    _updateMoving();
  }

  /// Slower than a scroll's, so a flick glides a good way.
  static const double _drag = 0.12;

  /// Below this many pixels a second the glide has done its work and the settling takes over.
  static const double _settleSpeed = 40;

  /// The settling: a spring that is neither bouncy nor sluggish, so it takes over from the glide
  /// with the speed it had and eases into the middle of the month.
  static const double _springStiffness = 150;
  static final double _springOmega = math.sqrt(_springStiffness);
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: _springStiffness, ratio: 1);

  /// Set while gliding, null while settling.
  FrictionSimulation? _flingSimulation;
  double? _springTarget;
  int _flingDirection = 0;

  void _onFling() {
    start = _fling.value;
    if (_flingSimulation == null) {
      _changed();
      return;
    }
    _clampStart();
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

  /// The first month on screen that puts the playhead in the middle of a month: the nearest to [from], or, going
  /// [direction] (1 later, -1 earlier), the next one along.
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

  /// Smoothly shows [years] years (everything, if that is more than there is), around the middle.
  void showYears(double years) {
    if (width <= 0) return;
    _touched = true;
    _stopMoving();
    final targetPpm = (width / (years * 12)).clamp(minPpm, _maxPixelsPerMonth);
    _animateTo(targetPpm, start + span / 2);
  }

  /// Glides to [month] (an absolute month) and rests on the middle of it, from a flag on a line or the button that
  /// goes to the next moment.
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

/// How close the zoom can go: this many pixels to a month (about a month a thumb wide).
const double _maxPixelsPerMonth = 48;

/// How many months show on opening (the last three years).
const double _openingMonths = 36;
