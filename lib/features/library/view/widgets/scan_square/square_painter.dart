part of '../scan_square.dart';

class _SquarePainter extends CustomPainter {
  _SquarePainter({
    required this.scene,
    required Listenable repaint,
    required this.progress,
    required this.indeterminate,
    required this.faceAmount,
    required this.faceProgress,
    required this.faceIndeterminate,
  }) : super(repaint: repaint);

  final _SquareScanHeroState scene;
  final double progress;
  final bool indeterminate;
  final double faceAmount;
  final double faceProgress;
  final bool faceIndeterminate;

  Canvas get _c => _canvas!;
  Canvas? _canvas;

  /// With the lid on, everything under it is hidden (it covers the die, the bank and the wires with room to spare,
  /// even when pressed), so none of it is drawn. The die and the memory bank are drawn a little smaller than the board
  /// so it has parts of its own round it.
  @override
  void paint(Canvas canvas, Size size) {
    _canvas = canvas;
    canvas.save();
    canvas.scale(size.width / _sheet);
    final now = scene._now;

    final scan = scene._scanAmt, done = scene._doneAmt;
    paintChipBoard(canvas);
    if (scene._lid > 0 || scan > .01) {
      _wires(now);
      canvas.save();
      canvas.translate(chipSheet / 2, chipSheet / 2);
      canvas.scale(chipDieScale);
      canvas.translate(-chipSheet / 2, -chipSheet / 2);
      paintChipDie(canvas, _photoBox, scene._dieColumns);
      paintChipMemory(canvas, _strip);

      if (scan > .01) {
        _withAlpha(scan, () {
          if (scene.widget.faceMode) {
            _faces(now);
          } else {
            _index(now);
          }
        });
      }

      canvas.restore();
    }

    paintChipLid(
      canvas,
      open: scene._lid,
      now: now,
      pressed: scene._pressed,
      idle: scene._lidIdle.withHint(scene.widget.idleHint),
      done: scene._lidDone,
      doneAmt: done,
      tilt: scene._tilt,
      tiltLive: scene._tiltLive,
    );
    canvas.restore();
    _canvas = null;
  }

  /// Draws [body] at [alpha] (as one picture, so overlapping parts do not show through).
  void _withAlpha(double alpha, void Function() body) {
    if (alpha >= .99) {
      body();
      return;
    }
    _c.saveLayer(
      const Rect.fromLTWH(0, 0, _sheet, _sheet),
      Paint()..color = ScanPalette.white.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
    body();
    _c.restore();
  }

  /// The loading of the scan: two rows of lanes between the die (top, gold, CLIP) or the memory
  /// bank (bottom, copper, FACE) and the board. They are brought up one after another with the
  /// scan. The one coming up trains (a pattern runs up and down it), a lane that has just locked
  /// flashes along its length, and packets of data run along the lanes that are up.
  void _wires(double now) {
    const gold = ScanPalette.gold350;
    const copper = ScanPalette.orange400;
    final scene = this.scene;
    for (var bar = 0; bar < 2; bar++) {
      final training = scene._training[bar];
      final fraction = scene._trainFraction[bar];
      final wires = bar == 0 ? scene._wireClip : scene._wireFace;
      paintChipLanes(
        _c,
        bar,
        color: bar == 0 ? gold : copper,
        alpha: bar == 0 ? scene._clipAlpha : scene._faceAlpha,
        level: (i) {
          if (i == training) {
            return (.25 + .5 * fraction + .15 * math.sin(now * 24)).clamp(0.0, 1.0);
          }
          return wires[i];
        },
      );
      for (var i = 0; i < chipWireCount; i++) {
        final age = now - scene._lockAt[bar][i];
        if (age < 0 || age > .5) continue;
        final f = age / .5;
        _c.drawPath(
          chipLaneSegment(bar, i, f - .35, f),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.8
            ..strokeCap = StrokeCap.round
            ..color = ScanPalette.white.withValues(alpha: .9 * (1 - f * .6)),
        );
      }
      if (training >= 0) {
        for (var k = 0; k < 2; k++) {
          final f = ((now * 1.5 + k * .5) % 1);
          final pos = chipLanePoint(bar, training, f);
          _c.drawCircle(pos, 3.2, Paint()..color = ScanPalette.white.withValues(alpha: .22));
          _c.drawCircle(pos, 1.4, Paint()..color = ScanPalette.white.withValues(alpha: .85));
        }
      }
    }
    _packetsOnLanes();
  }

  /// A packet is a short bright dash running along its lane from the die (or the bank) to the
  /// board, leaving the lane lit behind it.
  void _packetsOnLanes() {
    final c = _c;
    for (final packet in scene._packets) {
      final t = packet.t.clamp(0.0, 1.0);
      final color = packet.bar == 0 ? ScanPalette.gold150 : ScanPalette.orange150;
      final fade = packet.t > 1 ? 1 - (packet.t - 1) / .1 : 1.0;
      c.drawPath(
        chipLaneSegment(packet.bar, packet.wire, t - .2, t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: .55 * fade),
      );
      final b = chipLanePoint(packet.bar, packet.wire, t);
      c.drawCircle(b, 3.4, Paint()..color = color.withValues(alpha: .25 * fade));
      c.drawCircle(b, 1.5, Paint()..color = ScanPalette.white.withValues(alpha: .95 * fade));
    }
  }

  /// The memory array along the top of the bank: a cell is written for every bit of the scan
  /// that has been stored. The cell being written next pulses, and the ones just written flash.
  void _memoryCells(double now) {
    final c = _c;
    const cols = _memoryCellCount ~/ 2;
    const left = 8.0;
    final pitch = (_strip.width - 2 * left) / cols;
    final written = scene._cellsWritten;
    final dim = Paint()..color = ScanPalette.white.withValues(alpha: .1);
    final lit = Paint()..color = ScanPalette.glow.withValues(alpha: .8);
    for (var k = 0; k < _memoryCellCount; k++) {
      final row = k ~/ cols, col = k % cols;
      final cell = Rect.fromLTWH(
        _strip.left + left + col * pitch + .5,
        _strip.top + 2.2 + row * 3.8,
        pitch - 1.1,
        2.6,
      );
      c.drawRRect(RRect.fromRectAndRadius(cell, const Radius.circular(.6)), k < written ? lit : dim);
      final at = scene._cellWrittenAt[k];
      if (at != null) {
        final f = (now - at) / .8;
        c.drawRRect(
          RRect.fromRectAndRadius(cell.inflate(1.2 * (1 - f)), const Radius.circular(1)),
          Paint()..color = ScanPalette.white.withValues(alpha: .9 * (1 - f)),
        );
      }
    }
    if (written < _memoryCellCount && scene._scanAmt > .5) {
      final row = written ~/ cols, col = written % cols;
      final cell = Rect.fromLTWH(_strip.left + left + col * pitch + .5, _strip.top + 2.2 + row * 3.8, pitch - 1.1, 2.6);
      c.drawRRect(
        RRect.fromRectAndRadius(cell.inflate(.8), const Radius.circular(1)),
        Paint()..color = ScanPalette.glow.withValues(alpha: .25 + .55 * (.5 + .5 * math.sin(now * 9))),
      );
    }
  }

  Paint _imagePaint(double alpha) =>
      Paint()..color = ScanPalette.white.withValues(alpha: alpha.clamp(0.0, 1.0));

  void _text(
    String text,
    Offset center,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(_c, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _thumb(_Pic pic, Rect slot, double alpha) {
    final c = _c;
    final side = math.min(pic.w, pic.h);
    final src = Rect.fromCenter(
      center: Offset(pic.w / 2, pic.h / 2),
      width: side,
      height: side,
    );
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(slot, const Radius.circular(6)));
    c.drawImageRect(pic.image, src, slot, _imagePaint(alpha));
    c.restore();
    c.drawRRect(
      RRect.fromRectAndRadius(slot, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ScanPalette.white.withValues(alpha: alpha),
    );
  }

  Rect _tileRect(double x) => Rect.fromLTWH(x, _strip.top + 11, _tileSize, _tileSize);

  /// The strip: the photos waiting for their faces (the FACE bar fills as the queue does).
  void _queueStrip(double now) {
    final loadStart = scene._loadStart[0];
    if (loadStart >= 0) _memoryWeights(now, ((now - loadStart) / _loadSeconds).clamp(0.0, 1.0), ScanPalette.glow, 1);
    _memoryCells(now);
    for (final tile in scene._queue) {
      final slot = _tileRect(tile.x);
      _thumb(tile.pic, slot, 1);
      if (tile.frames != null) _videoMark(slot, tile.frames!, 1);
    }
  }

  /// The mark on a video's tile: a play sign, and how many frames were read from it.
  void _videoMark(Rect r, int frames, double alpha) {
    if (alpha <= .01) return;
    final c = _c;
    final k = math.min(1.6, r.width / _tileSize);
    final white = ScanPalette.white.withValues(alpha: alpha.clamp(0.0, 1.0));
    TextPainter? label;
    if (frames > 0) {
      label = TextPainter(
        text: TextSpan(
          text: '\u00d7$frames',
          style: TextStyle(fontSize: 6.5 * k, height: 1, fontWeight: FontWeight.w700, color: white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final h = 9 * k;
    final w = h + (label == null ? 0 : label.width + 2 * k);
    final pill = Rect.fromLTWH(r.left + 2.5 * k, r.bottom - 2.5 * k - h, w, h);
    c.drawRRect(
      RRect.fromRectAndRadius(pill, Radius.circular(h / 2)),
      Paint()..color = ScanPalette.black.withValues(alpha: .62 * alpha),
    );
    final mid = Offset(pill.left + h / 2 + .4 * k, pill.center.dy);
    final side = 2.2 * k;
    c.drawPath(
      Path()
        ..moveTo(mid.dx - side * .8, mid.dy - side)
        ..lineTo(mid.dx + side, mid.dy)
        ..lineTo(mid.dx - side * .8, mid.dy + side)
        ..close(),
      Paint()..color = white,
    );
    label?.paint(c, Offset(pill.left + h - .5 * k, pill.center.dy - label.height / 2));
  }

  /// The data bus between the die and the memory bank: a row of fine lines, lit while a picture
  /// goes down into memory.
  void _bus(double now, double energy) {
    final c = _c;
    final y0 = _photoBox.bottom + 3.4, y1 = _strip.top - 0.5;
    for (var i = 0; i < 7; i++) {
      final x = _strip.left + 6 + 17 + i * 38;
      c.drawLine(Offset(x, y0), Offset(x, y1), Paint()..strokeWidth = 1.4..color = ScanPalette.gold400.withValues(alpha: .35));
      if (energy > .02) {
        final f = ((now * 2.2 + i * .17) % 1);
        final yy = y0 + (y1 - y0) * f;
        c.drawLine(
          Offset(x, yy),
          Offset(x, math.min(y1, yy + 3.5)),
          Paint()
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = ScanPalette.glow.withValues(alpha: .95 * energy),
        );
      }
    }
  }

  /// The light of things working on the dark die.

  static final Map<int, List<Rect>> _blockCache = {};
  List<Rect> get _blocks => _blockCache.putIfAbsent(scene._dieColumns, () => chipDieBlocks(_photoBox, scene._dieColumns));

  /// While the folder is still being walked: the chip powers up block by block, the way a real processor does: the
  /// clock generator and power management first, then the memory controller, the fabric, the shared cache, the cores
  /// one after another and last the outside interfaces. The more files found, the more is awake. A block that has just
  /// come on flashes and settles to a working glow that flickers a little. What lights is the die's own structure, so
  /// the light seems to come from inside the silicon.
  void _discovering(double now, int? found) {
    final unit = found != null ? found / 10.0 : (now - scene._scanAt) * 1.2;
    final regions = <(Rect, double)>[];
    for (var i = 0; i < _blocks.length; i++) {
      final on = _ease((unit - i).clamp(0.0, 1.0));
      if (on <= 0) continue;
      final settled = unit - i - 1;
      final flash = settled < 0 ? 0.0 : math.max(0.0, 1 - settled / 1.2);
      final activity = .5 + .2 * math.sin(now * (1.7 + i * .29) + i * 1.9) + .1 * math.sin(now * 7.3 + i * 3.1);
      regions.add((_blocks[i], (on * (activity + .5 * flash)).clamp(0.0, 1.0)));
    }
    paintChipDieLit(_c, _photoBox, scene._dieColumns, regions, ScanPalette.glow);
  }

  /// How long the model takes to be loaded in the picture (the chip's part of the story).
  static const double _loadSeconds = 4.6;

  /// Where the chips of the memory bank are (one under each place a picture lands).
  Rect _memoryChip(int k) => Rect.fromLTWH(_strip.left + 6 + k * 38, _strip.top + 11, 34, 34);

  static int _hash(int a) {
    a = (a ^ 61) ^ (a >> 16);
    a *= 9;
    a ^= a >> 4;
    a *= 0x27d4eb2d;
    a ^= a >> 15;
    return a & 0x7fffffff;
  }

  /// The model, as it lands in memory: chip after chip of the bank fills with rows of data, from
  /// the top down, the newest row bright. When it is all in, the data stays, dimmer: the model is
  /// in memory.
  void _memoryWeights(double now, double f, Color color, double alpha) {
    if (f >= 1 && alpha == 1 && color == ScanPalette.glow) {
      paintChipCached(_c, 'weights', _strip.inflate(4), (canvas) {
        final saved = _canvas;
        _canvas = canvas;
        _drawWeights(1, color, 1);
        _canvas = saved;
      });
      return;
    }
    _drawWeights(f, color, alpha);
  }

  void _drawWeights(double f, Color color, double alpha) {
    final c = _c;
    final settle = _ease(_seg(f, .94, 1.0));
    final paint = Paint();
    for (var k = 0; k < 7; k++) {
      final u = (f * 7.4 - k * .9).clamp(0.0, 1.0);
      if (u <= 0) continue;
      final chip = _memoryChip(k);
      final inner = chip.deflate(3.2);
      const rows = 12;
      final rowH = inner.height / rows;
      final level = (1 - .6 * settle) * alpha;
      final head = u * rows;
      for (var r = 0; r < rows && r < head + 1; r++) {
        var x = inner.left;
        var h = _hash(k * 131 + r * 17 + 5);
        final newest = r + 1 > head && u < 1;
        while (x < inner.right - .5) {
          h = _hash(h + 7);
          final w = 2.0 + h % 7;
          final shade = .4 + .5 * ((h >> 8) % 100) / 100;
          paint.color = (newest ? ScanPalette.white : color).withValues(alpha: (newest ? .95 : shade) * level);
          c.drawRect(Rect.fromLTWH(x, inner.top + r * rowH + .3, math.min(w, inner.right - x), rowH - .8), paint);
          x += w + 1 + (h >> 4) % 2;
        }
      }
      c.drawRRect(
        RRect.fromRectAndRadius(chip.deflate(.6), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: (u < 1 ? .7 : .25) * alpha),
      );
    }
  }

  /// The data going up from the memory into the die while the model loads: a run of light up each
  /// line of the bus, from every chip of the bank that has begun to fill.
  void _busUp(double now, double f, Color color, double alpha) {
    final c = _c;
    final y0 = _photoBox.bottom + 3.4, y1 = _strip.top - 0.5;
    for (var i = 0; i < 7; i++) {
      if (f * 7.4 - i * .9 <= 0) continue;
      final x = _strip.left + 6 + 17 + i * 38;
      for (var k = 0; k < 2; k++) {
        final p = (now * 1.9 + i * .23 + k * .5) % 1;
        final yy = y1 - (y1 - y0) * p;
        c.drawLine(
          Offset(x, yy),
          Offset(x, math.min(y1, yy + 4)),
          Paint()
            ..strokeWidth = 1.9
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: .95 * alpha),
        );
      }
    }
  }

  /// The chip with nothing to read yet. The first time, the model is being loaded into memory:
  /// it comes from the bank, up the bus, into the die, where the shared cache and then each core
  /// fill from the top down with a bright edge. After that the chip waits for the next picture
  /// with a quiet glow, as a loaded processor idles.
  void _waiting(double now, Color color, double alpha, {int kind = 0}) {
    if (alpha <= .01) return;
    final c = _c;
    if (scene._loadStart[kind] < 0) scene._loadStart[kind] = now;
    final f = ((now - scene._loadStart[kind]) / _loadSeconds).clamp(0.0, 1.0);
    final standby = .3 + .1 * math.sin(now * 1.3);
    final regions = <(Rect, double)>[];
    final blocks = _blocks;
    final (workFrom, workCount) = chipDieWorkRange(scene._dieColumns);
    for (var i = 0; i < blocks.length; i++) {
      final activity = .8 + .2 * math.sin(now * (1.5 + i * .31) + i * 2.1);
      final j = i - workFrom;
      final receiving = j >= 0 && j < workCount;
      final s = receiving ? (f * (workCount + .5) - j).clamp(0.0, 1.0) : 1.0;
      final idle = (receiving ? standby * activity : (.4 + .2 * (1 - f)) * activity) * alpha;
      regions.add((blocks[i], idle));
      if (receiving && s > 0 && s < 1) {
        final r = blocks[i];
        regions.add((Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * s), .9 * alpha));
        c.drawLine(
          Offset(r.left + 1, r.top + r.height * s),
          Offset(r.right - 1, r.top + r.height * s),
          Paint()
            ..strokeWidth = 1.2
            ..color = ScanPalette.white.withValues(alpha: .85 * alpha),
        );
      } else if (receiving && s >= 1 && f < 1) {
        regions.add((blocks[i], .6 * alpha));
      }
    }
    paintChipDieLit(c, _photoBox, scene._dieColumns, regions, color);
    if (f < 1) _busUp(now, f, color, alpha);
    if (kind != 0) _memoryWeights(now, f, color, alpha);
  }

  /// The corners of a square, like the frame of a viewfinder.
  void _brackets(Rect r, double alpha, bool small, {Color color = ScanPalette.white}) {
    if (alpha <= .01) return;
    final len = r.width * .15;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 1.4 : 2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final corner = Offset(sx < 0 ? r.left : r.right, sy < 0 ? r.top : r.bottom);
        _c.drawPath(
          Path()
            ..moveTo(corner.dx - sx * len, corner.dy)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx, corner.dy - sy * len),
          p,
        );
      }
    }
  }

  /// Nothing to show yet: the frame waits or, while the folder is still being walked, looks for photos. The bus
  /// carries the vectors down into memory as the pictures land, and the photos are read side by side, each starting a
  /// little after the one before.
  void _index(double now) {
    _queueStrip(now);

    final shot = scene._shot;
    if (shot == null) {
      if (indeterminate) {
        _discovering(now, scene.widget.discovered);
      } else {
        _waiting(now, ScanPalette.glow, _ease(_seg(now - scene._idleSince, .3, .9)));
      }
      return;
    }
    final n = shot.pics.length;
    final t = scene._still ? .6 : ((now - shot.start) / shot.cycle).clamp(0.0, 1.0);
    final cells = _bentoCells(n, shot.layout);
    final stagger0 = n > 1 ? .05 : 0.0;
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      final u = ((t - stagger0 * i) / (1 - stagger0 * (n - 1))).clamp(0.0, 1.0);
      energy = math.max(energy, math.sin(math.pi * _seg(u, .85, .99)));
    }
    _bus(now, energy);
    final stagger = n > 1 ? .05 : 0.0;
    final span = 1 - stagger * (n - 1);
    for (var i = 0; i < n; i++) {
      final u = ((t - stagger * i) / span).clamp(0.0, 1.0);
      final frames = shot.frames[i];
      if (frames == null) {
        _readOne(shot.pics[i], cells[i], u, _tileRect(scene.landingX(i)), n > 1, now);
      } else {
        _burstOne(shot.pics[i], cells[i], u, _tileRect(scene.landingX(i)), n > 1, frames);
      }
    }
  }

  /// Where a photo of [aspect] sits whole inside [box].
  Rect _contain(double aspect, Rect box) {
    return aspect > box.width / box.height
        ? Rect.fromCenter(center: box.center, width: box.width, height: box.width / aspect)
        : Rect.fromCenter(center: box.center, width: box.height * aspect, height: box.height);
  }

  /// One photo of the round, the way the model reads it: the photo is shown whole and cut to its
  /// middle square (the model only sees a square), the square is cut into the 7 x 7 patches the
  /// model reads, each patch is boiled down to a single colour (a patch becomes one number
  /// vector), the patches look at each other (attention), and what comes out is one vector that
  /// goes down the bus into memory while the photo itself goes to the strip.
  void _readOne(_Pic pic, Rect cell, double t, Rect slot, bool small, double now) {
    final c = _c;
    final a = _ease(_seg(t, 0, .08));
    final whole = _contain(pic.w / pic.h, cell);
    final side = math.min(whole.width, whole.height);
    final crop = Rect.fromCenter(center: whole.center, width: side, height: side);
    final workSide = math.min(cell.width, cell.height);
    final work = Rect.fromCenter(center: cell.center, width: workSide, height: workSide);
    final cut = _ease(_seg(t, .17, .27));
    final grow = _ease(_seg(t, .25, .37));
    final q = _ease(_seg(t, .88, .99));
    final square = Rect.lerp(Rect.lerp(crop, work, grow)!, slot, q)!;
    final radius = _lerp(small ? 5 : 7, 6, q);
    final squareShape = RRect.fromRectAndRadius(square, Radius.circular(radius));
    final plain = _imagePaint(a);

    if (cut < 1) {
      final dim = _ease(_seg(t, .08, .17));
      c.save();
      c.clipRect(crop, clipOp: ui.ClipOp.difference);
      c.clipRRect(RRect.fromRectAndRadius(whole, Radius.circular(radius)));
      c.drawImageRect(pic.image, Rect.fromLTWH(0, 0, pic.w, pic.h), whole, _imagePaint(a * (1 - cut)));
      c.drawRect(whole, Paint()..color = ScanPalette.black.withValues(alpha: .55 * dim * (1 - cut) * a));
      c.restore();
    }
    c.save();
    c.clipRRect(squareShape);
    c.drawImageRect(pic.image, _coverSrc(pic, 1), square, plain);
    c.restore();

    final overlay = 1 - _ease(_seg(q, .5, 1));
    if (overlay <= .01) return;
    _brackets(square, _ease(_seg(t, .08, .17)) * (1 - _ease(_seg(t, .34, .42))) * overlay, small);

    final split = _ease(_seg(t, .36, .46)) * (1 - _ease(_seg(t, .78, .88)));
    final read = _seg(t, .46, .68) * 49;
    final mosaic = 1 - _ease(_seg(t, .76, .86));
    final tones = pic.tones;
    final cw = square.width / 7;
    if (split > .01 || (read > 0 && mosaic > .01)) {
      final src = _coverSrc(pic, 1);
      final sw = src.width / 7;
      final gap = split * (small ? .6 : 1);
      c.save();
      c.clipRRect(squareShape);
      c.drawRect(square, Paint()..color = ScanPalette.mint950.withValues(alpha: .55 * split * a * overlay));
      final tint = Paint();
      for (var k = 0; k < 49; k++) {
        final r = Rect.fromLTWH(square.left + (k % 7) * cw, square.top + (k ~/ 7) * cw, cw, cw);
        final inner = r.deflate(gap);
        c.drawImageRect(
          pic.image,
          Rect.fromLTWH(src.left + (k % 7) * sw, src.top + (k ~/ 7) * sw, sw, sw),
          inner,
          _imagePaint(a * overlay),
        );
        if (k < read) {
          final fresh = (1 - (read - k) / 6).clamp(0.0, 1.0);
          final base = tones?[k] ?? AppColors.primary;
          tint.color = Color.lerp(base, ScanPalette.white, fresh * .55)!.withValues(alpha: (mosaic * a * overlay).clamp(0.0, 1.0));
          c.drawRect(inner, tint);
        }
      }
      if (read > 0 && read < 49 && overlay > .3) {
        final k = read.floor();
        c.drawRect(
          Rect.fromLTWH(square.left, square.top + (k ~/ 7) * cw, square.width, cw),
          Paint()..color = ScanPalette.white.withValues(alpha: .1 * overlay),
        );
        c.drawRect(
          Rect.fromLTWH(square.left + (k % 7) * cw, square.top + (k ~/ 7) * cw, cw, cw).deflate(.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = small ? 1.2 : 2
            ..color = ScanPalette.white.withValues(alpha: overlay),
        );
      }
      c.restore();
    }

    final look = math.sin(math.pi * _seg(t, .64, .8));
    if (look > .02) {
      c.save();
      c.clipRRect(squareShape);
      final bucket = (now * 12).floor();
      final seed = pic.image.hashCode;
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = small ? .7 : 1
        ..color = ScanPalette.white.withValues(alpha: .6 * look * overlay);
      final dot = Paint()..color = ScanPalette.white.withValues(alpha: .9 * look * overlay);
      Offset center(int k) => Offset(square.left + (k % 7 + .5) * cw, square.top + (k ~/ 7 + .5) * cw);
      for (var j = 0; j < (small ? 7 : 12); j++) {
        final r = math.Random(seed ^ (bucket * 31 + j * 7919));
        final p = r.nextInt(49), o = r.nextInt(49);
        if (p == o) continue;
        final from = center(p), to = center(o);
        final control = Offset.lerp((from + to) / 2, square.center, .6)!;
        c.drawPath(Path()..moveTo(from.dx, from.dy)..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy), line);
        c.drawCircle(from, small ? 1.1 : 1.6, dot);
        c.drawCircle(to, small ? 1.1 : 1.6, dot);
      }
      c.restore();
    }

    final vector = _ease(_seg(t, .72, .8));
    if (vector > .01) {
      final cols = small ? 3 : 4, rows = small ? 4 : 6;
      final panel = Rect.fromLTWH(
        square.left + square.width * .06,
        square.bottom - square.height * .5 - square.height * .04,
        square.width * .88,
        square.height * .5,
      );
      final fontSize = math.max(4.6, square.width * (small ? .055 : .05));
      final fade = (vector * overlay).clamp(0.0, 1.0);
      c.save();
      c.clipRRect(squareShape);
      c.saveLayer(panel.inflate(4), Paint()..color = ScanPalette.white.withValues(alpha: fade));
      c.drawRRect(
        RRect.fromRectAndRadius(panel, Radius.circular(small ? 3 : 5)),
        Paint()..color = ScanPalette.black.withValues(alpha: .62),
      );
      final cellW = panel.width / cols, cellH = panel.height / rows;
      final n = cols * rows;
      final seed = pic.image.hashCode;
      final frame = (now * 16).floor();
      for (var i = 0; i < n; i++) {
        final lockAt = .76 + .11 * i / (n - 1);
        final centre = Offset(panel.left + (i % cols + .5) * cellW, panel.top + (i ~/ cols + .5) * cellH);
        if (t >= lockAt) {
          final just = t - lockAt < .025;
          _number(_signed(_vectorValue(tones, i)), centre, fontSize, just ? 2 : 1);
        } else {
          final v = (_hash(seed + i * 977 + frame * 131) % 1000) / 500 - 1;
          _number(_signed(v * .99), centre, fontSize, 0);
        }
      }
      c.restore();
      c.restore();
    }
  }

  /// One video of the round. A video comes in as a strip of film that rolls in and stops at a
  /// frame; its timeline ticks once for each frame taken (with a shutter flash on the picture),
  /// the frames fan out as a small deck, one sweep reads them all, and the deck snaps back into
  /// one tile with the video mark and the number of frames, which drops into the strip at the
  /// same moment a photo would. (The film and the deck show the one frame the app has, from
  /// slightly different angles.)
  void _burstOne(_Pic pic, Rect cell, double t, Rect slot, bool small, int frames) {
    final c = _c;
    final n = frames > 0 ? frames : 3;
    final a = _ease(_seg(t, 0, .08));
    final edge = small ? 5.0 : 9.0;
    final pad = small ? 2.0 : 6.0;
    final still = _contain(
      pic.w / pic.h,
      Rect.fromLTRB(cell.left + pad, cell.top + pad + edge, cell.right - pad, cell.bottom - pad - edge),
    );
    final pitch = still.width + (small ? 3 : 5);
    final whole = still.shift(Offset((1 - _ease(_seg(t, 0, .28))) * pitch * .4, 0));
    final workSide = math.min(cell.width, cell.height) * (small ? .8 : .74);
    final work = Rect.fromCenter(center: cell.center, width: workSide, height: workSide);
    final fan = _ease(_seg(t, .3, .48));
    final snap = _ease(_seg(t, .72, .86));
    final q = _ease(_seg(t, .88, .99));
    final front = Rect.lerp(Rect.lerp(whole, work, fan)!, slot, q)!;
    final radius = _lerp(small ? 5 : 7, 6, q);
    final frontShape = RRect.fromRectAndRadius(front, Radius.circular(radius));
    final overlay = 1 - _ease(_seg(q, .5, 1));
    final spread = fan * (1 - snap);

    final reading = math.sin(math.pi * _seg(t, .48, .74));
    final swept = _seg(t, .5, .7);

    // The film rolls with the frame and fades towards its ends, so it reads as film going on and not as copies of the
    // frame.
    final film = a * (1 - _ease(_seg(t, .3, .42))) * overlay;
    if (film > .01) {
      final reach = whole.width * (small ? .3 : .4);
      final strip = Rect.fromLTRB(
        math.max(cell.left, whole.left - reach),
        whole.top - edge,
        math.min(cell.right, whole.right + reach),
        whole.bottom + edge,
      );
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(cell, Radius.circular(small ? 5 : 7)));
      c.saveLayer(strip, Paint()..color = ScanPalette.white.withValues(alpha: film));
      c.clipRect(strip);
      c.drawRect(strip, Paint()..color = ScanPalette.black.withValues(alpha: .85));
      final dim = Paint()..color = ScanPalette.black.withValues(alpha: .5);
      for (final k in [-1, 1]) {
        final r = whole.shift(Offset(k * pitch, 0));
        final src = _coverSrc(pic, r.width / r.height, focus: Offset(.5 + k * .1, .5));
        c.drawImageRect(pic.image, src, r, _imagePaint(1));
        c.drawRect(r, dim);
      }
      final holeW = small ? 2.6 : 4.6, holeH = small ? 1.8 : 3.2;
      final step = small ? 6.0 : 10.0;
      final hole = Paint()..color = ScanPalette.white.withValues(alpha: .7);
      final first = whole.left - ((whole.left - strip.left) / step).ceil() * step;
      for (var x = first; x < strip.right; x += step) {
        for (final y in [whole.top - edge / 2, whole.bottom + edge / 2]) {
          c.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + step / 2, y), width: holeW, height: holeH), const Radius.circular(1)),
            hole,
          );
        }
      }
      final w = strip.width;
      c.drawRect(
        strip,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: [0, ((whole.left - strip.left) / w).clamp(0.0, 1.0), ((whole.right - strip.left) / w).clamp(0.0, 1.0), 1],
          ).createShader(strip),
      );
      c.restore();
      c.restore();
    }

    final deck = math.min(n, small ? 3 : 5) - 1;
    if (spread > .01) {
      for (var j = deck; j >= 1; j--) {
        final side = j.isOdd ? -1.0 : 1.0;
        final step = (j + 1) ~/ 2;
        final scale = 1 - .06 * step;
        final card = Rect.fromCenter(
          center: front.center + Offset(side * step * spread * front.width * .24, step * spread * 2),
          width: front.width * scale,
          height: front.height * scale,
        );
        c.save();
        c.translate(card.center.dx, card.center.dy);
        c.rotate(side * step * spread * .1);
        c.translate(-card.center.dx, -card.center.dy);
        final shape = RRect.fromRectAndRadius(card, Radius.circular(radius));
        c.save();
        c.clipRRect(shape);
        final src = _coverSrc(pic, card.width / card.height, focus: Offset(.5 + side * step * .12, .5 - step * .04));
        c.drawImageRect(pic.image, src, card, _imagePaint(a * spread));
        c.drawRect(card, Paint()..color = ScanPalette.black.withValues(alpha: (.18 + .1 * step) * spread * a));
        if (swept > 0) {
          c.drawRect(
            Rect.fromLTRB(card.left, card.top, card.right, card.top + card.height * swept),
            Paint()..color = ScanPalette.glow.withValues(alpha: .22 * reading * spread * a),
          );
        }
        c.restore();
        c.drawRRect(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = small ? 1 : 1.4
            ..color = ScanPalette.white.withValues(alpha: .7 * spread * a),
        );
        c.restore();
      }
    }

    final tick0 = .1, tickSpan = .2;
    var flash = 0.0;
    for (var j = 0; j < n; j++) {
      final at = tick0 + tickSpan * j / n;
      if (t >= at) flash = math.max(flash, 1 - _seg(t, at, at + .06));
    }
    c.save();
    if (t < .3) c.clipRect(cell);
    c.clipRRect(frontShape);
    c.drawImageRect(pic.image, _coverSrc(pic, front.width / front.height), front, _imagePaint(a));
    if (flash > .01) c.drawRect(front, Paint()..color = ScanPalette.white.withValues(alpha: .3 * flash * a * overlay));

    if (reading > .01 && overlay > .01) {
      final cw = front.width / 7, ch = front.height / 7;
      final rows = swept * 7;
      final tones = pic.tones;
      final tint = Paint();
      for (var k = 0; k < 49; k++) {
        if (k ~/ 7 >= rows) break;
        final base = tones?[k] ?? AppColors.primary;
        tint.color = base.withValues(alpha: (.55 * reading * a * overlay).clamp(0.0, 1.0));
        c.drawRect(Rect.fromLTWH(front.left + (k % 7) * cw, front.top + (k ~/ 7) * ch, cw, ch).deflate(.5), tint);
      }
      final grid = Paint()
        ..strokeWidth = .6
        ..color = ScanPalette.white.withValues(alpha: .35 * reading * overlay);
      for (var g = 1; g < 7; g++) {
        c.drawLine(Offset(front.left + g * cw, front.top), Offset(front.left + g * cw, front.bottom), grid);
        c.drawLine(Offset(front.left, front.top + g * ch), Offset(front.right, front.top + g * ch), grid);
      }
    }
    c.restore();
    if (reading > .01 && swept > 0 && swept < 1) {
      final reach = front.width * (.5 + spread * .24 * ((deck + 1) ~/ 2) + .04);
      final y = front.top + front.height * swept;
      c.drawLine(
        Offset(front.center.dx - reach, y),
        Offset(front.center.dx + reach, y),
        Paint()
          ..strokeWidth = small ? 1.2 : 1.8
          ..strokeCap = StrokeCap.round
          ..color = ScanPalette.white.withValues(alpha: .9 * reading * overlay),
      );
    }
    _brackets(front, _ease(_seg(t, .2, .26)) * (1 - _ease(_seg(t, .34, .4))) * overlay, small);

    final line = a * (1 - _ease(_seg(t, .3, .42))) * overlay;
    if (line > .01) {
      c.save();
      c.clipRect(cell);
      final bandH = small ? 8.0 : 13.0;
      final band = Rect.fromLTWH(front.left, front.bottom - bandH, front.width, bandH);
      c.save();
      c.clipRRect(frontShape);
      c.drawRect(band, Paint()..color = ScanPalette.black.withValues(alpha: .55 * line));
      c.restore();
      final pad = small ? 4.0 : 7.0;
      final y = band.center.dy;
      final x0 = band.left + pad, x1 = band.right - pad;
      c.drawLine(
        Offset(x0, y),
        Offset(x1, y),
        Paint()
          ..strokeWidth = small ? 1 : 1.4
          ..color = ScanPalette.white.withValues(alpha: .35 * line),
      );
      final tickH = small ? 2.4 : 3.6;
      for (var j = 0; j < n; j++) {
        final at = tick0 + tickSpan * j / n;
        final x = _lerp(x0, x1, (j + .5) / n);
        final lit = t >= at;
        final f = lit ? 1 - _seg(t, at, at + .06) : 0.0;
        if (f > .01) c.drawCircle(Offset(x, y), tickH * (1.2 + f), Paint()..color = ScanPalette.white.withValues(alpha: .45 * f * line));
        c.drawLine(
          Offset(x, y - tickH),
          Offset(x, y + tickH),
          Paint()
            ..strokeWidth = small ? 1.2 : 1.8
            ..strokeCap = StrokeCap.round
            ..color = (lit ? ScanPalette.glow : ScanPalette.white).withValues(alpha: (lit ? 1 : .45) * line),
        );
      }
      final head = _lerp(x0, x1, _seg(t, tick0, tick0 + tickSpan));
      c.drawLine(
        Offset(head, y - tickH - 1.5),
        Offset(head, y + tickH + 1.5),
        Paint()
          ..strokeWidth = small ? 1 : 1.4
          ..color = ScanPalette.white.withValues(alpha: line),
      );
      c.restore();
    }

    // The caption says what is happening, not how many frames: a small number would look like the video is only partly
    // read.
    final caption = a * (1 - snap) * overlay;
    if (!small && caption > .01) {
      _text(
        'READING FRAMES',
        Offset(front.center.dx, front.top + 10),
        8,
        ScanPalette.white.withValues(alpha: caption),
        weight: FontWeight.w700,
      );
    }

    final mark = a * snap;
    if (mark > .01) _videoMark(front, frames, mark);
  }

  static final Map<String, TextPainter> _numberText = {};

  /// A number of the vector, centred at [at]: [look] 0 is still flickering, 1 is locked, 2 is the
  /// flash as it locks.
  void _number(String text, Offset at, double size, int look) {
    final key = '$text|${size.toStringAsFixed(1)}|$look';
    var painter = _numberText[key];
    if (painter == null) {
      if (_numberText.length > 700) _numberText.clear();
      painter = _numberText[key] = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: size,
            fontWeight: FontWeight.w600,
            height: 1,
            color: switch (look) {
              0 => ScanPalette.white.withValues(alpha: .5),
              1 => ScanPalette.glow,
              _ => ScanPalette.white,
            },
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    painter.paint(_c, at - Offset(painter.width / 2, painter.height / 2));
  }

  static String _signed(double v) => '${v < 0 ? '-' : '+'}${v.abs().toStringAsFixed(2)}';

  Offset _slotCenter(int j) => Offset(_strip.left + 6 + 17 + (j + 1) * 38, _strip.top + 11 + 17);

  /// Lifted faces are shown the way the app really treats them: cut out as a square, straightened onto the standard
  /// 112 x 112 template, checked for how far the head is turned, and sent to the tray.
  void _faces(double now) {
    final c = _c;
    for (var j = 0; j < _traySlots; j++) {
      _bubble(j, now);
    }
    _memoryCells(now);
    _launching(now);

    final shot = scene._faceShot;
    if (shot == null) {
      _lookingForFaces(now);
      return;
    }
    final t = ((now - shot.start) / _faceCycle).clamp(0.0, 1.0);
    final dst = shot.dst;
    const area = _photoBox;
    final a = _ease(_seg(t, 0, .08)) * (1 - _ease(_seg(t, .92, .98)));
    Offset at(double fx, double fy) =>
        Offset(dst.left + fx * dst.width, dst.top + fy * dst.height);
    Rect boxOf(FaceEvent e) {
      final b = e.box;
      final p = at(b[0], b[1]), q = at(b[2], b[3]);
      return Rect.fromPoints(p, q);
    }

    double lift(int i) => _ease(_seg(t, .42 + .03 * i, .5 + .03 * i));

    if (a > 0.001) {
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(area, const Radius.circular(14)));
      c.drawImageRect(
        shot.pic.image,
        Rect.fromLTWH(0, 0, shot.pic.w, shot.pic.h),
        dst,
        _imagePaint(a),
      );
      final dim = .5 * _ease(_seg(t, .12, .26));
      if (dim > 0) {
        final path = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(area);
        for (var i = 0; i < shot.faces.length; i++) {
          if (lift(i) < .5) {
            path.addRRect(
              RRect.fromRectAndRadius(
                boxOf(shot.faces[i].event).inflate(4),
                const Radius.circular(10),
              ),
            );
          }
        }
        c.drawPath(
          path,
          Paint()..color = ScanPalette.indigo850.withValues(alpha: dim * a),
        );
      }
      for (var i = 0; i < shot.faces.length; i++) {
        final e = shot.faces[i].event;
        final box = boxOf(e).inflate(3);
        final l = lift(i);
        final centre = box.center;
        final rad = math.max(box.width, box.height) * .7;
        if (l > 0) {
          c.drawCircle(
            centre,
            rad,
            Paint()
              ..shader = ui.Gradient.radial(centre, rad, [
                ScanPalette.blue500.withValues(alpha: .97 * l * a),
                ScanPalette.blue500.withValues(alpha: .95 * l * a),
                ScanPalette.blue500.withValues(alpha: 0),
              ], [0, .72, 1]),
          );
        }
        final bp = _ease(_seg(t, .1 + .05 * i, .24 + .05 * i));
        if (bp > 0 && l < .5) {
          final al = (1 - l * 2) * a;
          final len = math.min(box.width, box.height) * .3 * bp + 3;
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..color = ScanPalette.white.withValues(alpha: al);
          for (final corner in [
            (box.topLeft, 1.0, 1.0),
            (box.topRight, -1.0, 1.0),
            (box.bottomLeft, 1.0, -1.0),
            (box.bottomRight, -1.0, -1.0),
          ]) {
            final p = corner.$1;
            c.drawPath(
              Path()
                ..moveTo(p.dx + corner.$2 * len, p.dy)
                ..lineTo(p.dx, p.dy)
                ..lineTo(p.dx, p.dy + corner.$3 * len),
              stroke,
            );
          }
          final la = _ease(_seg(t, .2 + .05 * i, .27 + .05 * i));
          final pill = RRect.fromRectAndRadius(
            Rect.fromLTWH(box.left, box.top - 17, 32, 14),
            const Radius.circular(7),
          );
          c.drawRRect(
            pill,
            Paint()..color = AppColors.faceAccent.withValues(alpha: al * la),
          );
          if (al * la > .01) {
            _text(
              e.score.toStringAsFixed(2),
              pill.outerRect.center,
              9,
              ScanPalette.white.withValues(alpha: al * la),
            );
          }
          if (e.landmarks.length >= 10) {
            _mesh(e, at, _ease(_seg(t, .33 + .03 * i, .42 + .03 * i)), al);
            for (var j = 0; j < 5; j++) {
              final s = _back(_seg(t, .27 + j * .014 + .03 * i, .32 + j * .014 + .03 * i));
              if (s <= 0) continue;
              final p = at(e.landmarks[j * 2], e.landmarks[j * 2 + 1]);
              final r = 2.6 * math.max(0.0, s);
              c.drawCircle(p, r, Paint()..color = ScanPalette.white.withValues(alpha: al));
              c.drawCircle(
                p,
                r,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.6
                  ..color = AppColors.faceAccent.withValues(alpha: al),
              );
            }
          }
        }
      }
      c.restore();
    }

    for (var i = 0; i < shot.faces.length; i++) {
      final face = shot.faces[i];
      final e = face.event;
      final l = lift(i);
      if (l <= 0) continue;
      final box = boxOf(e);
      final tr = _ease(_seg(t, .68 + .03 * i, .84 + .03 * i));
      if (tr > .97) continue;
      final end = _slotCenter(face.slot);
      final start = box.center;
      final pos = Offset(
        _lerp(start.dx, end.dx, tr),
        _lerp(start.dy, end.dy, tr) - math.sin(tr * math.pi) * 24,
      );
      final baseR = (math.max(box.width, box.height) / 2 * 1.05).clamp(12.0, 46.0);
      final full = (baseR * 2.3).clamp(52.0, 92.0);
      final side = _lerp(_lerp(baseR * 2, full, l), 31.0, tr);
      if (face.matched && tr > 0 && tr < 1) {
        _dashed(pos, end, AppColors.faceAccent.withValues(alpha: .55 * math.sin(tr * math.pi)));
      }
      _alignedFace(
        shot.pic,
        e,
        pos,
        side,
        l: l,
        straighten: _ease(_seg(t, .5 + .03 * i, .62 + .03 * i)),
        gauge: _ease(_seg(t, .56 + .03 * i, .62 + .03 * i)),
        needle: _ease(_seg(t, .6 + .03 * i, .68 + .03 * i)),
        travel: tr,
      );
    }
  }

  /// ArcFace's reference landmarks on a 112 x 112 face (what the app's FaceAligner moves every
  /// face onto): left eye, right eye, nose tip, left and right mouth corner.
  static const List<Offset> _template = [
    Offset(38.2946, 51.6963),
    Offset(73.5318, 51.5014),
    Offset(56.0252, 71.7366),
    Offset(41.5493, 92.3655),
    Offset(70.7299, 92.2041),
  ];

  /// How far the nose sits off the line between the eyes, as a fraction of the eye distance and
  /// signed (the app's FaceQuality.yaw, which only keeps its size): about 0 facing the camera, 0.3
  /// at 45 degrees, 0.6 or more in profile. Faces turned more than 0.55 are not matched.
  static double _signedYaw(List<Offset> lm) {
    final d = lm[1] - lm[0];
    final eye = d.distance;
    if (eye <= 0) return 1;
    final mid = (lm[0] + lm[1]) / 2;
    final offset = ((lm[2].dx - mid.dx) * d.dx + (lm[2].dy - mid.dy) * d.dy) / eye;
    return offset / eye;
  }

  /// One face in its square frame of [side] centred at [centre]. [straighten] (0..1) turns it from the plain crop onto
  /// the template, by the same least-squares rotate, scale and shift the app's FaceAligner uses. [gauge] reveals the
  /// head-turn gauge under it, which runs from -1 to +1 as a fraction of the eye distance with the accepted turn in
  /// violet, and [needle] swings its needle to this face's turn. [travel] rounds the square into a circle as it goes
  /// to the tray.
  void _alignedFace(
    _Pic pic,
    FaceEvent e,
    Offset centre,
    double side, {
    required double l,
    required double straighten,
    required double gauge,
    required double needle,
    required double travel,
  }) {
    final c = _c;
    final k = side / 112;
    final frame = Rect.fromCenter(center: centre, width: side, height: side);
    final shape = RRect.fromRectAndRadius(frame, Radius.circular(_lerp(5, side / 2, travel)));
    final calm = 1 - travel;
    c.drawRRect(shape.shift(const Offset(0, 2)).inflate(1), Paint()..color = ScanPalette.indigo800.withValues(alpha: .22 * calm));
    c.drawRRect(shape.shift(const Offset(0, 4)).inflate(2), Paint()..color = ScanPalette.indigo800.withValues(alpha: .1 * calm));
    c.drawRRect(shape, Paint()..color = ScanPalette.indigo850);

    final lm = [
      for (var j = 0; j < 5; j++) Offset(e.landmarks[j * 2] * pic.w, e.landmarks[j * 2 + 1] * pic.h),
    ];
    var smx = 0.0, smy = 0.0, dmx = 0.0, dmy = 0.0;
    for (var j = 0; j < 5; j++) {
      smx += lm[j].dx;
      smy += lm[j].dy;
      dmx += _template[j].dx * k;
      dmy += _template[j].dy * k;
    }
    smx /= 5;
    smy /= 5;
    dmx /= 5;
    dmy /= 5;
    var dot = 0.0, cross = 0.0, norm = 0.0;
    for (var j = 0; j < 5; j++) {
      final sx = lm[j].dx - smx, sy = lm[j].dy - smy;
      final dx = _template[j].dx * k - dmx, dy = _template[j].dy * k - dmy;
      dot += sx * dx + sy * dy;
      cross += sx * dy - sy * dx;
      norm += sx * sx + sy * sy;
    }
    final a = norm > 0 ? dot / norm : 1.0, b = norm > 0 ? cross / norm : 0.0;
    final scaleEnd = math.max(math.sqrt(a * a + b * b), 1e-3), angleEnd = math.atan2(b, a);

    final crop = _faceCrop(pic, e);
    final scaleStart = side / crop.width;
    final centreStart = (Offset(smx, smy) - crop.center) * scaleStart + Offset(side / 2, side / 2);
    final scale = scaleStart * math.pow(scaleEnd / scaleStart, straighten);
    final angle = angleEnd * straighten;
    final at = Offset.lerp(centreStart, Offset(dmx, dmy), straighten)!;

    c.save();
    c.clipRRect(shape);
    c.translate(frame.left + at.dx, frame.top + at.dy);
    c.rotate(angle);
    c.scale(scale.toDouble());
    c.translate(-smx, -smy);
    c.drawImage(pic.image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    c.restore();

    final shown = (l * (1 - travel * 2)).clamp(0.0, 1.0);
    if (shown > .01) {
      c.save();
      c.clipRRect(shape);
      c.drawLine(
        Offset(frame.left, frame.top + _template[0].dy * k),
        Offset(frame.right, frame.top + _template[0].dy * k),
        Paint()
          ..strokeWidth = .8
          ..color = ScanPalette.white.withValues(alpha: .4 * shown),
      );
      final locked = _seg(straighten, .88, 1);
      final mark = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.faceAccent.withValues(alpha: shown);
      final dotPaint = Paint();
      final turn = Offset(math.cos(angle), math.sin(angle)) * scale.toDouble();
      for (var j = 0; j < 5; j++) {
        final target = frame.topLeft + _template[j] * k;
        c.drawCircle(target, 2.6, mark);
        if (locked > 0) {
          c.drawCircle(target, 2.6 * locked, dotPaint..color = ScanPalette.white.withValues(alpha: .9 * locked * shown));
        }
        final d = lm[j] - Offset(smx, smy);
        final p = frame.topLeft + at + Offset(d.dx * turn.dx - d.dy * turn.dy, d.dx * turn.dy + d.dy * turn.dx);
        c.drawCircle(p, 1.7, dotPaint..color = ScanPalette.white.withValues(alpha: shown));
        c.drawCircle(p, 1.7, mark..strokeWidth = 1.2);
      }
      c.restore();
    }
    c.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ScanPalette.white.withValues(alpha: .95),
    );

    final gaugeShown = gauge * (1 - travel * 2).clamp(0.0, 1.0);
    if (gaugeShown > .01) {
      final half = side * .46 * gauge;
      final y = frame.bottom + 7;
      final yaw = _signedYaw(lm).clamp(-1.0, 1.0);
      final centreX = centre.dx;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(centreX - half, y, centreX + half, y + 4), const Radius.circular(2)),
        Paint()..color = ScanPalette.white.withValues(alpha: .28 * gaugeShown),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(centreX - half * .55, y, centreX + half * .55, y + 4), const Radius.circular(2)),
        Paint()..color = AppColors.faceAccent.withValues(alpha: .9 * gaugeShown),
      );
      c.drawLine(
        Offset(centreX, y - 1),
        Offset(centreX, y + 5),
        Paint()
          ..strokeWidth = .8
          ..color = ScanPalette.white.withValues(alpha: .7 * gaugeShown),
      );
      final x = centreX + yaw * half * needle;
      c.drawPath(
        Path()
          ..moveTo(x, y + 4.6)
          ..lineTo(x - 2.6, y + 9.4)
          ..lineTo(x + 2.6, y + 9.4)
          ..close(),
        Paint()..color = ScanPalette.white.withValues(alpha: gaugeShown),
      );
    }
  }

  /// The 5 landmarks joined into a small mesh over the face, just before it is lifted out.
  void _mesh(FaceEvent e, Offset Function(double, double) at, double grow, double alpha) {
    if (grow <= 0) return;
    final c = _c;
    final p = [for (var j = 0; j < 5; j++) at(e.landmarks[j * 2], e.landmarks[j * 2 + 1])];
    final fill = Path()
      ..moveTo(p[0].dx, p[0].dy)
      ..lineTo(p[1].dx, p[1].dy)
      ..lineTo(p[2].dx, p[2].dy)
      ..close()
      ..moveTo(p[2].dx, p[2].dy)
      ..lineTo(p[3].dx, p[3].dy)
      ..lineTo(p[4].dx, p[4].dy)
      ..close();
    c.drawPath(fill, Paint()..color = AppColors.faceAccent.withValues(alpha: .22 * grow * alpha));
    final line = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = ScanPalette.white.withValues(alpha: .85 * alpha);
    for (final edge in const [
      [0, 1], [0, 2], [1, 2], [2, 3], [2, 4], [3, 4], [0, 3], [1, 4],
    ]) {
      c.drawLine(p[edge[0]], Offset.lerp(p[edge[0]], p[edge[1]], grow)!, line);
    }
  }

  /// The strip's photos rising into the square when a batch starts.
  void _launching(double now) {
    final tiles = scene._launch;
    if (tiles.isEmpty) return;
    final age = now - scene._launchAt;
    for (var i = 0; i < tiles.length; i++) {
      final u = _ease(_seg(age - i * .05, 0, .7));
      if (u >= 1) continue;
      final from = Rect.fromLTWH(tiles[i].x, _strip.top + 11, _tileSize, _tileSize);
      final to = _photoBox.center + Offset((i % 5 - 2) * 10.0, (i ~/ 5 - 1) * 8.0);
      final size = _tileSize * (1 - .55 * u);
      final rect = Rect.fromCenter(
        center: Offset.lerp(from.center, to, u)!,
        width: size,
        height: size,
      );
      _thumb(tiles[i].pic, rect, 1 - u);
      if (tiles[i].frames != null) _videoMark(rect, tiles[i].frames!, 1 - u);
    }
  }

  /// While no photo with faces is being shown: the batch's photos go by under a scan line.
  void _lookingForFaces(double now) {
    final history = scene._batchPics;
    if (history.isEmpty) {
      _waiting(now, AppColors.faceAccent, 1, kind: 1);
      return;
    }
    final pic = history[(now / 1.3).floor() % history.length];
    final dst = _photoBox;
    final f = (now / 1.3) % 1;
    final c = _c;
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(dst, const Radius.circular(14)));
    c.drawImageRect(
      pic.image,
      _coverSrc(pic, dst.width / dst.height),
      dst,
      _imagePaint(.55),
    );
    final y = dst.top + dst.height * f;
    c.drawRect(
      Rect.fromLTRB(dst.left, y - 18, dst.right, y),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, y - 18),
          Offset(0, y),
          [AppColors.faceAccent.withValues(alpha: 0), AppColors.faceAccent.withValues(alpha: .35)],
        ),
    );
    c.drawLine(
      Offset(dst.left, y),
      Offset(dst.right, y),
      Paint()
        ..strokeWidth = 2
        ..color = AppColors.faceAccent,
    );
    c.restore();
  }

  void _dashed(Offset from, Offset to, Color color) {
    final paint = Paint()
      ..strokeWidth = 1.6
      ..color = color;
    final d = to - from;
    final n = (d.distance / 8).floor();
    for (var k = 0; k < n; k += 2) {
      _c.drawLine(from + d * (k / n), from + d * ((k + 1) / n), paint);
    }
  }

  void _crop(_Pic pic, Rect src, Offset center, double r, double alpha) {
    final c = _c;
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    c.drawImageRect(pic.image, src, Rect.fromCircle(center: center, radius: r), _imagePaint(alpha));
    c.restore();
  }

  void _bubble(int j, double now) {
    final c = _c;
    final centre = _slotCenter(j);
    final p = scene._tray[j];
    if (p == null) {
      c.drawCircle(
        centre,
        16.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = ScanPalette.white.withValues(alpha: .2),
      );
      return;
    }
    final age = now - p.bornAt;
    final pop = p.isNew || age < .4 ? math.max(.01, _back(_seg(age, 0, .4))) : 1.0;
    c.save();
    c.translate(centre.dx, centre.dy);
    c.scale(pop);
    c.translate(-centre.dx, -centre.dy);
    c.drawCircle(centre, 17, Paint()..color = ScanPalette.white);
    _crop(p.pic, p.src, centre, 15.5, 1);
    c.restore();
    final pulse = _seg(now - p.pulseAt, 0, .7);
    if (pulse > 0 && pulse < 1) {
      c.drawCircle(
        centre,
        17 + 11 * _ease(pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppColors.faceAccent.withValues(alpha: (1 - pulse) * .9),
      );
    }
    final badge = centre + const Offset(12.5, 12.5);
    c.drawCircle(badge, 7.2, Paint()..color = AppColors.faceAccent);
    c.drawCircle(
      badge,
      7.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ScanPalette.white,
    );
    _text('${p.count}', badge, p.count > 99 ? 6.5 : 8.5, ScanPalette.white);
    if (p.isNew && age < 3) {
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(centre.dx - 4, centre.dy + 8, 22, 12),
        const Radius.circular(6),
      );
      final fade = 1 - _ease(_seg(age, 2.5, 3));
      c.drawRRect(pill, Paint()..color = AppColors.faceAccent.withValues(alpha: fade));
      _text('NEW', pill.outerRect.center, 8, ScanPalette.white.withValues(alpha: fade));
    }
  }

  /// The painter reads the hero's state as well as its own fields (the press, the lid's text, the
  /// core count...), and is only made again when the hero is built, which is when one of them
  /// may have changed: so it always repaints (the frame was going to be drawn anyway).
  @override
  bool shouldRepaint(_SquarePainter old) => true;
}

/// The square is drawn on a 340 x 340 sheet that is scaled to fit.
const double _sheet = 340;

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

double _ease(double x) => 1 - math.pow(1 - x, 3).toDouble();

double _back(double x) {
  const c = 1.70158;
  return 1 + (c + 1) * math.pow(x - 1, 3) + c * math.pow(x - 1, 2);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

List<Rect> _bentoCells(int n, int layout) {
  final templates = _bentoLayouts[n.clamp(1, 6)];
  final template = templates[layout % templates.length];
  const b = _photoBox;
  return [
    for (final f in template)
      Rect.fromLTWH(
        b.left + f.left * b.width,
        b.top + f.top * b.height,
        f.width * b.width,
        f.height * b.height,
      ).deflate(3),
  ];
}

/// The part of [pic] that fills a box of [aspect] (width / height) without stretching it: as
/// much of the photo as fits, cut to that shape around [focus] (fractions of the photo).
Rect _coverSrc(_Pic pic, double aspect, {Offset focus = const Offset(.5, .5)}) {
  if (!aspect.isFinite || aspect <= 0) return Rect.fromLTWH(0, 0, pic.w, pic.h);
  final double w, h;
  if (pic.w / pic.h > aspect) {
    h = pic.h;
    w = h * aspect;
  } else {
    w = pic.w;
    h = w / aspect;
  }
  return Rect.fromLTWH(
    (focus.dx * pic.w - w / 2).clamp(0.0, pic.w - w),
    (focus.dy * pic.h - h / 2).clamp(0.0, pic.h - h),
    w,
    h,
  );
}

/// Number [i] of a photo's vector (-1..1): derived from the photo's own colours, so each photo
/// gets its own list. (Illustrative: the real vector is made by the model, not by the screen.)
double _vectorValue(List<Color>? tones, int i) {
  final tone = tones == null ? ScanPalette.gray500 : tones[(i * 7) % 49];
  final v = math.sin((tone.r * 12.9898 + tone.g * 78.233 + tone.b * 37.719) * (i + 1) * 3.1) * 43758.5453;
  return ((v - v.floorToDouble()) * 2 - 1) * .98;
}
