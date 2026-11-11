part of '../action_fab.dart';

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.path,
    required this.fab,
    required this.rx,
    required this.ry,
    required this.search,
    required this.fabColor,
    required this.searchColor,
    required this.withSearch,
    required this.merge,
    required this.lift,
  });

  final Path path;
  final Offset fab;
  final double rx;
  final double ry;
  final Offset search;
  final Color fabColor;
  final Color searchColor;
  final bool withSearch;

  /// 0 apart, 1 run into each other.
  final double merge;

  /// 1 while the button floats, 0 once it has run into the search button: its shadow goes with it.
  final double lift;

  /// Paints the liquid. The button's shadow comes from the button alone, because the search part is glass and nothing
  /// may show through it. The button and the search button keep their own colours and mix only in the stretch between
  /// the two, at least a few pixels wide so a button sitting right on the search button still blends. Apart, the blend
  /// sits in the gap. As they merge it widens up to about 40 px, S-shaped so the colours settle into each end instead
  /// of ending in a visible edge.
  @override
  void paint(Canvas canvas, Size size) {
    final own = Path()..addOval(Rect.fromCenter(center: fab, width: rx * 2, height: ry * 2));
    canvas.drawPath(
      own.shift(const Offset(0, 8)),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.34 * lift)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final paint = Paint()..isAntiAlias = true;
    if (withSearch) {
      final sign = search.dy >= fab.dy ? 1.0 : -1.0;
      var from = fab.dy + sign * ry * 0.95;
      var to = search.dy - sign * (kFloatingBarHeight / 2) * 0.95;
      final wanted = 6 + 36 * Curves.easeInOut.transform(((merge - 0.25) / 0.45).clamp(0.0, 1.0));
      if ((to - from) * sign < wanted) {
        final mid = (from + to) / 2;
        from = mid - sign * wanted / 2;
        to = mid + sign * wanted / 2;
      }
      const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
      final colors = [
        for (final t in stops) Color.lerp(fabColor, searchColor, t * t * (3 - 2 * t))!,
      ];
      paint.shader = ui.Gradient.linear(Offset(search.dx, from), Offset(search.dx, to), colors, stops);
    } else {
      paint.color = fabColor;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => true;
}
