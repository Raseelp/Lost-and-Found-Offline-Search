part of '../embed_film.dart';

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

double _ease(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;

double _out(double x) => 1 - math.pow(1 - x, 3).toDouble();

double _lerp(double a, double b, double x) => a + (b - a) * x;

const String _query = 'a dog on a beach';

/// A photo of the wall: where it is, which photo it holds, and where it lies among the others when they are placed by
/// what is in them.
class _Cell {
  _Cell(this.i, this.j, this.id, this.flip, this.rank, this.score);

  final int i, j;
  final String id;
  final bool flip;

  /// -1, or the place among the best matches.
  final int rank;
  final double score;
  double x = 0, y = 0;
  double embedAt = 0;
  double collapseAt = 0;
  double pickAt = 0;
  double thumb = 24;
  double tilt = 0;
  int cluster = 0;
  Offset spot = Offset.zero;
  double get flightAt => _Time.flightStart + 0.09 * rank;
}

/// A group of photos that are alike, with its name.
class _Place {
  _Place(this.name, this.at);

  final String name;
  final Offset at;
}

class _Camera {
  const _Camera(this.scale, this.anchorY);

  final double scale;
  final double anchorY;
}
