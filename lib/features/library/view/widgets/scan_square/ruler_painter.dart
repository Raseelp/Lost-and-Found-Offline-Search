part of '../scan_square.dart';

/// A thin gauge with a ruler under it: the bar fills in the channel's colour and the ticks it
/// has passed take the colour too. When how far it is cannot be told, a short run goes to and fro.
class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.fraction, required this.color, required this.sweep}) : super(repaint: sweep);

  final double? fraction;
  final Color color;
  final Animation<double>? sweep;

  static const double _track = 6;
  static const int _ticks = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, _track), const Radius.circular(_track / 2));
    canvas.drawRRect(track, Paint()..color = AppColors.ink.withValues(alpha: .08));

    double reach = 0;
    canvas.save();
    canvas.clipRRect(track);
    if (fraction == null) {
      final t = sweep?.value ?? .3;
      final swing = t < .5 ? t * 2 : 2 - t * 2;
      final run = w * .22;
      final from = (w - run) * Curves.easeInOut.transform(swing);
      canvas.drawRect(Rect.fromLTWH(from, 0, run, _track), Paint()..color = color);
      reach = -1;
    } else {
      reach = w * fraction!;
      if (reach > 0) canvas.drawRect(Rect.fromLTWH(0, 0, reach, _track), Paint()..color = color);
    }
    canvas.restore();

    final tick = Paint()..strokeWidth = 1;
    for (var i = 0; i <= _ticks; i++) {
      final x = (w * i / _ticks).clamp(.5, w - .5);
      final major = i % 5 == 0;
      final passed = reach >= 0 && w * i / _ticks <= reach + .5;
      tick.color = passed ? color.withValues(alpha: .75) : AppColors.ink.withValues(alpha: major ? .28 : .16);
      canvas.drawLine(Offset(x, _track + 3), Offset(x, _track + (major ? 9 : 6)), tick);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.fraction != fraction || old.color != color || old.sweep != sweep;
}
