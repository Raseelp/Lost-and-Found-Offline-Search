part of '../people_timeline.dart';

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({required this.layout, required this.window}) : super(repaint: window);

  final TimelineLayout layout;
  final TimelineWindow window;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7));
    canvas.drawRRect(box, Paint()..color = AppColors.parchment);
    final months = layout.monthCount;
    if (months <= 0) return;
    canvas.save();
    canvas.clipRRect(box);
    final cw = size.width / months;
    final bar = Paint();
    for (var i = 0; i < layout.density.length; i++) {
      final v = layout.density[i];
      if (v <= 0) continue;
      final h = 3 + (size.height - 7) * v;
      bar.color = AppColors.primary.withValues(alpha: 0.25 + 0.5 * v);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * cw + 0.3, size.height - 3 - h, math.max(cw - 0.6, 1), h),
          const Radius.circular(1),
        ),
        bar,
      );
    }
    if (window.width > 0) {
      final left = ((window.start - layout.startMonth) * cw).clamp(0.0, size.width);
      final right = ((window.start + window.span - layout.startMonth) * cw).clamp(0.0, size.width);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, 1, math.max(right, left + 6), size.height - 1),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = AppColors.primary.withValues(alpha: 0.10));
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.primary,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter old) => !identical(old.layout, layout);
}
