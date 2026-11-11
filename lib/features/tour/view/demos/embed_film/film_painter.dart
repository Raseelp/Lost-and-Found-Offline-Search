part of '../embed_film.dart';

/// Everything of the film that is drawn: the wall, the heaps it sorts itself into, the words' place, the photos that are
/// picked and fly out, and the finger.
class _FilmPainter extends CustomPainter {
  _FilmPainter({
    required this.geo,
    required this.cells,
    required this.spots,
    required this.small,
    required this.big,
    required this.clock,
  }) : super(repaint: clock);

  final _Geo geo;
  final List<_Cell> cells;
  final List<_Place> spots;
  final Map<String, ui.Image> small;
  final Map<String, ui.Image> big;
  final ValueListenable<double> clock;

  static final Map<String, TextPainter> _text = {};

  Rect _cover(ui.Image im, double aspect) {
    final iw = im.width.toDouble(), ih = im.height.toDouble();
    if (iw / ih > aspect) {
      final w = ih * aspect;
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final h = iw / aspect;
    return Rect.fromLTWH(0, (ih - h) / 2, iw, h);
  }

  TextPainter _painter(
    String text,
    double size,
    FontWeight weight,
    Color color, {
    bool mono = false,
    double spacing = 0,
  }) {
    final key =
        '$text|$size|${weight.value}|${color.toARGB32()}|$mono|$spacing';
    return _text.putIfAbsent(key, () {
      if (_text.length > 200) _text.clear();
      final base = mono
          ? TextStyle(fontFamily: 'monospace', fontSize: size)
          : GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight);
      return TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            fontWeight: weight,
            color: color,
            height: 1.25,
            letterSpacing: spacing,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final cam = geo.camera(t);
    _mat(canvas, t);
    _sweep(canvas, t, cam);
    _leaders(canvas, t);
    _photos(canvas, size, t, cam);
    _words(canvas, t);
    _flights(canvas, t);
    _finger(canvas, t);
    final fadeIn = 1 - _seg(t, 0, 0.5);
    final fadeOut = _seg(t, _Time.end - 1.2, _Time.end);
    final cover = math.max(fadeIn, fadeOut);
    if (cover > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = TourPalette.bottom.withValues(alpha: cover),
      );
    }
  }

  /// The surface the photos are sorted on: a cutting mat, with a faint grid of dots, a stronger dot every fifth, and
  /// the little marks of a ruler along its four edges.
  late final Rect _matRect = Rect.fromLTRB(
    8,
    _Geo.barTop + _Geo.barHeight + 12,
    geo.w - 8,
    geo.h - _Geo.bottomGap - 8,
  );
  late final Float32List _minorDots = _dots(false);
  late final Float32List _majorDots = _dots(true);
  late final Path _ruler = _rulerPath();

  static const double _step = 12;

  Float32List _dots(bool major) {
    final out = <double>[];
    var i = 1;
    for (
      var x = _matRect.left + _step;
      x < _matRect.right - 6;
      x += _step, i++
    ) {
      var j = 1;
      for (
        var y = _matRect.top + _step;
        y < _matRect.bottom - 6;
        y += _step, j++
      ) {
        final isMajor = i % 5 == 0 && j % 5 == 0;
        if (isMajor == major) {
          out
            ..add(x)
            ..add(y);
        }
      }
    }
    return Float32List.fromList(out);
  }

  Path _rulerPath() {
    final path = Path();
    final m = _matRect;
    var i = 1;
    for (var x = m.left + _step; x < m.right - 6; x += _step, i++) {
      final len = i % 5 == 0 ? 6.0 : 3.0;
      path
        ..moveTo(x, m.top + 1)
        ..lineTo(x, m.top + 1 + len)
        ..moveTo(x, m.bottom - 1)
        ..lineTo(x, m.bottom - 1 - len);
    }
    i = 1;
    for (var y = m.top + _step; y < m.bottom - 6; y += _step, i++) {
      final len = i % 5 == 0 ? 6.0 : 3.0;
      path
        ..moveTo(m.left + 1, y)
        ..lineTo(m.left + 1 + len, y)
        ..moveTo(m.right - 1, y)
        ..lineTo(m.right - 1 - len, y);
    }
    return path;
  }

  /// Draws the mat: a pale green-grey, a little darker at its edge, with a thin line round it, then the dots and the
  /// ruler.
  void _mat(Canvas canvas, double t) {
    final a =
        _ease(_seg(t, _Time.pullStart + 1.6, _Time.pullEnd + 0.6)) *
        (1 - _ease(_seg(t, _Time.flightStart + 0.2, _Time.flightStart + 1.4)));
    if (a <= 0.01) return;
    final shape = RRect.fromRectAndRadius(_matRect, const Radius.circular(16));
    canvas.drawRRect(
      shape,
      Paint()..color = TourPalette.mint.withValues(alpha: 0.2 * a),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = TourPalette.teal.withValues(alpha: 0.16 * a),
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      _minorDots,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5
        ..color = TourPalette.teal.withValues(alpha: 0.16 * a),
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      _majorDots,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6
        ..color = TourPalette.teal.withValues(alpha: 0.28 * a),
    );
    canvas.drawPath(
      _ruler,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..color = TourPalette.teal.withValues(alpha: 0.26 * a),
    );
  }

  /// The ring of light that goes out from the chip over the wall as each photo is read.
  void _sweep(Canvas canvas, double t, _Camera cam) {
    final r = (t - _Time.waveStart) * 260 * cam.scale;
    if (r < 2 || t > _Time.waveStart + 4.6) return;
    final a = 1 - _seg(t, _Time.waveStart + 3.4, _Time.waveStart + 4.6);
    final centre = Offset(geo.w / 2, cam.anchorY);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          r,
          [
            TourPalette.glow.withValues(alpha: 0),
            TourPalette.glow.withValues(alpha: 0.12 * a),
            TourPalette.glow.withValues(alpha: 0),
          ],
          const [0.8, 0.98, 1.0],
        ),
    );
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = TourPalette.white.withValues(alpha: 0.7 * a),
    );
  }

  /// The thin lines from the words' place to the photos that are picked.
  void _leaders(Canvas canvas, double t) {
    if (t < _Time.compareStart) return;
    for (final cell in cells) {
      if (cell.rank < 0) continue;
      final p = _ease(_seg(t, cell.pickAt, cell.pickAt + 0.5));
      if (p <= 0) continue;
      final a = 1 - _seg(t, cell.flightAt, cell.flightAt + 0.4);
      if (a <= 0) continue;
      canvas.drawLine(
        geo.query,
        Offset.lerp(geo.query, cell.spot, p)!,
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = TourPalette.teal.withValues(alpha: 0.55 * a),
      );
    }
  }

  /// The photos of the wall. They sort themselves into heaps, each lying a little crooked with a thin white edge, like
  /// prints on a table. The wall fades out towards its edges, and the heaps do not. A best match is picked when the
  /// ring reaches it and lifts out of its heap, then shows its score as a small tag outside the photo, away from the
  /// words. It leaves its heap for good when its flight starts.
  void _photos(Canvas canvas, Size size, double t, _Camera cam) {
    final reveal = _ease(
      _seg(_seg(t, _Time.pullStart, _Time.pullEnd), 0.25, 0.75),
    );
    if (reveal <= 0) return;
    final others = _ease(_seg(t, _Time.othersFade, _Time.othersFade + 0.9));
    final focus = _ease(
      _seg(t, _Time.compareStart + 0.2, _Time.compareStart + 2.0),
    );
    final wallSize = _Geo.tile * cam.scale;
    final centre = Offset(geo.w / 2, cam.anchorY);
    final image = Paint()..filterQuality = FilterQuality.low;
    final fill = Paint();
    for (final cell in cells) {
      final best = cell.rank >= 0;
      if (best && t >= cell.flightAt) continue;
      final collapse = _ease(_seg(t, cell.collapseAt, cell.collapseAt + 1.1));
      final wall = centre + Offset(cell.x * cam.scale, cell.y * cam.scale);
      var pos = Offset.lerp(wall, cell.spot, collapse)!;
      final ex = (wall.dx - centre.dx) / (geo.w * 0.62);
      final ey = (wall.dy - geo.endY) / (geo.h * 0.50);
      final vignette = 1 - _ease(_seg(math.sqrt(ex * ex + ey * ey), 0.62, 1.0));
      var a = _lerp(reveal * vignette, 1.0, collapse);
      if (!best) {
        a *= 1 - 0.55 * focus;
        a *= 1 - others;
      }
      if (a <= 0.01) continue;
      final read = math.sin(
        math.pi * _seg(t, cell.embedAt, cell.embedAt + 0.5),
      );
      var sz = _lerp(wallSize * (1 + 0.1 * read), cell.thumb, collapse);
      var angle = cell.tilt * collapse;
      var radius = _lerp(1.5, 3.5, collapse);
      final pick = best ? _ease(_seg(t, cell.pickAt, cell.pickAt + 0.55)) : 0.0;
      if (pick > 0) {
        pos = cell.spot;
        sz = _lerp(cell.thumb, geo.pop, pick);
        angle = cell.tilt * (1 - pick);
        radius = _lerp(3.5, 7, pick);
      }
      if (pos.dx < -sz ||
          pos.dx > size.width + sz ||
          pos.dy < -sz ||
          pos.dy > size.height + sz) {
        continue;
      }
      final photo = (best && pick > 0 ? big[cell.id] : null) ?? small[cell.id];
      if (photo == null) continue;
      final print = math.max(collapse, pick);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      final rect = Rect.fromCenter(center: Offset.zero, width: sz, height: sz);
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      if (print > 0.02) {
        final edge = 1.6 * print;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge + 1.5).shift(Offset(0, 2.2 + 3 * pick)),
            Radius.circular(radius + 2),
          ),
          fill..color = TourPalette.black.withValues(alpha: 0.05 * a * print),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge + 0.5).shift(Offset(0, 1.2 + 1.5 * pick)),
            Radius.circular(radius + 1),
          ),
          fill..color = TourPalette.black.withValues(alpha: 0.11 * a * print),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge),
            Radius.circular(radius + 1),
          ),
          fill..color = TourPalette.white.withValues(alpha: a),
        );
      }
      image.color = TourPalette.white.withValues(alpha: a);
      canvas.save();
      canvas.clipRRect(shape);
      if (cell.flip && !best) canvas.scale(-1, 1);
      canvas.drawImageRect(photo, _cover(photo, 1), rect, image);
      if (read > 0 && collapse < 0.5) {
        canvas.drawRect(
          rect,
          fill..color = TourPalette.white.withValues(alpha: 0.38 * read * a),
        );
      }
      canvas.restore();
      canvas.restore();
      if (best && pick > 0) {
        final tag = _seg(t, cell.pickAt + 0.4, cell.pickAt + 0.8);
        if (tag > 0) {
          final text = _painter(
            cell.score.toStringAsFixed(2),
            10,
            FontWeight.w700,
            TourPalette.gray900,
          );
          final away = pos - geo.query;
          final dir = away / math.max(1, away.distance);
          final reach =
              geo.pop / 2 +
              8 +
              text.width / 2 * dir.dx.abs() +
              text.height / 2 * dir.dy.abs();
          final box = Rect.fromCenter(
            center: pos + dir * reach,
            width: text.width + 10,
            height: text.height + 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              box.shift(const Offset(0, 1)),
              Radius.circular(box.height / 2),
            ),
            Paint()..color = TourPalette.black.withValues(alpha: 0.10 * tag),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
            Paint()..color = TourPalette.white.withValues(alpha: tag),
          );
          canvas.saveLayer(
            box,
            Paint()..color = TourPalette.white.withValues(alpha: tag),
          );
          text.paint(canvas, Offset(box.left + 5, box.top + 1));
          canvas.restore();
        }
      }
    }
  }

  /// The words. They leave the bar as a small tag, land among the photos as a pin, and then a ring goes out from them
  /// and picks the nearest photos. Two rings go out from the pin while it waits.
  void _words(Canvas canvas, double t) {
    final q = geo.query;
    if (t >= _Time.chipFly && t < _Time.queryLands) {
      final f = _ease(_seg(t, _Time.chipFly, _Time.queryLands));
      final from = Offset(geo.w / 2, _Geo.barTop + _Geo.barHeight / 2);
      final control = Offset(geo.w * 0.78, (from.dy + q.dy) / 2);
      final p =
          from * ((1 - f) * (1 - f)) +
          control * (2 * f * (1 - f)) +
          q * (f * f);
      final scale = _lerp(1, 0.16, _ease(_seg(f, 0.2, 1)));
      final label = _painter(_query, 12, FontWeight.w600, TourPalette.gray900);
      final box = Rect.fromCenter(
        center: p,
        width: (label.width + 22) * scale,
        height: 28 * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.shift(Offset(0, 4 * scale)),
          Radius.circular(14 * scale),
        ),
        Paint()
          ..color = TourPalette.black.withValues(alpha: 0.16 * (1 - f))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(14 * scale)),
        Paint()..color = TourPalette.white.withValues(alpha: 1 - 0.4 * f),
      );
      if (scale > 0.5) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.scale(scale);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
    if (t < _Time.queryLands - 0.1) return;
    final land = _out(_seg(t, _Time.queryLands - 0.1, _Time.queryLands + 0.5));
    final out = 1 - _ease(_seg(t, _Time.flightStart, _Time.flightStart + 0.6));
    if (out <= 0) return;
    for (var k = 0; k < 2; k++) {
      if (t >= _Time.compareStart) break;
      final p = ((t - _Time.queryLands) / 1.8 + k * 0.5) % 1.0;
      canvas.drawCircle(
        q,
        6 + 26 * _out(p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = TourPalette.teal.withValues(
            alpha: 0.4 * (1 - p) * land * out,
          ),
      );
    }
    if (t >= _Time.compareStart) {
      final r = (t - _Time.compareStart) * 1.12 * geo.clear / _Time.ringSeconds;
      final ring =
          1 - _seg(t, _Time.compareStart + 2.0, _Time.compareStart + 2.9);
      if (r > 3 && ring > 0) {
        canvas.drawCircle(
          q,
          r,
          Paint()..color = TourPalette.teal.withValues(alpha: 0.05 * ring),
        );
        canvas.drawCircle(
          q,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = TourPalette.teal.withValues(alpha: 0.7 * ring),
        );
      }
    }
    canvas.drawCircle(
      q + const Offset(0, 2),
      8.5 * land,
      Paint()
        ..color = TourPalette.black.withValues(alpha: 0.25 * out)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      q,
      8 * land,
      Paint()..color = TourPalette.white.withValues(alpha: out),
    );
    canvas.drawCircle(
      q,
      5.2 * land,
      Paint()..color = TourPalette.teal.withValues(alpha: out),
    );
    canvas.drawCircle(
      q,
      1.8 * land,
      Paint()..color = TourPalette.white.withValues(alpha: out),
    );
  }

  /// The best matches leave their heaps for the places of the result, each with its score, and the best one with a "Best match" label.
  void _flights(Canvas canvas, double t) {
    if (t < _Time.flightStart - 0.4) return;
    final bento = geo.bento;
    final fadeOut = 1 - _seg(t, _Time.end - 1.2, _Time.end);
    for (final cell in cells) {
      if (cell.rank < 0) continue;
      final f = _ease(_seg(t, cell.flightAt, cell.flightAt + 1.1));
      if (f <= 0) continue;
      final from = Rect.fromCenter(
        center: cell.spot,
        width: geo.pop,
        height: geo.pop,
      );
      final to = bento[cell.rank];
      final rect = Rect.lerp(
        from,
        to,
        f,
      )!.shift(Offset(0, -math.sin(f * math.pi) * 26));
      final image = big[cell.id] ?? small[cell.id];
      if (image == null) continue;
      final shape = RRect.fromRectAndRadius(
        rect,
        Radius.circular(_lerp(7, 14, f)),
      );
      canvas.drawRRect(
        shape.shift(Offset(0, 5 * f)),
        Paint()
          ..color = TourPalette.black.withValues(alpha: 0.28 * f)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * f + 0.1),
      );
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawImageRect(
        image,
        _cover(image, rect.width / rect.height),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      final pill =
          _seg(t, cell.flightAt + 1.2, cell.flightAt + 1.6) *
          (1 - _seg(t, _Time.pillsOut, _Time.pillsOut + 0.6)) *
          fadeOut;
      if (pill > 0) {
        final text = _painter(
          cell.score.toStringAsFixed(2),
          cell.rank == 0 ? 12.5 : 10.5,
          FontWeight.w700,
          TourPalette.gray900,
        );
        final padX = cell.rank == 0 ? 8.0 : 5.0;
        final box = Rect.fromLTWH(
          rect.right - text.width - padX * 2 - 4,
          rect.bottom - text.height - 7,
          text.width + padX * 2,
          text.height + 3,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
          Paint()..color = TourPalette.white.withValues(alpha: pill),
        );
        canvas.saveLayer(
          box,
          Paint()..color = TourPalette.white.withValues(alpha: pill),
        );
        text.paint(canvas, Offset(box.left + padX, box.top + 1.5));
        canvas.restore();
      }
      if (cell.rank == 0) {
        final label = _seg(t, _Time.bestLabel, _Time.bestLabel + 0.4);
        if (label > 0) {
          final text = _painter(
            'Best match',
            10.5,
            FontWeight.w500,
            TourPalette.white,
          );
          final box = Rect.fromLTWH(
            rect.left + 8,
            rect.bottom - text.height - 18,
            text.width + 20,
            text.height + 8,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
            Paint()..color = TourPalette.black.withValues(alpha: 0.5 * label),
          );
          canvas.saveLayer(
            box.inflate(2),
            Paint()..color = TourPalette.white.withValues(alpha: label),
          );
          text.paint(canvas, Offset(box.left + 10, box.top + 4));
          canvas.restore();
        }
      }
    }
  }

  /// A finger that taps the chip, and later the search bar and its button.
  void _finger(Canvas canvas, double t) {
    final chip = Offset(geo.w / 2, geo.startY);
    final middle = _Geo.barTop + _Geo.barHeight / 2;
    final bar = Offset(geo.w * 0.34, middle);
    final send = Offset(geo.w - 33, middle);
    Offset? at;
    var alpha = 0.0;
    var down = 0.0;
    var presses = <double>[];
    if (t >= 0.2 && t <= 1.8) {
      at = Offset.lerp(
        Offset(geo.w * 0.9, geo.h * 0.8),
        chip,
        _ease(_seg(t, 0.2, 0.95)),
      );
      alpha = _seg(t, 0.2, 0.45) * (1 - _seg(t, 1.4, 1.8));
      presses = [_Time.tap];
    } else if (t >= _Time.fingerIn && t <= _Time.tapSend + 0.7) {
      final toBar = _ease(_seg(t, _Time.fingerIn, _Time.tapBar - 0.05));
      final toSend = _ease(_seg(t, _Time.tapBar + 0.6, _Time.tapSend - 0.05));
      at = Offset.lerp(
        Offset.lerp(Offset(geo.w * 0.9, geo.h * 0.55), bar, toBar)!,
        send,
        toSend,
      );
      alpha =
          _seg(t, _Time.fingerIn, _Time.fingerIn + 0.25) *
          (1 - _seg(t, _Time.tapSend + 0.35, _Time.tapSend + 0.7));
      presses = [_Time.tapBar, _Time.tapSend];
    }
    if (at == null || alpha <= 0) return;
    for (final p in presses) {
      down = math.max(
        down,
        _seg(t, p, p + 0.12) * (1 - _seg(t, p + 0.22, p + 0.4)),
      );
    }
    final r = 16 * (1 - 0.18 * down);
    canvas.drawCircle(
      at + const Offset(0, 3),
      r,
      Paint()
        ..color = TourPalette.black.withValues(alpha: 0.18 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      at,
      r,
      Paint()..color = TourPalette.white.withValues(alpha: 0.82 * alpha),
    );
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = TourPalette.teal.withValues(alpha: 0.55 * alpha),
    );
    for (final p in presses) {
      final ring = _seg(t, p, p + 0.55);
      if (ring > 0 && ring < 1) {
        canvas.drawCircle(
          at,
          16 + 34 * _out(ring),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = TourPalette.teal.withValues(alpha: 0.5 * (1 - ring)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FilmPainter old) =>
      old.cells != cells || old.geo != geo;
}
