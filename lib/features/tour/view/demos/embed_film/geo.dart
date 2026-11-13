part of '../embed_film.dart';

/// How the film is laid out for the room it has.
class _Geo {
  _Geo(Size size) : w = size.width, h = size.height {
    side = math.min(w, 320.0);
    heroHeight = cardHeight + buttonGap + buttonHeight;
    startScale = math.min(
      1.0,
      math.min((h - bottomGap - 8) / heroHeight, w / side),
    );
    startY = 8 + heroHeight * startScale / 2;
    buttonY = startY + (cardHeight + buttonGap + buttonHeight / 2 - heroHeight / 2) * startScale;
    endY = (h - bottomGap) / 2 + 24;
    map = Rect.fromLTRB(
      14,
      barTop + barHeight + 30,
      w - 14,
      h - bottomGap - 30,
    );
    query = Offset(map.left + map.width * 0.5, map.top + map.height * 0.30);
    clear = 0.27 * math.min(map.width, map.height);
    pop = (clear * 0.42).clamp(26.0, 40.0);
    thumb = (map.width * 0.052).clamp(14.0, 20.0);
  }

  final double w, h;
  late final double side, heroHeight, startScale, startY, endY;

  /// Where the middle of the Start button is when the film begins.
  late final double buttonY;

  /// The part of the room the photos are placed in.
  late final Rect map;

  /// Where the words land, how far round it nothing else lies, how big a photo is when it is picked, and how big it is
  /// when it lies among the others.
  late final Offset query;
  late final double clear, pop, thumb;

  /// How tall the scan card is with its three steps waiting, the gap under it and the button.
  static const double cardHeight = 258;
  static const double buttonGap = 16;
  static const double buttonHeight = 48;

  static const double bottomGap = 12;
  static const double pitch = 64;
  static const double tile = 58;
  static const double endScale = 0.38;
  static const double barTop = 10;
  static const double barHeight = 48;

  Offset mapPoint(double nx, double ny) =>
      Offset(map.left + nx * map.width, map.top + ny * map.height);

  _Camera camera(double t) {
    final pull = _ease(_seg(t, _Time.pullStart, _Time.pullEnd));
    return _Camera(
      startScale * math.pow(endScale / startScale, pull).toDouble(),
      _lerp(startY, endY, pull),
    );
  }

  /// Where the results land: the usual best-match layout under the bar.
  late final List<Rect> bento = () {
    const top = barTop + barHeight + 12;
    final area = Size(w - 20, h - bottomGap - top - 4);
    return [
      for (final r in bentoRects(7, area, gap: 6))
        r.shift(const Offset(10, top)),
    ];
  }();
}
