import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/home/features/splash/view/splash_timeline.dart';

void main() {
  const path = [(x: 176.0, y: 372.0), (x: 118.0, y: 200.0), (x: 252.0, y: 440.0)];

  test('every value stays a real number inside its range, before, during and after the sequence', () {
    for (var t = -50.0; t <= SplashTimeline.totalMs + 200; t += 1) {
      final f = SplashFrame(t);
      for (final v in [f.pin, f.splitX, f.lineOpacity, f.tileOut, f.lensGrow, f.trip, f.widen, f.lensOpacity, f.holeOpen, f.iconScale, f.iconOpacity]) {
        expect(v.isFinite, isTrue, reason: 't=$t');
      }
      expect(f.lineOpacity, inInclusiveRange(0, 1));
      expect(f.tileOut, inInclusiveRange(0, 1));
      expect(f.lensOpacity, inInclusiveRange(0, 1));
      expect(f.holeOpen, inInclusiveRange(0, 1));
      expect(f.trip, inInclusiveRange(0, 1));
      expect(f.lensGrow, inInclusiveRange(-0.001, 1.2));
    }
  });

  test('the slider and its line stay hidden while the animation waits, and show once the sweep starts', () {
    expect(SplashFrame(0).lineOpacity, 0);
    expect(SplashFrame(SplashTimeline.holdMs).lineOpacity, 0);
    expect(SplashFrame(SplashTimeline.holdMs + 120).lineOpacity, 1);
  });

  test('the slider starts at the left edge and ends at its place in the new icon', () {
    expect(SplashFrame(SplashTimeline.holdMs).splitX, SplashTimeline.splitStart);
    expect(SplashFrame(900).splitX, closeTo(SplashTimeline.split, 1e-9));
  });

  test('the tile is gone before the hole opens, and the hole opens exactly when the cover is switched to its picture', () {
    final at = SplashFrame(SplashTimeline.coverBakedMs);
    expect(at.iconOpacity, 0);
    expect(at.holeOpen, 0);
    expect(SplashFrame(SplashTimeline.coverBakedMs + 100).holeOpen, 1);
  });

  test('the lens ring is gone by the end, and the lens has taken its full size', () {
    expect(SplashFrame(SplashTimeline.totalMs).lensOpacity, 0);
    expect(SplashFrame(SplashTimeline.totalMs).widen, 1);
    expect(SplashFrame(1200).lensGrow, closeTo(1, 1e-9));
  });

  test('the icon fades in from small and transparent to full size', () {
    expect(SplashFrame(0).iconOpacity, 0);
    expect(SplashFrame(0).iconScale, closeTo(0.9, 1e-9));
    expect(SplashFrame(300).iconScale, 1);
  });

  test('real time is the design time stretched by the slowdown', () {
    expect(SplashTimeline.real(1000).inMilliseconds, (1000 * SplashTimeline.slowdown).round());
  });

  group('the path of the lens', () {
    test('starts and ends on its first and last point', () {
      expect(tripAt(0, path), path.first);
      final end = tripAt(1, path);
      expect(end.x, closeTo(path.last.x, 1e-9));
      expect(end.y, closeTo(path.last.y, 1e-9));
    });

    test('passes close to the point in the middle', () {
      var closest = 1e9;
      for (var i = 0; i <= 300; i++) {
        final p = tripAt(i / 300, path);
        closest = math.min(closest, math.sqrt(math.pow(p.x - path[1].x, 2) + math.pow(p.y - path[1].y, 2)));
      }
      expect(closest, lessThan(1.5));
    });

    test('goes no faster than 20 pixels a frame at 60 frames a second', () {
      var prev = tripAt(0, path);
      var worst = 0.0;
      for (var ms = 1100.0; ms <= 2000; ms += 1000 / 60 / SplashTimeline.slowdown) {
        final p = tripAt(SplashFrame(ms).trip, path);
        worst = math.max(worst, math.sqrt(math.pow(p.x - prev.x, 2) + math.pow(p.y - prev.y, 2)));
        prev = p;
      }
      expect(worst, lessThan(20));
    });

    test('a path of two points is a straight line, and one that does not move does not divide by zero', () {
      final mid = tripAt(0.5, [path.first, path.last]);
      expect(mid.x, closeTo((path.first.x + path.last.x) / 2, 1e-9));
      expect(tripAt(0.5, [path.first, path.first, path.first]).x.isFinite, isTrue);
    });

    test('a position outside 0 to 1 is held at the end', () {
      expect(tripAt(-1, path), path.first);
      expect(tripAt(2, path).x, closeTo(path.last.x, 1e-9));
    });
  });
}
