part of '../photo_faces_layer.dart';

/// The hint that faces can be tapped: every face's outline is faintly traced (each
/// starting at its own point, in its own time), then a small sparkle twinkles at the head
/// (on a different side each time); everything is gone by the end. [progress] 0..1.
class _HintPainter extends CustomPainter {
  _HintPainter(this.heads, this.rolls, this.progress);

  final List<_Head> heads;
  final List<_Roll> rolls;
  final double progress;

  /// Paints the outlines of all faces. With many faces at once, a big group, every one gets a lighter version, so the
  /// moment they appear costs the same as a small photo. Each face runs a touch behind or ahead of the others, and
  /// small faces need few points to look round.
  @override
  void paint(Canvas canvas, Size size) {
    final crowded = heads.length > 8;
    for (var i = 0; i < heads.length; i++) {
      final h = heads[i];
      final roll = i < rolls.length ? rolls[i] : null;
      if (roll == null) continue;

      final p = ((progress - roll.lag) / (1 - 0.12)).clamp(0.0, 1.0);
      final trace = Curves.easeOutCubic.transform(Interval(0.0, 0.4).transform(p));
      final glow = Interval(0.0, 0.18).transform(p) * (1 - Interval(0.62, 0.9).transform(p));
      final sparkleIn = Curves.elasticOut.transform(Interval(0.3, 0.55).transform(p));
      final sparkleOut = 1 - Interval(0.72, 0.95).transform(p);

      if (glow > 0) {
        final steps = (h.radius * 0.9).clamp(28.0, crowded ? 48.0 : 96.0).round();
        final outline = _blobPath(h.center, h.radius, p * 2, 0.25, offset: roll.offset, start: roll.start, steps: steps);
        var drawn = outline;
        if (trace < 1) {
          drawn = Path();
          for (final metric in outline.computeMetrics()) {
            drawn.addPath(metric.extractPath(0, metric.length * trace), Offset.zero);
          }
        }
        _glowStroke(canvas, drawn, h.center, h.radius, roll.start + roll.dir * p * math.pi * 2, roll.tint,
            alpha: glow * 0.8, line: 1.8, glow: 0.8, soft: !crowded);
      }

      if (sparkleIn > 0 && sparkleOut > 0) {
        final at = h.center + Offset(math.cos(roll.sparkleAngle), math.sin(roll.sparkleAngle)) * (h.radius * 1.02);
        final star = (9 + math.min(h.radius * 0.12, 6)) * sparkleIn;
        final twinkle = 1 + 0.12 * math.sin(p * math.pi * 6);
        _sparkle(canvas, at, star * twinkle, sparkleOut, p * 0.9 * roll.dir);
      }
    }
  }

  /// A four-point star with a soft glow.
  void _sparkle(Canvas canvas, Offset c, double r, double opacity, double turn) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + turn + i * math.pi / 4;
      final rr = i.isEven ? r : r * 0.26;
      final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    _light(canvas, c, r * 2.2, FacePalette.mint200, 0.55 * opacity);
    canvas.drawPath(path, Paint()..color = FacePalette.white.withValues(alpha: 0.95 * opacity));
  }

  @override
  bool shouldRepaint(covariant _HintPainter old) => old.progress != progress || old.heads != heads;
}
