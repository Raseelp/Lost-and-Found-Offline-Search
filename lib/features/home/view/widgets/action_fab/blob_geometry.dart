part of '../action_fab.dart';

/// The button's liquid: an ellipse (the button, stretched when it moves fast), the search button's circle while they
/// are running into each other, and a waist between them that is thick when they are close and snaps to nothing as
/// they pull apart.
class _BlobGeometry {
  const _BlobGeometry({
    required this.fab,
    required this.rx,
    required this.ry,
    required this.search,
    required this.r,
    required this.withSearch,
  });

  final Offset fab;
  final double rx;
  final double ry;
  final Offset search;
  final double r;
  final bool withSearch;

  /// The outline of the liquid. The waist is none at the distance the button rests at and the whole width of the
  /// circle once they overlap.
  Path path() {
    final fabOval = Path()..addOval(Rect.fromCenter(center: fab, width: rx * 2, height: ry * 2));
    if (!withSearch) return fabOval;
    final searchCircle = Path()..addOval(Rect.fromCircle(center: search, radius: r));
    var result = Path.combine(PathOperation.union, fabOval, searchCircle);

    final gap = (search.dy - fab.dy).abs();
    final far = 2.4 * r, near = 0.9 * r;
    final k = ((far - gap) / (far - near)).clamp(0.0, 1.0);
    final waist = r * k * k * (3 - 2 * k);
    if (waist > 1.5 && gap > 1) {
      final cx = search.dx;
      final mid = (search.dy + fab.dy) / 2;
      final end = r * 0.9;
      final bend = 2 * waist - end;
      final neck = Path()
        ..moveTo(cx - end, fab.dy)
        ..quadraticBezierTo(cx - bend, mid, cx - end, search.dy)
        ..lineTo(cx + end, search.dy)
        ..quadraticBezierTo(cx + bend, mid, cx + end, fab.dy)
        ..close();
      result = Path.combine(PathOperation.union, result, neck);
    }
    return result;
  }
}
