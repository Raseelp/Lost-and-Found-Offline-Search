import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/features/library/view/widgets/chip_palette.dart';
part 'chip_art/shared.dart';
part 'chip_art/draw_board.dart';
part 'chip_art/art.dart';
part 'chip_art/draw_die.dart';
part 'chip_art/draw_die_layer.dart';
part 'chip_art/draw_lid_base.dart';

/// The steel heat spreader. [open] is how far it has come off (0 closed, 1 gone): it lifts a
/// little, tilts and slides away to the right. Over the lid is etched [idle], or [done] when
/// [doneAmt] says a finished scan is on show. [tilt] (each way -1..1) is how the phone is held,
/// which moves the reflection of the room on the plate.
void paintChipLid(
  Canvas canvas, {
  required double open,
  required double now,
  required bool pressed,
  required ChipLidText idle,
  ChipLidText? done,
  required double doneAmt,
  Offset tilt = Offset.zero,
  bool tiltLive = false,
}) {
  if (open >= .999) return;
  final lift = Curves.easeOut.transform(_seg(open, 0, .3));
  final slide = Curves.easeInOutCubic.transform(_seg(open, .22, 1));
  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(0, 0, chipSheet, chipSheet));
  canvas.translate(170 + 400 * slide, 170 + 46 * slide);
  canvas.rotate(.14 * slide);
  final scale = 1 + .05 * lift - (pressed && open == 0 ? .012 : 0);
  canvas.scale(scale);
  canvas.translate(-170, -170);

  final shadow = _art(
    'lid-shadow',
    _flange.inflate(34),
    (c) => c.drawPath(
      _flangePath(),
      Paint()
        ..color = ChipPalette.black
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    ),
    scale: 1.5,
  );
  canvas.save();
  canvas.translate(2 + 26 * lift, 4 + 30 * lift);
  shadow.paint(canvas, Paint()..color = ChipPalette.white.withValues(alpha: .34 * (1 - .55 * slide)));
  canvas.restore();

  _art('lid-base', _flange.inflate(6), _drawLidBase).paint(canvas);
  final plate = _art('room', _roomBounds, _drawRoom, scale: 1);
  var shift = Offset(tilt.dx * 150, tilt.dy * 150);
  if (!tiltLive) {
    shift = Offset(math.sin(now * .27) * 70 + math.sin(now * .09) * 40, math.cos(now * .19) * 55);
  }
  final left = (160 + shift.dx).clamp(0.0, 320.0);
  final top = (160 + shift.dy).clamp(0.0, 320.0);
  final roomImage = plate.image;
  if (roomImage != null) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(_plate, const Radius.circular(11)));
    canvas.drawImageRect(
      roomImage,
      Rect.fromLTWH(left, top, 240, 240),
      _plate,
      Paint()
        ..blendMode = BlendMode.overlay
        ..filterQuality = FilterQuality.low
        ..color = ChipPalette.white.withValues(alpha: .6),
    );
    canvas.restore();
  }

  final idleKey = 'lid-text-${idle.key}';
  final doneKey = done == null ? null : 'lid-text-${done.key}';
  _evictOthers('lid-text-', {idleKey, if (doneKey != null) doneKey});
  final idleArt = _art(idleKey, _plate, (c) => _drawLidText(c, idle));
  final doneArt = doneKey == null ? null : _art(doneKey, _plate, (c) => _drawLidText(c, done!));
  final showDone = doneArt != null && doneAmt > .01;
  if (1 - doneAmt > .01) {
    idleArt.paint(canvas, Paint()..filterQuality = FilterQuality.medium..color = ChipPalette.white.withValues(alpha: showDone ? 1 - doneAmt : 1));
  }
  if (showDone) {
    doneArt.paint(canvas, Paint()..filterQuality = FilterQuality.medium..color = ChipPalette.white.withValues(alpha: doneAmt));
  }

  final angleX = (tiltLive ? tilt.dx : shift.dx / 110) * .38;
  final angleY = (tiltLive ? tilt.dy : shift.dy / 110) * .38;
  final plateShape = RRect.fromRectAndRadius(_plate, const Radius.circular(11));
  final outer = RRect.fromRectAndRadius(_plate.inflate(4), const Radius.circular(15));
  double bevel(double t) => (.5 + t * 1.8).clamp(0.0, 1.0);
  canvas.drawDRRect(
    outer,
    plateShape,
    Paint()
      ..shader = ui.Gradient.linear(
        _plate.centerLeft - const Offset(4, 0),
        _plate.centerRight + const Offset(4, 0),
        [
          ChipPalette.white.withValues(alpha: .5 * bevel(-angleX)),
          ChipPalette.black.withValues(alpha: .1 + .25 * (1 - bevel(-angleX))),
        ],
      ),
  );
  canvas.drawDRRect(
    outer,
    plateShape,
    Paint()
      ..shader = ui.Gradient.linear(
        _plate.topCenter - const Offset(0, 4),
        _plate.bottomCenter + const Offset(0, 4),
        [
          ChipPalette.white.withValues(alpha: .3 * bevel(-angleY)),
          ChipPalette.black.withValues(alpha: .06 + .18 * (1 - bevel(-angleY))),
        ],
      ),
  );
  canvas.restore();
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

void _drawLidText(Canvas canvas, ChipLidText text) {
  _etchLine(canvas, text.above, 100, 10, space: 3.2);
  _etchLine(canvas, text.big, 142, 32, space: 1, weight: FontWeight.w800, maxWidth: 190);
  _etchLine(canvas, text.below, 184, 9.5, space: 2);
  for (var k = 0; k < text.extras.length && k < 3; k++) {
    _etchLine(canvas, text.extras[k], 206 + k * 17, 8.5, space: 2);
  }
  _etchLine(canvas, text.hint, 262, 7, space: 2.6);
}

/// One line of etching: a light edge under the dark line, as if cut into the metal.
void _etchLine(Canvas canvas, String text, double centreY, double size, {double space = 1, FontWeight weight = FontWeight.w700, double maxWidth = 200}) {
  final light = _etchText(text, size, space: space, weight: weight, color: ChipPalette.white.withValues(alpha: .85), maxWidth: maxWidth);
  final dark = _etchText(text, size, space: space, weight: weight, maxWidth: maxWidth);
  final at = Offset(170 - dark.width / 2, centreY - dark.height / 2);
  light.paint(canvas, at + const Offset(.8, .8));
  dark.paint(canvas, at);
}

TextPainter _etchText(String text, double size, {double space = 1, FontWeight weight = FontWeight.w700, Color color = ChipPalette.slate600a, double maxWidth = 200}) {
  TextPainter make(double s) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: s, height: 1, letterSpacing: space, fontWeight: weight, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  var tp = make(size);
  if (tp.width > maxWidth) tp = make(size * maxWidth / tp.width);
  return tp;
}

/// What is etched on the lid: a small line above, a big line, a line under, some more lines,
/// and a hint.
class ChipLidText {
  const ChipLidText({required this.above, required this.big, required this.below, this.extras = const [], required this.hint});

  final String above;
  final String big;
  final String below;
  final List<String> extras;
  final String hint;

  String get key => '$above|$big|$below|${extras.join('/')}|$hint';

  /// The same text with another hint line.
  ChipLidText withHint(String hint) => ChipLidText(above: above, big: big, below: below, extras: extras, hint: hint);
}

void _drawRoom(Canvas canvas) {
  canvas.drawRect(
    _roomBounds,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 560), [
        ChipPalette.slate350,
        ChipPalette.slate600b,
      ]),
  );
  void shape(Rect rect, double angle, Color color, double blur) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height), const Radius.circular(6)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  shape(const Rect.fromLTWH(160, 170, 240, 190), -.5, ChipPalette.white, 12);
  shape(const Rect.fromLTWH(262, 170, 12, 200), -.5, ChipPalette.slate250a, 5);
  shape(const Rect.fromLTWH(150, 262, 250, 12), -.5, ChipPalette.slate250a, 5);
  shape(const Rect.fromLTWH(380, 300, 60, 380), .75, ChipPalette.whiteA90, 11);
  shape(const Rect.fromLTWH(70, 400, 52, 52), 0, ChipPalette.whiteA90, 14);
  shape(const Rect.fromLTWH(420, 70, 150, 110), .3, ChipPalette.sky850, 10);
  shape(const Rect.fromLTWH(60, 90, 130, 80), -.2, ChipPalette.sky800, 12);
}

/// The room, as the steel sees it: a soft grey ceiling and walls with a window, a long strip
/// light, a lamp and a dark piece of furniture, all out of focus. Made once; the lid shows a
/// window on it that moves as the phone is tilted, in every direction, so the reflection slides
/// and turns across the plate like a real one.
const Rect _roomBounds = Rect.fromLTWH(0, 0, 560, 560);
