part of '../action_fab.dart';

/// Draws the drops and their necks, in the button's teal where they leave it, turning white as they come
/// out. The button itself is drawn over the necks' roots, so they grow out of it.
class _BudsPainter extends CustomPainter {
  _BudsPainter({required this.buttonAt, required this.buds});

  final Offset buttonAt;
  final List<_Bud> buds;

  /// Paints one drop in its own frame, with the button at the origin and the drop out along the x axis. Its sides bow
  /// in to a waist halfway. The shadow comes from the drop alone, growing in as it comes free, with none under the
  /// neck. The colour is teal at the button's edge and white from the drop on, the change spread over at least a dozen
  /// pixels and S-shaped so there is no line across it.
  @override
  void paint(Canvas canvas, Size size) {
    for (final bud in buds) {
      if (bud.shows <= 0) continue;
      final gap = (bud.centre - buttonAt).distance;
      canvas.save();
      canvas.translate(buttonAt.dx, buttonAt.dy);
      canvas.rotate(bud.angle);
      final rx = bud.radius * bud.stretch;
      final ry = bud.radius / bud.stretch;
      final drop = Path()..addOval(Rect.fromCenter(center: Offset(gap, 0), width: rx * 2, height: ry * 2));
      var shape = drop;
      if (bud.waist > 0.8) {
        final x0 = bud.buttonRadius * 0.5;
        final x1 = math.max(x0 + 1, gap - rx * 0.4);
        final e0 = math.min(bud.buttonRadius, bud.radius) * 0.9;
        final e1 = ry * 0.9;
        final mid = (x0 + x1) / 2;
        final bend = 2 * bud.waist - (e0 + e1) / 2;
        final neck = Path()
          ..moveTo(x0, -e0)
          ..quadraticBezierTo(mid, -bend, x1, -e1)
          ..lineTo(x1, e1)
          ..quadraticBezierTo(mid, bend, x0, e0)
          ..close();
        shape = Path.combine(PathOperation.union, drop, neck);
      }
      final lifted = bud.free * bud.shows;
      if (lifted > 0.01) {
        canvas.save();
        canvas.rotate(-bud.angle);
        final c = Offset(gap * math.cos(bud.angle), gap * math.sin(bud.angle));
        canvas.drawOval(
          Rect.fromCenter(center: c + const Offset(0, 6), width: bud.radius * 2, height: bud.radius * 2),
          Paint()
            ..color = AppColors.shadow.withValues(alpha: 0.26 * lifted)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.restore();
      }
      var from = bud.buttonRadius * 0.95;
      var to = gap - rx * 0.6;
      if (to - from < 14) {
        final m = (from + to) / 2;
        from = m - 7;
        to = m + 7;
      }
      const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
      final colors = [
        for (final t in stops)
          Color.lerp(AppColors.primary, AppColors.canvas, t * t * (3 - 2 * t))!.withValues(alpha: bud.shows),
      ];
      canvas.drawPath(
        shape,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(Offset(from, 0), Offset(to, 0), colors, stops),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BudsPainter old) => true;
}
