part of '../chip_art.dart';

void _drawLidBase(Canvas canvas) {
  final flange = _flangePath();
  canvas.drawPath(
    flange,
    Paint()
      ..shader = ui.Gradient.linear(_flange.topLeft, _flange.bottomRight, [
        ChipPalette.slate100,
        ChipPalette.slate250,
      ]),
  );
  canvas.drawPath(
    flange,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ChipPalette.slate450,
  );
  for (final at in const [Offset(292, 48), Offset(292, 292), Offset(48, 292)]) {
    canvas.drawCircle(at + const Offset(.6, .6), 1.8, Paint()..color = ChipPalette.white.withValues(alpha: .6));
    canvas.drawCircle(at, 1.8, Paint()..color = ChipPalette.slate450a);
  }
  final ramp = RRect.fromRectAndRadius(_plate.inflate(4), const Radius.circular(15));
  canvas.drawRRect(
    ramp,
    Paint()
      ..shader = ui.Gradient.linear(ramp.outerRect.topLeft, ramp.outerRect.bottomRight, [
        ChipPalette.gray50,
        ChipPalette.slate400,
      ]),
  );
  final plate = RRect.fromRectAndRadius(_plate, const Radius.circular(11));
  canvas.drawRRect(
    plate,
    Paint()
      ..shader = ui.Gradient.linear(
        _plate.topLeft,
        _plate.bottomRight,
        [
          ChipPalette.sky50,
          ChipPalette.slate200a,
          ChipPalette.sky50a,
          ChipPalette.slate300,
          ChipPalette.slate100a,
        ],
        [0, .3, .52, .78, 1],
      ),
  );
  canvas.save();
  canvas.clipRRect(plate);
  final rnd = math.Random(11);
  final brush = Paint()..strokeWidth = .6;
  for (var i = 0; i < 120; i++) {
    final y = _plate.top + rnd.nextDouble() * _plate.height;
    final x0 = _plate.left + rnd.nextDouble() * _plate.width * .7;
    final x1 = x0 + 40 + rnd.nextDouble() * _plate.width * .6;
    brush.color = (i.isEven ? ChipPalette.white : ChipPalette.slate650).withValues(alpha: .05 + rnd.nextDouble() * .07);
    canvas.drawLine(Offset(x0, y), Offset(x1, y + (rnd.nextDouble() - .5) * .8), brush);
  }
  canvas.drawRRect(
    plate.shift(const Offset(1.4, 1.4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = ChipPalette.white.withValues(alpha: .95),
  );
  canvas.drawRRect(
    plate.shift(const Offset(-1.4, -1.4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = ChipPalette.slate750.withValues(alpha: .28),
  );
  canvas.restore();
}
