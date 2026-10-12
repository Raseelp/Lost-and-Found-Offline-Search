import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';

// The pictures of the zip export: the tick when it is done, and the sizes written out.

/// "1.2 GB", "340 MB", "12 KB".
String zipBytes(num bytes) {
  if (bytes < 0) return '-';
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 100 * 1024 * 1024 ? 1 : 0)} MB';
  }
  final gb = bytes / (1024 * 1024 * 1024);
  return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
}

// ------------------------------------------------------------------------------ the tick

/// A circle that draws itself and then a tick inside it, once.
class ZipDoneMark extends StatelessWidget {
  const ZipDoneMark({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) =>
          CustomPaint(size: Size.square(size), painter: _TickPainter(t)),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    final ring = (t / .6).clamp(0.0, 1.0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      stroke,
    );
    canvas.drawCircle(
      c,
      r - 3,
      Paint()..color = AppColors.primary.withValues(alpha: .1 * ring),
    );
    final tick = ((t - .45) / .55).clamp(0.0, 1.0);
    if (tick > 0) {
      final a = Offset(size.width * .30, size.height * .52);
      final b = Offset(size.width * .45, size.height * .66);
      final d = Offset(size.width * .72, size.height * .36);
      final path = Path()..moveTo(a.dx, a.dy);
      final first = (tick / .4).clamp(0.0, 1.0);
      path.lineTo(a.dx + (b.dx - a.dx) * first, a.dy + (b.dy - a.dy) * first);
      if (tick > .4) {
        final second = ((tick - .4) / .6).clamp(0.0, 1.0);
        path.lineTo(
          b.dx + (d.dx - b.dx) * second,
          b.dy + (d.dy - b.dy) * second,
        );
      }
      canvas.drawPath(path, stroke..strokeWidth = 5);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}
