import 'dart:math' as math;

/// The splash animation as plain maths: one clock, in milliseconds, and everything on screen is a function of it.
/// Nothing here draws or touches Flutter, so it can be tested without a screen. The painter in splash_painter.dart
/// reads these values.
///
/// The icon is drawn on its own 108 unit canvas, of which the middle 72 units (18 to 90) show. Sequence:
/// - 0 to 300: the icon fades in, as the old look (the split is at the left edge), on a pale sky with drifting clouds and fine hill lines.
/// - 300: it waits here, if it must, for the app to be ready (see [holdMs]).
/// - 300 to 900: the slider sweeps across to the new look.
/// - 900 to 2200: a big lens grows out of the tile and over its edge (the tile has faded away by 1100). Through it the app shows, first the top of
///   the screen, then the middle; then the lens widens until it is the whole screen.
class SplashTimeline {
  const SplashTimeline._();

  /// The length of the sequence above, in its own milliseconds.
  static const double totalMs = 2200;

  /// How much slower than those milliseconds it really plays: 1.3 makes the 2.2 s sequence take about 2.9 s.
  static const double slowdown = 1.3;

  /// Real time for [designMs] of the sequence.
  static Duration real(double designMs) => Duration(milliseconds: (designMs * slowdown).round());

  /// Where the animation waits for the app: the icon has just appeared. The app is let build its first screen
  /// here, while the sky keeps drifting, and when it is quiet the sweep and the lens play through without stopping.
  static const double holdMs = 300;

  /// The finished icon, after the sweep: what is shown still when the phone asks for no motion.
  static const double restMs = 900;

  /// When the big lens comes out of the tile.
  static const double lensStartMs = 900;

  /// From here on the sky behind the tile is one fixed picture, drawn once and reused: the tile
  /// is gone, and the colour stops drifting.
  static const double coverBakedMs = 1100;

  /// The slider's resting place in the new icon, on the 108 unit canvas.
  static const double split = 60.8;

  /// Where the sweep starts (the left edge of the visible window).
  static const double splitStart = 18;
}

double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double lerp(double a, double b, double t) => a + (b - a) * t;

/// 0 before [a], 1 after [b], a straight ramp between.
double seg(double t, double a, double b) => clamp01((t - a) / (b - a));

class Ease {
  const Ease._();

  static double out(double t) => 1 - math.pow(1 - t, 3).toDouble();

  /// A gentle start and stop: the fastest it goes is only about 1.6 times its average speed.
  static double sine(double t) => 0.5 - 0.5 * math.cos(math.pi * t);

  static double cubicIn(double t) => t * t * t;

  static double inOut(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

  /// Overshoots a little and settles.
  static double back(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}

typedef Pt = ({double x, double y});

/// Everything about one moment of the animation that the painter needs, worked out once per frame.
class SplashFrame {
  SplashFrame(this.t)
    : pin = Ease.out(seg(t, 0, 300)),
      splitX = lerp(SplashTimeline.splitStart, SplashTimeline.split, Ease.inOut(seg(t, 300, 900))),
      lineOpacity = seg(t, SplashTimeline.holdMs, SplashTimeline.holdMs + 120),
      tileOut = seg(t, 950, 1100),
      holeOpen = seg(t, SplashTimeline.coverBakedMs, SplashTimeline.coverBakedMs + 100),
      lensGrow = Ease.back(seg(t, 900, 1200)),
      trip = Ease.sine(seg(t, 1100, 2000)),
      widen = Ease.cubicIn(seg(t, 1700, 2200)),
      lensOpacity = seg(t, 900, 1000) * (1 - seg(t, 1950, 2150));

  final double t;

  /// 0 to 1: the icon appearing (scale 0.9 to 1 and fade).
  final double pin;

  /// Where the slider is, on the 108 unit canvas, and how visible its line and handle are. They show only once the
  /// sweep starts (at the hold point), not while the animation waits for the app.
  final double splitX;
  final double lineOpacity;

  /// 0 is the whole tile, 1 is the tile gone (the big lens has come out of it).
  final double tileOut;

  /// 0 to 1: the round hole in the cover (what the lens looks through) opening to the size of the lens.
  final double holeOpen;

  /// The big lens: 0 before it comes out of the tile, 1 once it has grown to its size; it overshoots a little.
  final double lensGrow;

  /// How far along its path over the screen the lens is: 0 at the tile, 1 in the middle, where it widens from.
  final double trip;

  /// How far the lens has widened towards the whole screen.
  final double widen;

  /// The lens's ring and handle: there once it is out, gone as it fills the screen.
  final double lensOpacity;

  /// The icon as a whole.
  double get iconScale => lerp(0.9, 1, pin);
  double get iconOpacity => pin * (1 - tileOut);
}

/// A smooth path through the points [pts] (a Catmull-Rom curve, at least two of them), [s] from 0 at the first to 1
/// at the last, at about an even speed along it however far apart the points are. The lens goes over the top of the
/// screen and then the middle without stopping at either.
Pt tripAt(double s, List<Pt> pts) {
  assert(pts.length >= 2);
  double gap(Pt p, Pt q) => math.sqrt(math.pow(q.x - p.x, 2) + math.pow(q.y - p.y, 2));
  final gaps = [for (var i = 0; i < pts.length - 1; i++) gap(pts[i], pts[i + 1])];
  final total = gaps.fold(0.0, (a, b) => a + b);
  if (total == 0) return pts.first;
  var left = clamp01(s) * total;
  var k = 0;
  while (k < gaps.length - 1 && left > gaps[k]) {
    left -= gaps[k];
    k++;
  }
  final u = gaps[k] == 0 ? 0.0 : clamp01(left / gaps[k]);
  // The first and last points are doubled, so the curve starts and ends where it should.
  final ext = [pts.first, ...pts, pts.last];
  double axis(double Function(Pt) v) {
    final p0 = v(ext[k]), p1 = v(ext[k + 1]), p2 = v(ext[k + 2]), p3 = v(ext[k + 3]);
    return 0.5 *
        (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u);
  }

  return (x: axis((p) => p.x), y: axis((p) => p.y));
}
