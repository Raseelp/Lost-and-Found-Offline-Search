part of '../photo_faces_layer.dart';

/// The dimmed photo (with the head left clear) and a glowing outline that draws itself round the head, then keeps
/// turning slowly, starting and turning differently each time ([roll]).
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.center,
    required this.radius,
    required this.progress,
    required this.spin,
    required this.roll,
    this.settled = false,
  });

  /// The band is already whole (it came from a flight): only the dimming and the lights fade in.
  final bool settled;

  final Offset center;
  final double radius;
  /// How far the outline has appeared, from 0 to 1.
  final double progress;
  /// The spin in radians.
  final double spin;
  final _Roll roll;

  /// Paints the dimmed photo with a hole around the head, and the ring. The band's own progress is complete from the
  /// first frame when it comes from a flight. The outline settles in from a little wider, and the hole wobbles most
  /// while it settles in. The outline draws itself round the head, with three tiny lights drifting along its edge.
  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    if (t <= 0) return;

    final loop = spin / (2 * math.pi);
    final phase = roll.dir > 0 ? loop : 1 - loop;
    final rt = settled ? 1.0 : t;
    final wobble = 1 - rt;

    final hole = _blobPath(center, radius * 1.06, phase, wobble, offset: roll.offset, start: roll.start);
    final everything = Path()..addRect(Offset.zero & size);
    canvas.drawPath(
      Path.combine(PathOperation.difference, everything, hole),
      Paint()..color = FacePalette.black.withValues(alpha: 0.5 * t),
    );

    final r = radius * (1 + 0.14 * (1 - rt));
    final outline = _blobPath(center, r, phase, wobble, offset: roll.offset, start: roll.start);

    Path drawn = outline;
    if (rt < 1) {
      drawn = Path();
      for (final metric in outline.computeMetrics()) {
        drawn.addPath(metric.extractPath(0, metric.length * rt), Offset.zero);
      }
    }
    _glowStroke(canvas, drawn, center, r, roll.start + roll.dir * spin * 1.5, roll.tint,
        alpha: rt, line: 2.8, glow: 1.3);

    for (var k = 0; k < 3; k++) {
      final a = roll.start + roll.dir * spin * 1.6 + k * 2 * math.pi / 3;
      final p = center + Offset(math.cos(a), math.sin(a)) * _blobRadius(a, r, phase, wobble, roll.offset);
      _light(canvas, p, 9, FacePalette.white, 0.5 * t);
      canvas.drawCircle(p, 1.7, Paint()..color = FacePalette.white.withValues(alpha: t));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.center != center || old.radius != radius || old.progress != progress || old.spin != spin;
}
