part of '../chip_art.dart';

/// One layer of the die: its blocks and what is in them. It is drawn dark, as the chip is, and once more in white with
/// no backing, to be lit block by block as the chip works (see [paintChipDieLit]). A core is laid out as in a real
/// out-of-order core: front end on the left, then the execution core, the vector unit, and the load/store unit with
/// the data cache, with the level-2 cache along one edge. Every core is the same macro placed again, the bottom row
/// turned over and every other core mirrored, so their caches and buses meet. The shared cache, the fabric, the memory
/// controller and the outside interfaces fill the rest.
void _drawDieLayer(Canvas canvas, Rect area, int perRow, {required bool lit}) {
  final l = _DieLayout(area, perRow);
  final ink = ChipPalette.white.withValues(alpha: lit ? .8 : .11);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .8
    ..color = ChipPalette.white.withValues(alpha: lit ? .5 : .2);
  final hair = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .5
    ..color = ChipPalette.white.withValues(alpha: lit ? .32 : .1);
  final warm = Paint()..color = lit ? ChipPalette.white.withValues(alpha: .8) : ChipPalette.gold400.withValues(alpha: .35);

  void block(Rect r, [double radius = 3.5]) {
    final shape = RRect.fromRectAndRadius(r, Radius.circular(radius));
    if (!lit) canvas.drawRRect(shape, Paint()..color = ChipPalette.black.withValues(alpha: .22));
    canvas.drawRRect(shape, line);
  }

  void unit(Rect r) => canvas.drawRect(r, hair);

  void core(Rect r, {required bool flipX, required bool flipY}) {
    canvas.save();
    if (flipX) {
      canvas.translate(r.center.dx * 2, 0);
      canvas.scale(-1, 1);
    }
    if (flipY) {
      canvas.translate(0, r.center.dy * 2);
      canvas.scale(1, -1);
    }
    block(r);
    const g = 1.5;
    final iw = r.width - 4 - 3 * g;
    final widths = [iw * .27, iw * .38, iw * .18, iw * .17];
    final xs = <double>[];
    var x = r.left + 2;
    for (final w in widths) {
      xs.add(x);
      x += w + g;
    }
    final top = r.top + 2;
    final l1i = Rect.fromLTWH(xs[0], top, widths[0], 11);
    final bpu = Rect.fromLTWH(xs[0], top + 11.5, widths[0], 7);
    final decode = Rect.fromLTWH(xs[0], top + 19, widths[0], 16);
    _sramTexture(canvas, l1i, ink);
    _sramTexture(canvas, bpu, ink);
    _logicTexture(canvas, decode, ink, 31, pitch: 2.2, rowH: 1.5);
    final rob = Rect.fromLTWH(xs[1], top, widths[1], 8.5);
    final sched = Rect.fromLTWH(xs[1], top + 9, widths[1], 7.5);
    final irf = Rect.fromLTWH(xs[1], top + 17, widths[1], 8);
    final alu = Rect.fromLTWH(xs[1], top + 25.5, widths[1], 9.5);
    _registerTexture(canvas, rob, ink);
    _logicTexture(canvas, sched, ink, 41, pitch: 2.2, rowH: 1.5);
    _registerTexture(canvas, irf, ink);
    _datapathTexture(canvas, alu, ink);
    final vsched = Rect.fromLTWH(xs[2], top, widths[2], 7);
    final vec = Rect.fromLTWH(xs[2], top + 7.5, widths[2], 17);
    final vrf = Rect.fromLTWH(xs[2], top + 25, widths[2], 10);
    _logicTexture(canvas, vsched, ink, 51, pitch: 2.1, rowH: 1.4);
    _datapathTexture(canvas, vec, ink);
    _registerTexture(canvas, vrf, ink);
    final l1d = Rect.fromLTWH(xs[3], top, widths[3], 14);
    final lsu = Rect.fromLTWH(xs[3], top + 14.5, widths[3], 11);
    final tlb = Rect.fromLTWH(xs[3], top + 26, widths[3], 9);
    _sramTexture(canvas, l1d, ink);
    _logicTexture(canvas, lsu, ink, 61, pitch: 2.2, rowH: 1.5);
    _registerTexture(canvas, tlb, ink);
    for (final u in [l1i, bpu, decode, rob, sched, irf, alu, vsched, vec, vrf, l1d, lsu, tlb]) {
      unit(u);
    }
    final l2 = Rect.fromLTWH(r.left + 2, r.bottom - 15, r.width - 4, 13);
    _sramTexture(canvas, l2, ink);
    unit(l2);
    canvas.drawCircle(Offset(r.center.dx, r.top + 1), .9, warm);
    canvas.restore();
  }

  for (var i = 0; i < l.cores.length; i++) {
    final column = i % perRow;
    core(l.cores[i], flipX: column.isOdd, flipY: i >= perRow);
  }

  for (final r in l.l3) {
    block(r, 3);
    final upper = Rect.fromLTWH(r.left + 2, r.top + 1.5, r.width - 4, 10);
    final tags = Rect.fromLTWH(r.left + 2, r.top + 12, r.width - 4, 3);
    final lower = Rect.fromLTWH(r.left + 2, r.top + 15.5, r.width - 4, 9.5);
    _sramTexture(canvas, upper, ink);
    _logicTexture(canvas, tags, ink, 71, pitch: 1.6, rowH: 1.1);
    _sramTexture(canvas, lower, ink);
  }

  final routers = [for (final r in l.l3) r.center.dx];
  block(l.fabricTop, 1.5);
  _fabricTexture(canvas, l.fabricTop, ink, 81, routers);
  block(l.fabricBottom, 1.5);
  _fabricTexture(canvas, l.fabricBottom, ink, 81, routers);

  block(l.mc);
  final mcBuffer = Rect.fromLTWH(l.mc.left + 2, l.mc.top + 1.5, 26, l.mc.height - 3);
  final mcSched = Rect.fromLTWH(l.mc.left + 29.5, l.mc.top + 1.5, 36, l.mc.height - 3);
  final mcRegs = Rect.fromLTWH(l.mc.left + 67, l.mc.top + 1.5, 24, l.mc.height - 3);
  final mcEcc = Rect.fromLTWH(l.mc.left + 92.5, l.mc.top + 1.5, l.mc.width - 94.5, l.mc.height - 3);
  _sramTexture(canvas, mcBuffer, ink);
  _logicTexture(canvas, mcSched, ink, 91, pitch: 2.2, rowH: 1.5);
  _registerTexture(canvas, mcRegs, ink);
  _logicTexture(canvas, mcEcc, ink, 92, pitch: 2.2, rowH: 1.5);
  for (final u in [mcBuffer, mcSched, mcRegs, mcEcc]) {
    unit(u);
  }
  block(l.phy);
  _phyTexture(canvas, Rect.fromLTWH(l.phy.left + 2, l.phy.top + 1, l.phy.width - 4, 8.5), ink);
  for (var k = 0; k < 14; k++) {
    canvas.drawCircle(Offset(l.phy.left + 9 + k * 8.2, l.phy.bottom - 3.8), 1.5, warm);
  }

  block(l.io);
  _logicTexture(canvas, Rect.fromLTWH(l.io.left + 2, l.io.top + 1.5, l.io.width - 4, 8), ink, 101, pitch: 2.2, rowH: 1.5);
  _phyTexture(canvas, Rect.fromLTWH(l.io.left + 2, l.io.top + 11, l.io.width - 4, 12), ink);
  for (var k = 0; k < 6; k++) {
    canvas.drawCircle(Offset(l.io.left + 6 + k * 8.2, l.io.bottom - 4), 1.5, warm);
  }
  block(l.media);
  _datapathTexture(canvas, Rect.fromLTWH(l.media.left + 2, l.media.top + 1.5, l.media.width - 4, 14), ink);
  _logicTexture(canvas, Rect.fromLTWH(l.media.left + 2, l.media.top + 16.5, l.media.width - 4, 6), ink, 111, pitch: 2.1, rowH: 1.4);
  _sramTexture(canvas, Rect.fromLTWH(l.media.left + 2, l.media.top + 23.5, l.media.width - 4, 7), ink);
  block(l.pll, 2.5);
  _pllTexture(canvas, l.pll.deflate(.5), ink, 121);
  block(l.pmu, 2.5);
  _logicTexture(canvas, Rect.fromLTWH(l.pmu.left + 2, l.pmu.top + 1.5, 13, l.pmu.height - 3), ink, 131, pitch: 2.2, rowH: 1.5);
  final switches = Paint()..color = ink.withValues(alpha: ink.a * .8);
  for (var y = l.pmu.top + 2; y + 1.6 < l.pmu.bottom - 1; y += 2.6) {
    canvas.drawRect(Rect.fromLTWH(l.pmu.left + 16.5, y, l.pmu.width - 18.5, 1.6), switches);
  }

  if (!lit) {
    final channel = Paint()
      ..strokeWidth = .5
      ..color = ChipPalette.white.withValues(alpha: .07);
    for (var c = 0; c < perRow - 1; c++) {
      final x = area.left + 12 + (c + 1) * l.columnWidth + c * l.columnGap + l.columnGap / 2;
      canvas.drawLine(Offset(x, area.top + 12), Offset(x, area.top + 158), channel);
    }
    final spine = Paint()
      ..strokeWidth = .8
      ..color = ChipPalette.white.withValues(alpha: .12);
    canvas.drawLine(Offset(area.left + 6, area.top + 160.5), Offset(area.right - 6, area.top + 160.5), spine);
  }
}

/// Memory (caches, tables): bit cells in a fine regular grid, cut into mats. Each mat has its row decoder down the
/// left and, under it, a row of sense amplifiers, which are wider than the cells.
void _sramTexture(Canvas c, Rect r, Color ink) {
  final cell = Paint()..color = ink;
  final periphery = Paint()..color = ink.withValues(alpha: ink.a * .75);
  const pitch = 2.2;
  final mats = math.max(1, (r.width / 26).round());
  final matW = r.width / mats;
  final sense = r.height >= 9 ? 2.6 : 0.0;
  final rows = ((r.height - sense - 1) / pitch).floor();
  for (var m = 0; m < mats; m++) {
    final left = r.left + m * matW;
    for (var row = 0; row < rows; row++) {
      c.drawRect(Rect.fromLTWH(left + .5, r.top + .8 + row * pitch, 1.7, 1.0), periphery);
    }
    for (var x = left + 3.2; x + 1.3 < left + matW - .6; x += pitch) {
      for (var row = 0; row < rows; row++) {
        c.drawRect(Rect.fromLTWH(x, r.top + .8 + row * pitch, 1.3, 1.3), cell);
      }
    }
    if (sense > 0) {
      for (var x = left + 3.2; x + 3 < left + matW - .6; x += pitch * 2) {
        c.drawRect(Rect.fromLTWH(x, r.bottom - sense + .2, 3.0, 1.6), periphery);
      }
    }
  }
}

/// Datapaths (ALUs, the vector unit). Unlike control logic these are laid out as bit slices, the same column
/// repeated once for every bit, with the wires of the buses running across them.
void _datapathTexture(Canvas c, Rect r, Color ink) {
  const rowAlpha = [.9, .5, 1.0, .65, .8, .45];
  final cell = Paint();
  for (var x = r.left + .9; x + 1.5 <= r.right - .6; x += 2.4) {
    var row = 0;
    for (var y = r.top + .9; y + 1.4 <= r.bottom - .5; y += 2.0) {
      cell.color = ink.withValues(alpha: ink.a * rowAlpha[row % rowAlpha.length]);
      c.drawRect(Rect.fromLTWH(x, y, 1.5, 1.4), cell);
      row++;
    }
  }
  final bus = Paint()
    ..strokeWidth = .4
    ..color = ink.withValues(alpha: ink.a * .55);
  for (var y = r.top + 2.2; y < r.bottom - 1; y += 6) {
    c.drawLine(Offset(r.left + .6, y), Offset(r.right - .6, y), bus);
  }
}

/// The interface to the outside (memory, storage, USB): the same slice repeated once per lane, a delay line on top
/// and a column of drivers under it, because it is one macro placed again and again.
void _phyTexture(Canvas c, Rect r, Color ink) {
  final lanes = math.max(1, (r.width / 13).floor());
  final laneW = r.width / lanes;
  final delay = Paint()..color = ink.withValues(alpha: ink.a * .7);
  final driver = Paint()..color = ink;
  final seam = Paint()
    ..strokeWidth = .4
    ..color = ink.withValues(alpha: ink.a * .5);
  for (var k = 0; k < lanes; k++) {
    final x = r.left + k * laneW;
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(x + .9 + i * 3.4, r.top + .8, 2.6, 2.2), delay);
      c.drawRect(Rect.fromLTWH(x + .9 + i * 3.4, r.top + 3.6, 2.6, r.height - 4.4), driver);
    }
    if (k > 0) c.drawLine(Offset(x, r.top + .6), Offset(x, r.bottom - .6), seam);
  }
}

/// The clock generator: an oscillator with a spiral inductor (turns of octagon), the capacitors of its loop filter
/// (an array of identical cells) and the divider logic.
void _pllTexture(Canvas c, Rect r, Color ink, int seed) {
  final centre = Offset(r.left + r.height * .55, r.center.dy);
  final turn = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .8
    ..color = ink;
  for (var k = 1; k <= 3; k++) {
    c.drawPath(_octagon(centre, k * r.height * .13 + .9), turn);
  }
  final left = r.left + r.height * 1.15;
  final caps = Rect.fromLTWH(left, r.top + 1.5, (r.right - left - 1.5) * .5, r.height - 3);
  _registerTexture(c, caps, ink);
  final divider = Rect.fromLTWH(caps.right + 1, r.top + 1.5, r.right - caps.right - 2.5, r.height - 3);
  _logicTexture(c, divider, ink, seed, pitch: 2.4, rowH: 1.7);
}

Path _octagon(Offset centre, double radius) {
  final path = Path();
  for (var k = 0; k < 8; k++) {
    final angle = math.pi / 8 + k * math.pi / 4;
    final p = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    if (k == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// Registers and queues (register files, reorder buffer, store buffer): multi-ported arrays, with bigger cells than
/// a cache's and read and write wires between the rows.
void _registerTexture(Canvas c, Rect r, Color ink) {
  final cell = Paint()..color = ink.withValues(alpha: ink.a * 1.3);
  final wire = Paint()
    ..strokeWidth = .4
    ..color = ink.withValues(alpha: ink.a * .5);
  for (var y = r.top + 1.2; y < r.bottom - 1; y += 3) {
    c.drawLine(Offset(r.left + .8, y + 1), Offset(r.right - .8, y + 1), wire);
    for (var x = r.left + 1.2; x < r.right - 2; x += 3) {
      c.drawRect(Rect.fromLTWH(x, y, 1.9, 1.9), cell);
    }
  }
}

/// The data fabric: bundles of parallel wires (the buses) with a router, a small block of logic, at the foot of each
/// column of cores.
void _fabricTexture(Canvas c, Rect r, Color ink, int seed, List<double> routers) {
  final wire = Paint()
    ..strokeWidth = .45
    ..color = ink.withValues(alpha: ink.a * .8);
  for (var k = 0; k < 3; k++) {
    final y = r.top + .8 + k * 1.2;
    c.drawLine(Offset(r.left + 1, y), Offset(r.right - 1, y), wire);
  }
  for (final x in routers) {
    _logicTexture(c, Rect.fromCenter(center: Offset(x, r.center.dy), width: 9, height: r.height - 1), ink, seed++, pitch: 1.4, rowH: 1.0, fill: .9);
  }
}

/// Control logic (decode, schedulers): rows of standard cells, each row a string of cells of different widths, so
/// it looks like placed and routed logic, not a pattern.
void _logicTexture(Canvas c, Rect r, Color ink, int seed, {double pitch = 2.6, double rowH = 2, double fill = .85}) {
  final rnd = math.Random(seed);
  final paint = Paint();
  for (var y = r.top + .9; y + rowH <= r.bottom - .4; y += pitch) {
    var x = r.left + .9;
    while (x < r.right - .9) {
      final len = 2.5 + rnd.nextDouble() * 11;
      final w = math.min(len, r.right - .9 - x);
      if (rnd.nextDouble() < fill) {
        paint.color = ink.withValues(alpha: ink.a * (.3 + .7 * rnd.nextDouble()));
        c.drawRect(Rect.fromLTWH(x, y, w, rowH), paint);
      }
      x += len + .55;
    }
  }
}

/// Lights parts of the die as if they were working: each of [regions] is a place on the die and
/// how brightly it shows (0..1), in [tint]. What is lit is the die's own structure (its memory
/// cells, logic rows, registers), so the light looks like it comes from inside the silicon.
void paintChipDieLit(Canvas canvas, Rect area, int perRow, List<(Rect, double)> regions, Color tint) {
  final art = _art('dieLit$perRow', area.inflate(8), (c) => _drawDieLayer(c, area, perRow, lit: true));
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..blendMode = BlendMode.plus;
  for (final (rect, level) in regions) {
    if (level <= .01) continue;
    paint.colorFilter = ColorFilter.mode(tint.withValues(alpha: level.clamp(0.0, 1.0)), BlendMode.modulate);
    // Only the block's own part of the picture (a block's frame is .8 wide, and the next block is
    // never closer than a unit).
    art.paintRegion(canvas, rect.inflate(.45), paint);
  }
}
