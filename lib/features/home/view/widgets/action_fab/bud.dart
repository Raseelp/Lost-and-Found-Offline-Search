part of '../action_fab.dart';

/// One action on its way out of the button, as a drop of the button's liquid: where it is, how big, how it
/// is stretched, and how it hangs on to the button.
///
/// Its way out: it clings at first (swelling out of the button on a thick neck), then pulls away faster and
/// faster, the neck thinning until it pinches off, and once free it runs a little past its place and wobbles
/// back. Going back in plays the same way backwards: the neck reaches out, catches it and draws it in.
class _Bud {
  const _Bud({
    required this.centre,
    required this.radius,
    required this.angle,
    required this.stretch,
    required this.waist,
    required this.free,
    required this.settled,
    required this.shows,
    required this.buttonRadius,
  });

  /// Works out where one drop is along its way out. It is small while still mostly inside the button and plumps up to
  /// full size as it comes out. The neck is as wide as the drop while they overlap, drawing out thinner until it
  /// pinches off well clear of the button. Fast, the drop draws out long and thin; running past its place and turning
  /// back, it squashes. With no motion wanted it simply fades in where it goes.
  factory _Bud.at({
    required Offset from,
    required Offset to,
    required double buttonRadius,
    required double radius,
    required double progress,
    required bool calm,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final angle = (to - from).direction;
    if (calm) {
      return _Bud(
        centre: to, radius: radius, angle: angle, stretch: 1, waist: 0, free: p, settled: p, shows: p,
        buttonRadius: buttonRadius,
      );
    }
    final along = _out(p);
    final centre = Offset.lerp(from, to, along)!;
    final gap = (centre - from).distance;
    final size = radius * (0.55 + 0.45 * Curves.easeOut.transform((gap / (buttonRadius + radius)).clamp(0.0, 1.0)));
    final near = buttonRadius, far = buttonRadius + size * 2.6;
    final k = ((far - gap) / (far - near)).clamp(0.0, 1.0);
    final waist = size * 0.9 * k * k * (3 - 2 * k);
    final slope = (_out(math.min(1, p + 0.01)) - _out(math.max(0, p - 0.01))) / 0.02;
    final stretch = (1 + 0.06 * slope + 0.12 * k * (1 - k) * 4).clamp(0.88, 1.18);
    return _Bud(
      centre: centre,
      radius: size,
      angle: angle,
      stretch: stretch,
      waist: waist,
      free: Curves.easeOut.transform(((1 - k) * 1.25 - 0.25).clamp(0.0, 1.0)),
      settled: const Interval(0.72, 1, curve: Curves.easeOut).transform(p),
      shows: (p * 8).clamp(0.0, 1.0),
      buttonRadius: buttonRadius,
    );
  }

  /// Clings (slow, quadratic) for the first part, then springs out, runs about a tenth past and settles.
  static double _out(double t) {
    const cling = 0.34;
    if (t <= cling) {
      final u = t / cling;
      return 0.2 * u * u;
    }
    final tau = (t - cling) / (1 - cling);
    final base = 0.2 + 0.8 * (1 - math.pow(1 - tau, 3));
    return base + 0.11 * math.sin(tau * math.pi * 2) * math.exp(-3.2 * tau) * (1 - tau);
  }

  final Offset centre;
  final double radius;

  /// The way from the button to where it settles.
  final double angle;

  /// Along [angle]: above 1 drawn out long, below 1 squashed (its area kept).
  final double stretch;

  /// The neck back to the button, 0 once it has pinched off.
  final double waist;

  /// 0 while it hangs on the neck, 1 once free (its icon shows).
  final double free;

  /// 1 once it has settled (its name shows).
  final double settled;

  /// The drop shows at all (a quick fade at the very start, so nothing pops into being).
  final double shows;
  final double buttonRadius;
}
