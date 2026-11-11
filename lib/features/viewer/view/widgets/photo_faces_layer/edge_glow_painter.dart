part of '../photo_faces_layer.dart';

class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter(this.t, this.orbs, this.fade);

  /// How far around the loop, from 0 to 1.
  final double t;
  final List<_Orb> orbs;
  /// How much is showing, from 0 to 1.
  final double fade;

  /// A point on the screen's edge, [u] (0..1) of the way round.
  static Offset _onEdge(double u, Size s) {
    final total = 2 * (s.width + s.height);
    var d = (u % 1) * total;
    if (d < s.width) return Offset(d, 0);
    d -= s.width;
    if (d < s.height) return Offset(s.width, d);
    d -= s.height;
    if (d < s.width) return Offset(s.width - d, s.height);
    d -= s.width;
    return Offset(0, s.height - d);
  }

  /// Rings per pool: each a plain, faint circle, so together they fall off smoothly with
  /// no gradient shader at all (a big gradient rendered as coarse blocks on some phones).
  static const _rings = 26;

  /// Paints the pools. Each breathes slowly between fainter and stronger, and its rings have a per-ring transparency
  /// chosen so that the stack adds up to the peak strength in the middle.
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || fade <= 0) return;
    final short = math.min(size.width, size.height);
    for (final orb in orbs) {
      final centre = _onEdge(orb.phase + orb.turns * t, size);
      final breath = 0.5 + 0.5 * math.sin(orb.breathPhase + 2 * math.pi * orb.breathTurns * t);
      final peak = (0.26 + 0.12 * breath) * fade;
      final radius = short * orb.size * (0.94 + 0.12 * breath);
      final each = 1 - math.pow(1 - peak, 1 / _rings).toDouble();
      final paint = Paint()..color = orb.color.withValues(alpha: each);
      for (var i = 0; i < _rings; i++) {
        canvas.drawCircle(centre, radius * (i + 1) / _rings, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeGlowPainter old) => old.t != t || old.orbs != orbs || old.fade != fade;
}
