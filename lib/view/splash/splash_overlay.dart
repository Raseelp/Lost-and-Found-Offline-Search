import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/controllers/tour_controller.dart';
import 'package:lost_and_found/utils/motion.dart';
import 'package:lost_and_found/view/splash/splash_painter.dart';
import 'package:lost_and_found/view/splash/splash_timeline.dart';

/// Whether the app may build its screens yet. The splash keeps it back until the icon is whole, so the heavy work of
/// building the first screen (and the loading that starts with it) does not land in the middle of the animation and
/// make it stutter. Until then the app shows plain white under the splash.
class SplashGate {
  const SplashGate._();

  static final ValueNotifier<bool> released = ValueNotifier<bool>(false);

  static void release() => released.value = true;
}

/// The clock the waiting for the app measures by, in milliseconds. A test replaces it with its own.
@visibleForTesting
int Function() splashNowMs = () => DateTime.now().millisecondsSinceEpoch;

/// Puts the splash animation over the app while it starts. The app is built underneath from the first frame, so
/// it is ready the moment the white clears. Mounted once, around the navigator, in main.dart.
class SplashHost extends StatefulWidget {
  const SplashHost({super.key, required this.child});

  final Widget child;

  @override
  State<SplashHost> createState() => _SplashHostState();
}

class _SplashHostState extends State<SplashHost> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done) _SplashLayer(onDone: () => setState(() => _done = true)),
      ],
    );
  }
}

/// Finds out when the app has what it needs to show a screen, which is what the animation waits for.
class _SplashLayer extends StatelessWidget {
  const _SplashLayer({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<TourController>(
      builder: (tour) => GetBuilder<NativeController>(
        builder: (native) => SplashStage(ready: tour.loaded && !native.isCheckingModels, onDone: onDone),
      ),
    );
  }
}

/// The animation itself, with its clocks and its waiting for the app. Public only so that a test can run it.
@visibleForTesting
class SplashStage extends StatefulWidget {
  const SplashStage({super.key, required this.ready, required this.onDone});

  /// The app can show its first screen.
  final bool ready;
  final VoidCallback onDone;

  @override
  State<SplashStage> createState() => _SplashStageState();
}

/// Runs the splash: waits for the app, plays the animation and takes itself away.
class _SplashStageState extends State<SplashStage> with TickerProviderStateMixin {
  /// The longest the animation waits at the start for the app before the app shows through anyway, as it has its own
  /// loading screen.
  static const Duration _patience = Duration(seconds: 6);

  /// The least and the most time the app is left to build its first screen while the icon sits. See
  /// [_waitForQuiet].
  static const Duration _settle = Duration(milliseconds: 350);
  static const Duration _settleMost = Duration(milliseconds: 1500);

  /// With "Remove animations" the finished icon is shown still for this long.
  static const Duration _stillHold = Duration(milliseconds: 500);

  /// Uses [AnimationBehavior.preserve], so the phone's own animation scale cannot speed the clock up or skip it.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: SplashTimeline.real(SplashTimeline.totalMs),
    animationBehavior: AnimationBehavior.preserve,
  );
  /// Real time since the start, for the sky, which keeps drifting while [_clock] waits for the app.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600000),
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    animationBehavior: AnimationBehavior.preserve,
  );
  late final Animation<double> _visible = ReverseAnimation(_leave);

  SplashPainter? _painter;

  Timer? _timer;
  bool _started = false;
  bool _atHold = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    SplashPainter.warmUp();
  }

  /// Starts the animation, or with "Remove animations" sets the finished icon.
  ///
  /// The gate is released after the first frame, because this runs while the tree is being built.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (calm(context)) {
      _clock.value = SplashTimeline.restMs / SplashTimeline.totalMs;
      _ambient.value = 1000 / SplashPainter.ambientSpanMs;
      WidgetsBinding.instance.addPostFrameCallback((_) => SplashGate.release());
      _timer = Timer(_stillHold, _leaveWhenReady);
    } else {
      _ambient.forward();
      _clock
          .animateTo(
            SplashTimeline.holdMs / SplashTimeline.totalMs,
            duration: SplashTimeline.real(SplashTimeline.holdMs),
            curve: Curves.linear,
          )
          .whenComplete(_reachedHold);
    }
  }

  @override
  void didUpdateWidget(SplashStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) {
      if (_atHold) {
        _timer?.cancel();
        _waitForQuiet();
      }
      if (_leaving) _fadeOut();
    }
  }

  void _reachedHold() {
    if (!mounted || _leaving) return;
    _atHold = true;
    SplashGate.release();
    if (widget.ready) {
      _waitForQuiet();
    } else {
      _timer = Timer(_patience, _playRest);
    }
  }

  /// Plays the rest once the app has had [_settle] and its thread has been quiet for about 130 ms, or after
  /// [_settleMost] whatever it is doing. The quiet is found by how late a short timer fires, so the lens does not
  /// share the thread with the app starting.
  void _waitForQuiet() {
    final started = splashNowMs();
    var last = started;
    var quiet = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final now = splashNowMs();
      final lag = now - last - 16;
      last = now;
      quiet = lag < 6 ? quiet + 1 : 0;
      final waited = now - started;
      if ((waited >= _settle.inMilliseconds && quiet >= 8) || waited >= _settleMost.inMilliseconds) {
        timer.cancel();
        _playRest();
      }
    });
  }

  /// Plays the animation from the hold to the end. The picture the cover is drawn from later is made first, while
  /// the sweep is still slow.
  void _playRest() {
    if (!mounted || _leaving || !_atHold) return;
    _atHold = false;
    _timer?.cancel();
    _painter?.prepare(MediaQuery.sizeOf(context));
    _clock
        .animateTo(1, duration: SplashTimeline.real(SplashTimeline.totalMs - SplashTimeline.holdMs), curve: Curves.linear)
        .whenComplete(() {
          if (mounted && !_leaving) _finish();
        });
  }

  /// Tapped, or no motion wanted: stop where it is and go (fading out, or with no motion at once), as soon as the
  /// app is ready.
  void _leaveWhenReady() {
    if (!mounted || _leaving) return;
    _leaving = true;
    _atHold = false;
    SplashGate.release();
    _clock.stop();
    _timer?.cancel();
    if (widget.ready) {
      _fadeOut();
    } else {
      _timer = Timer(_patience, _fadeOut);
    }
  }

  /// Fades the splash out. With "Remove animations" it is taken away at once and nothing fades.
  void _fadeOut() {
    if (!mounted || _leave.isAnimating || _leave.isCompleted) return;
    _timer?.cancel();
    if (calm(context)) {
      _finish();
      return;
    }
    _leave.forward().whenComplete(() {
      if (mounted) _finish();
    });
  }

  void _finish() {
    _ambient.stop();
    SplashGate.release();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    _ambient.dispose();
    _leave.dispose();
    _painter?.dispose();
    super.dispose();
  }

  /// The splash is a picture to look at, so it is kept out of the screen reader's way. A tap on it leaves early.
  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leaveWhenReady,
        child: FadeTransition(
          opacity: _visible,
          child: RepaintBoundary(
            child: CustomPaint(painter: _painter ??= SplashPainter(_clock, ambient: _ambient, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)), size: Size.infinite, isComplex: true, willChange: true),
          ),
        ),
      ),
    );
  }
}
