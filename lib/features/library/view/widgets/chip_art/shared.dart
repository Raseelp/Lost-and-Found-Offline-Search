part of '../chip_art.dart';

/// The size of the square sheet the Library page's processor is drawn on, from above. The chip is a green substrate
/// with gold contact pads along its edges, a pin 1 corner marker and retention notches, with the silicon die and a
/// memory bank joined by bond wires. While the chip is closed the steel heat spreader (the lid) covers it, drawn last,
/// and can slide off. Everything that does not change is drawn once into an image, so a frame only has to place a few
/// images.
const double chipSheet = 340;

/// The die and the memory bank are drawn at this scale about the middle of the chip, which
/// leaves the board a margin for the bond wires and the parts round them.
const double chipDieScale = .87;

final Map<String, _Art> _arts = {};

/// Pixels per sheet unit the pictures are made at: as many as the screen can show of the chip, so a phone with a
/// dense screen gets a sharper chip, but never fewer than 2 or more than 4.
double _artScale = 3;

/// Tells the chip how dense the screen is, so its pictures are made sharp enough for it (and
/// no larger). Call before the chip is first drawn; a change makes the pictures again.
void setChipArtScale(double devicePixelRatio) {
  final scale = ((devicePixelRatio * .94).clamp(2.0, 4.0) * 2).round() / 2;
  if (scale == _artScale) return;
  _artScale = scale;
  for (final art in _arts.values) {
    art.dispose();
  }
  _arts.clear();
}

/// Forgets and frees the pictures whose key starts with [prefix] except [keep], which are for a text or a core count
/// that is not shown any more.
void _evictOthers(String prefix, Set<String> keep) {
  final stale = [for (final key in _arts.keys) if (key.startsWith(prefix) && !keep.contains(key)) key];
  for (final key in stale) {
    _arts.remove(key)?.dispose();
  }
}

/// Makes the picture for [key] once. [draw] paints in sheet coordinates, and the result is rasterised at [scale]
/// pixels per unit and drawn as an image from then on. If the engine cannot make the image, the picture is drawn
/// instead.
_Art _art(String key, Rect bounds, void Function(Canvas canvas) draw, {double? scale}) {
  final pixels = scale ?? _artScale;
  return _arts.putIfAbsent(key, () {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder));
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      final raster = ui.PictureRecorder();
      final c = Canvas(raster);
      c.scale(pixels);
      c.translate(-bounds.left, -bounds.top);
      c.drawPicture(picture);
      image = raster.endRecording().toImageSync(
        (bounds.width * pixels).ceil(),
        (bounds.height * pixels).ceil(),
      );
    } catch (_) {
      image = null;
    }
    return _Art(bounds, picture, image);
  });
}

/// The wires from the die (top) and the memory bank (bottom) to the board: 27 along the top,
/// 27 along the bottom. The top ones are the CLIP indexing, the bottom ones the faces.
const int chipWireCount = 27;

double _wireX(int i) => 67 + i * 8.0;

double _dieX(double sheetX) => chipSheet / 2 + (sheetX - chipSheet / 2) / chipDieScale;

/// Where a wire starts on the die (top) or the bank (bottom), and where it ends on the board, in sheet coordinates.
const double _dieEdgeTop = 52.6;

const double _fingerTop = 42.6;

const double _fingerBottom = 298.6;

final List<List<Path>> _wirePaths = [
  for (var bar = 0; bar < 2; bar++) [for (var i = 0; i < chipWireCount; i++) _wirePath(bar, i)],
];

/// The path of wire [i] of [bar]. A wire is never quite straight: it leaves the pad, arches and settles.
Path _wirePath(int bar, int i) {
  final fan = (i - (chipWireCount - 1) / 2) * .3;
  final a = Offset(_wireX(i), bar == 0 ? _dieEdgeTop : _dieEdgeBottom);
  final b = Offset(_wireX(i) + fan, bar == 0 ? _fingerTop : _fingerBottom);
  final bow = 2.2 * math.sin(i * 1.9 + bar);
  final mid = Offset.lerp(a, b, .5)! + Offset(bow, 0);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
}

const double _dieEdgeBottom = 288.0;

final List<List<ui.PathMetric>> _wireMetrics = [
  for (final bar in _wirePaths) [for (final path in bar) path.computeMetrics().first],
];

/// Where on wire [i] of [bar] (0 the top, 1 the bottom) the point [f] (0 at the die, 1 at the
/// board) is, on the sheet.
Offset chipWirePoint(int bar, int i, double f) {
  final metric = _wireMetrics[bar][i];
  return metric.getTangentForOffset(metric.length * f.clamp(0.0, 1.0))!.position;
}

/// The part of lane [i] of [bar] (0 the top, 1 the bottom) between [from] and [to] (0 at the die
/// or bank, 1 at the board).
Path chipLaneSegment(int bar, int i, double from, double to) {
  final metric = _wireMetrics[bar][i];
  return metric.extractPath(metric.length * from.clamp(0.0, 1.0), metric.length * to.clamp(0.0, 1.0));
}

/// Where on lane [i] of [bar] the point [f] (0 at the die, 1 at the board) is, on the sheet.
Offset chipLanePoint(int bar, int i, double f) {
  final metric = _wireMetrics[bar][i];
  return metric.getTangentForOffset(metric.length * f.clamp(0.0, 1.0))!.position;
}

/// The wires with nothing on them: shadow, body and shine, all 27 of a row in one picture.
void _drawDullLanes(Canvas canvas, int bar) {
  final body = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4
    ..color = ChipPalette.gray650;
  final shine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = .9
    ..color = ChipPalette.white.withValues(alpha: .14);
  final shade = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3
    ..color = ChipPalette.black.withValues(alpha: .3);
  for (var i = 0; i < chipWireCount; i++) {
    final path = _wirePaths[bar][i];
    canvas.drawPath(path.shift(const Offset(1.1, 1.6)), shade);
    canvas.drawPath(path, body);
    canvas.drawPath(path.shift(const Offset(-.5, -.5)), shine);
  }
}

/// The 27 lanes of [bar]: each is a wire between the die (or the bank) and the board. A lane
/// that is not up is drawn dull, as a wire with nothing on it (all of those are one picture);
/// [level] is how far lane `i` is up (0..1), which brightens it to [color].
void paintChipLanes(
  Canvas canvas,
  int bar, {
  required Color color,
  required double alpha,
  required double Function(int i) level,
}) {
  _art('lanes-dull-$bar', const Rect.fromLTWH(50, 34, 250, 272), (c) => _drawDullLanes(c, bar)).paint(canvas);
  Paint? body, shine;
  for (var i = 0; i < chipWireCount; i++) {
    final up = level(i).clamp(0.0, 1.0);
    if (up <= .004) continue;
    body ??= Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    shine ??= Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .9;
    final path = _wirePaths[bar][i];
    body.color = Color.lerp(ChipPalette.gray650, color, up * alpha)!;
    canvas.drawPath(path, body);
    shine.color = ChipPalette.white.withValues(alpha: (.14 + .46 * up) * (.4 + .6 * alpha));
    canvas.drawPath(path.shift(const Offset(-.5, -.5)), shine);
  }
}

/// The substrate: a green board with its pads, corner marker, notches and parts.
void paintChipBoard(Canvas canvas) =>
    _art('board', const Rect.fromLTWH(0, 0, chipSheet, chipSheet), _drawBoard).paint(canvas);

/// Where the parts of the die are. It is laid out like a modern processor: two rows of identical cores (the cores
/// of the phone, [perRow] to a row), the shared cache between the rows, the data fabric that joins the cores to the
/// cache, and along the bottom the memory controller with its interface to the memory (at the die's edge, where the
/// memory is reached), the storage and USB interfaces, the media engine, the clock generator and the power
/// management.
class _DieLayout {
  _DieLayout(Rect a, this.perRow) {
    final gap = perRow == 4 ? 8.0 : 12.0;
    final w = (256 - (perRow - 1) * gap) / perRow;
    for (final y in [12.0, 104.0]) {
      for (var c = 0; c < perRow; c++) {
        cores.add(Rect.fromLTWH(a.left + 12 + c * (w + gap), a.top + y, w, 54));
      }
    }
    for (var c = 0; c < perRow; c++) {
      l3.add(Rect.fromLTWH(a.left + 12 + c * (w + gap), a.top + 72, w, 26));
    }
    fabricTop = Rect.fromLTWH(a.left + 12, a.top + 67, 256, 4);
    fabricBottom = Rect.fromLTWH(a.left + 12, a.top + 99, 256, 4);
    mc = Rect.fromLTWH(a.left + 12, a.top + 164, 124, 15);
    phy = Rect.fromLTWH(a.left + 12, a.top + 180, 124, 16);
    io = Rect.fromLTWH(a.left + 144, a.top + 164, 52, 32);
    media = Rect.fromLTWH(a.left + 200, a.top + 164, 36, 32);
    pll = Rect.fromLTWH(a.left + 240, a.top + 164, 28, 15);
    pmu = Rect.fromLTWH(a.left + 240, a.top + 181, 28, 15);
    columnWidth = w;
    columnGap = gap;
  }

  final int perRow;
  final List<Rect> cores = [], l3 = [];
  late final Rect fabricTop, fabricBottom, mc, phy, io, media, pll, pmu;
  late final double columnWidth, columnGap;
}

/// The blocks of the die in the order a chip powers up: the clock generator, power management,
/// the memory controller and its interface, the fabric (top, bottom), the slices of the shared
/// cache, the cores (top row, then bottom row), then the storage/USB interfaces and the media
/// engine. The cache slices and cores are the blocks 6 to 6 + 3 * [perRow] (see
/// [chipDieWorkRange]).
List<Rect> chipDieBlocks(Rect area, int perRow) {
  final l = _DieLayout(area, perRow);
  return [l.pll, l.pmu, l.mc, l.phy, l.fabricTop, l.fabricBottom, ...l.l3, ...l.cores, l.io, l.media];
}

/// The blocks that hold the cache and the cores (what a model is loaded into): their first
/// index and how many there are.
(int, int) chipDieWorkRange(int perRow) => (6, 3 * perRow);

/// The silicon die the photos are read on, with [perRow] cores to a row (see [chipDieColumns]).
void paintChipDie(Canvas canvas, Rect area, int perRow) {
  _evictOthers('die', {'die$perRow', 'dieLit$perRow'});
  _art('die$perRow', area.inflate(8), (c) => _drawDie(c, area, perRow)).paint(canvas);
}

/// How many cores to a row for a phone with [cores] cores: two rows, three or four to a row.
int chipDieColumns(int cores) => (cores / 2).round().clamp(3, 4);

/// Draws what [draw] paints (in sheet coordinates, inside [bounds]) from a picture made the first
/// time and kept: for something that is drawn the same way every frame.
void paintChipCached(Canvas canvas, String key, Rect bounds, void Function(Canvas canvas) draw) =>
    _art(key, bounds, draw).paint(canvas);

/// Makes the pictures of everything that is under the lid (the die, the lit die, the memory
/// bank and the dull wires) one at a time, a little apart, so none of them is made while the lid
/// is opening or a scan is starting (it is the biggest of the chip's work).
Future<void> warmChipInside(Rect die, Rect strip, int perRow) async {
  final steps = <void Function()>[
    () => _art('die$perRow', die.inflate(8), (c) => _drawDie(c, die, perRow)),
    () => _art('dieLit$perRow', die.inflate(8), (c) => _drawDieLayer(c, die, perRow, lit: true)),
    () => _art('memory', strip.inflate(4), (c) => _drawMemory(c, strip)),
    () => _art('lanes-dull-0', const Rect.fromLTWH(50, 34, 250, 272), (c) => _drawDullLanes(c, 0)),
    () => _art('lanes-dull-1', const Rect.fromLTWH(50, 34, 250, 272), (c) => _drawDullLanes(c, 1)),
  ];
  for (final step in steps) {
    step();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

void _drawMemory(Canvas canvas, Rect strip) {
  final bank = RRect.fromRectAndRadius(strip, const Radius.circular(16));
  canvas.drawRRect(
    bank,
    Paint()
      ..shader = ui.Gradient.linear(strip.topCenter, strip.bottomCenter, [
        ChipPalette.mint800a,
        ChipPalette.mint900b,
      ]),
  );
  canvas.save();
  canvas.clipRRect(bank);
  final chip = Paint()..color = ChipPalette.sky950;
  for (var k = 0; k < 7; k++) {
    final r = Rect.fromLTWH(strip.left + 6 + k * 38, strip.top + 11, 34, 34);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), chip);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(.5), const Radius.circular(3.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = ChipPalette.white.withValues(alpha: .14),
    );
  }
  final gold = Paint()..color = ChipPalette.gold400a;
  for (var i = 0; i < chipWireCount; i++) {
    final x = _dieX(_wireX(i));
    canvas.drawRect(Rect.fromLTWH(x - 3.2, strip.bottom - 6.4, 6.4, 6.4), gold);
  }
  canvas.restore();
  canvas.drawRRect(
    bank.deflate(.6),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ChipPalette.white.withValues(alpha: .12),
  );
}

/// The memory bank along the bottom.
void paintChipMemory(Canvas canvas, Rect strip) =>
    _art('memory', strip.inflate(4), (c) => _drawMemory(c, strip)).paint(canvas);

const Rect _flange = Rect.fromLTWH(34, 34, 272, 272);

const Rect _plate = Rect.fromLTWH(50, 50, 240, 240);

Path _flangePath() {
  const r = 15.0, cut = 16.0;
  return Path()
    ..moveTo(_flange.left + cut, _flange.top)
    ..lineTo(_flange.right - r, _flange.top)
    ..arcTo(Rect.fromCircle(center: Offset(_flange.right - r, _flange.top + r), radius: r), -math.pi / 2, math.pi / 2, false)
    ..lineTo(_flange.right, _flange.bottom - r)
    ..arcTo(Rect.fromCircle(center: Offset(_flange.right - r, _flange.bottom - r), radius: r), 0, math.pi / 2, false)
    ..lineTo(_flange.left + r, _flange.bottom)
    ..arcTo(Rect.fromCircle(center: Offset(_flange.left + r, _flange.bottom - r), radius: r), math.pi / 2, math.pi / 2, false)
    ..lineTo(_flange.left, _flange.top + cut)
    ..close();
}
