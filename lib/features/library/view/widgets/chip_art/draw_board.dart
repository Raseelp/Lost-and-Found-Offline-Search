part of '../chip_art.dart';

/// Draws the board with its shadow on the page, a faint speckle for the weave, and edge light on the top and left
/// with shade on the bottom and right. It has contact pads along the four edges, which are what a real chip plugs in
/// by, and retention notches in the middle of the left and right edges. The bond fingers the wires end on are gold
/// and lie along the top and bottom. What each row carries is printed above and below them while a scan runs (see
/// scan_square.dart). A few capacitors sit at the ends of the rows, with vias in the board, and the alignment
/// triangle is in the corner.
void _drawBoard(Canvas canvas) {
  final board = RRect.fromRectAndRadius(chipBoard, const Radius.circular(12));
  for (var k = 1; k <= 4; k++) {
    canvas.drawRRect(
      board.shift(Offset(0, 1.5 * k)),
      Paint()..color = ChipPalette.gray900.withValues(alpha: .04),
    );
  }
  canvas.drawRRect(
    board,
    Paint()
      ..shader = ui.Gradient.linear(chipBoard.topLeft, chipBoard.bottomRight, [
        ChipPalette.mint750,
        ChipPalette.mint800,
      ]),
  );
  canvas.save();
  canvas.clipRRect(board);
  final rnd = math.Random(5);
  final speck = Paint();
  for (var i = 0; i < 260; i++) {
    final at = Offset(
      chipBoard.left + rnd.nextDouble() * chipBoard.width,
      chipBoard.top + rnd.nextDouble() * chipBoard.height,
    );
    speck.color = (rnd.nextBool() ? ChipPalette.white : ChipPalette.black).withValues(alpha: .05 + rnd.nextDouble() * .06);
    canvas.drawCircle(at, .5 + rnd.nextDouble() * .7, speck);
  }
  canvas.drawRRect(
    board.shift(const Offset(1.4, 1.4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ChipPalette.white.withValues(alpha: .16),
  );
  canvas.drawRRect(
    board.shift(const Offset(-1.4, -1.4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ChipPalette.black.withValues(alpha: .22),
  );
  canvas.restore();
  canvas.drawRRect(
    board,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ChipPalette.mint900,
  );
  const padFrom = 46.0, padTo = 294.0, padsPerSide = 18;
  const pitch = (padTo - padFrom) / (padsPerSide - 1);
  const near = 23.4, far = 313.4;
  final pad = Paint();
  void contact(Rect r) {
    final tall = r.height > r.width;
    pad.color = ChipPalette.goldDull;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(.8)), pad);
    pad.color = ChipPalette.goldDullLight;
    canvas.drawRect(
      tall ? Rect.fromLTWH(r.left, r.top, r.width * .45, r.height) : Rect.fromLTWH(r.left, r.top, r.width, r.height * .45),
      pad,
    );
  }

  for (var i = 0; i < padsPerSide; i++) {
    final at = padFrom + i * pitch;
    contact(Rect.fromLTWH(at - 2.6, near, 5.2, 3.4));
    contact(Rect.fromLTWH(far, at - 2.6, 3.4, 5.2));
    contact(Rect.fromLTWH(at - 2.6, far, 5.2, 3.4));
    contact(Rect.fromLTWH(near, at - 2.6, 3.4, 5.2));
  }
  canvas.save();
  canvas.clipRRect(board);
  for (final x in [chipBoard.left, chipBoard.right]) {
    canvas.drawCircle(Offset(x, 170), 5.2, Paint()..color = AppColors.canvas);
    canvas.drawCircle(
      Offset(x, 170),
      5.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = ChipPalette.mint900,
    );
  }
  canvas.restore();

  for (var bar = 0; bar < 2; bar++) {
    for (var i = 0; i < chipWireCount; i++) {
      final fan = (i - (chipWireCount - 1) / 2) * .3;
      final x = _wireX(i) + fan;
      final y = bar == 0 ? _fingerTop - 2.6 : _fingerBottom - 1.0;
      contact(Rect.fromLTWH(x - 3.2, y, 6.4, 3.8));
    }
  }
  final cap = Paint();
  void capacitors(double x, double y, int count) {
    canvas.drawRect(
      Rect.fromLTWH(x - 1.6, y - 1.6, count * 8 + 1.2, 6.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = ChipPalette.white.withValues(alpha: .3),
    );
    for (var i = 0; i < count; i++) {
      final r = Rect.fromLTWH(x + i * 8, y, 6.2, 3.4);
      cap.color = ChipPalette.gold350;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(.5)), cap);
      cap.color = ChipPalette.gray250;
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, 1.4, r.height), cap);
      canvas.drawRect(Rect.fromLTWH(r.right - 1.4, r.top, 1.4, r.height), cap);
    }
  }

  capacitors(286, 35.8, 2);
  capacitors(286, 299.8, 2);
  final via = Paint()..color = ChipPalette.green350.withValues(alpha: .55);
  for (final at in const [Offset(32, 98), Offset(32, 242), Offset(308, 98), Offset(308, 242)]) {
    canvas.drawCircle(at, 1.6, via);
    canvas.drawCircle(at, .7, Paint()..color = ChipPalette.mint900a);
  }
  final marker = Path()
    ..moveTo(25.5, 25.5)
    ..lineTo(38, 25.5)
    ..lineTo(25.5, 38)
    ..close();
  canvas.drawPath(marker, Paint()..color = ChipPalette.gold);
  canvas.drawPath(
    marker,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = ChipPalette.goldDull,
  );
}

const Rect chipBoard = Rect.fromLTWH(22, 22, 296, 296);
