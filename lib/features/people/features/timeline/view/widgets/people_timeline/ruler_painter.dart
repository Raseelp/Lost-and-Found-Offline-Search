part of '../people_timeline.dart';

/// The years (and, zoomed in, the months) along the top of the strips.
class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.window, required this.style}) : super(repaint: window);

  final TimelineWindow window;
  final TextStyle style;

  void _text(Canvas canvas, String text, double x, double y, {double? centreIn}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = centreIn == null ? x : x + (centreIn - painter.width) / 2;
    painter.paint(canvas, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ppm = window.ppm;
    if (window.width <= 0 || ppm <= 0) return;
    canvas.clipRect(Offset.zero & size);
    final start = window.start;
    final end = start + size.width / ppm;
    final line = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;

    final yearWidth = ppm * 12;
    final step = yearWidth >= 46 ? 1 : (yearWidth >= 23 ? 2 : (yearWidth >= 11 ? 5 : 10));
    final firstYear = start ~/ 12;
    final lastYear = end ~/ 12;
    for (var y = firstYear; y <= lastYear; y++) {
      final x = (y * 12 - start) * ppm;
      final named = y % step == 0;
      if (x >= -1 && x <= size.width) {
        if (named) canvas.drawLine(Offset(x, 0), Offset(x, 13), line);
        if (ppm < 11) canvas.drawLine(Offset(x, 22), Offset(x, 30), line);
      }
      if (!named) continue;
      var labelX = x + 3;
      if (x < 0) {
        final following = ((y + 1) * 12 - start) * ppm;
        labelX = math.min(3.0, following - 33);
      }
      if (labelX > size.width - 26 || labelX < -6) continue;
      _text(canvas, '$y', labelX, -1);
    }

    if (ppm >= 11) {
      final names = ppm >= 30 ? _monthShort : _monthInitials;
      for (var m = start.floor(); m <= end.ceil(); m++) {
        final x = (m - start) * ppm;
        if (x < -ppm || x > size.width) continue;
        canvas.drawLine(Offset(x, 22), Offset(x, 30), line);
        _text(canvas, names[m % 12], x, 14, centreIn: ppm);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.style != style;
}

const _monthInitials = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
