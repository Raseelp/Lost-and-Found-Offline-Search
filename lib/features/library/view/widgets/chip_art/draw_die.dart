part of '../chip_art.dart';

/// Draws the die: the seal round it, the sheen of silicon (thin metal layers split the light into soft bands of
/// colour), a fine dot matrix as of the finest metal layer, its dark layer and the bond pads along its top edge,
/// where the wires of the CLIP row start.
void _drawDie(Canvas canvas, Rect area, int perRow) {
  final rim = RRect.fromRectAndRadius(area.inflate(3.4), const Radius.circular(18));
  canvas.drawRRect(rim, Paint()..color = ChipPalette.slate900);
  canvas.drawRRect(
    rim.deflate(.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = ChipPalette.white.withValues(alpha: .08),
  );
  final die = RRect.fromRectAndRadius(area.inflate(1.8), const Radius.circular(16));
  canvas.drawRRect(
    die,
    Paint()
      ..shader = ui.Gradient.linear(die.outerRect.topLeft, die.outerRect.bottomRight, [
        ChipPalette.slate600,
        ChipPalette.slate800,
      ]),
  );
  canvas.save();
  canvas.clipRRect(die);
  canvas.drawRect(
    area,
    Paint()
      ..shader = ui.Gradient.sweep(
        area.center,
        [
          ChipPalette.indigo400A18,
          ChipPalette.teal500A18,
          ChipPalette.gold450A18,
          ChipPalette.pink450A18,
          ChipPalette.indigo400A18,
        ],
        [0, .28, .52, .78, 1],
      ),
  );
  final dot = Paint()..color = ChipPalette.white.withValues(alpha: .07);
  for (var y = area.top + 3; y < area.bottom; y += 4) {
    for (var x = area.left + 3; x < area.right; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, y, .8, .8), dot);
    }
  }
  _drawDieLayer(canvas, area, perRow, lit: false);
  final bondPad = Paint()..color = ChipPalette.slate200;
  for (var i = 0; i < chipWireCount; i++) {
    final x = _dieX(_wireX(i));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - 3.2, _dieY(_dieEdgeTop) - 1.6, 6.4, 4.2), const Radius.circular(.7)),
      bondPad,
    );
  }
  canvas.restore();
  canvas.drawRRect(
    die,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = ChipPalette.white.withValues(alpha: .16),
  );
}

double _dieY(double sheetY) => chipSheet / 2 + (sheetY - chipSheet / 2) / chipDieScale;
