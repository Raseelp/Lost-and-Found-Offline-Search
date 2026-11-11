part of '../people_timeline.dart';

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.row,
    required this.base,
    required this.window,
    required this.color,
    required this.develop,
    this.compact = false,
  }) : _runs = compact ? timelineRuns(row.offsets) : const [],
       super(repaint: Listenable.merge([window, develop]));

  final bool compact;
  final List<(int, int)> _runs;

  final TimelineRowData row;

  /// The month the row's offsets count from.
  final int base;
  final TimelineWindow window;
  final Color color;

  /// 0 = nothing developed yet, 1 = the whole strip.
  final Animation<double> develop;

  static const double _inset = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final track = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9));
    canvas.drawRRect(track, Paint()..color = AppColors.parchment);
    final ppm = window.ppm;
    if (window.width <= 0 || ppm <= 0) return;

    canvas.save();
    canvas.clipRRect(track);
    final start = window.start;
    final end = start + w / ppm;
    final reveal = Curves.easeOutCubic.transform(develop.value);
    if (compact) {
      _paintCompact(canvas, size, reveal);
      canvas.restore();
      return;
    }

    final tick = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var m = (start / 12).ceil() * 12; m <= end; m += 12) {
      final x = (m - start) * ppm;
      canvas.drawLine(Offset(x, _inset), Offset(x, h - _inset - 1), tick);
    }

    final centreMonth = (start + w / ppm / 2).floor();
    final centreX = (centreMonth - start) * ppm;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(centreX - 1, 2, math.max(ppm, 3) + 2, h - 4), const Radius.circular(5)),
      Paint()..color = color.withValues(alpha: 0.16),
    );

    final maxCount = row.maxCount;
    final alone = row.offsets.length == 1;
    var i = _firstAtOrAfter(row.offsets, (start - base).floor());
    for (; i < row.offsets.length; i++) {
      final month = base + row.offsets[i];
      final x = (month - start) * ppm;
      if (x > w) break;
      final shown = ((reveal * 1.25 - x / w) * 5).clamp(0.0, 1.0);
      if (shown <= 0) continue;
      final t = maxCount <= 1 ? 1.0 : math.sqrt(row.counts[i] / maxCount);
      final cellW = alone ? math.max(7.0, ppm - 1) : math.max(ppm - math.min(1.0, ppm * 0.12), 2.4);
      final left = x + (ppm - cellW) / 2;
      final full = h - _inset * 2;
      final height = full * (0.38 + 0.62 * t) * Curves.easeOutBack.transform(shown).clamp(0.0, 1.2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, h - _inset - height, cellW, height),
        Radius.circular(math.min(cellW / 2, ppm > 20 ? 5 : 3)),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: (0.3 + 0.7 * t) * shown));
      if (month == centreMonth) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = AppColors.canvas,
        );
      }
    }

    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.85)
        ..strokeWidth = 1.5,
    );

    canvas.restore();
  }

  /// The collapsed strip: a thin rounded line for every stretch of months they are in, broken where they are not. It
  /// shows when, with no heights or counts.
  void _paintCompact(Canvas canvas, Size size, double reveal) {
    final w = size.width, h = size.height;
    final ppm = window.ppm;
    final start = window.start;
    final thickness = h * 0.46;
    final y = (h - thickness) / 2;

    final tick = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var m = (start / 12).ceil() * 12; m <= start + w / ppm; m += 12) {
      final x = (m - start) * ppm;
      canvas.drawLine(Offset(x, 3), Offset(x, h - 3), tick);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal * 1.1, h));
    final paint = Paint()..color = color.withValues(alpha: 0.9);
    for (final (first, last) in _runs) {
      final x1 = (base + first - start) * ppm;
      final x2 = (base + last + 1 - start) * ppm;
      if (x2 < 0 || x1 > w) continue;
      var left = x1 + 0.5, right = x2 - 0.5;
      if (right - left < thickness) {
        final mid = (left + right) / 2;
        left = mid - thickness / 2;
        right = mid + thickness / 2;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, y, right, y + thickness), Radius.circular(thickness / 2)),
        paint,
      );
    }
    canvas.restore();

    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.85)
        ..strokeWidth = 1.5,
    );
  }

  /// The first place in [sorted] holding a value of at least [value].
  static int _firstAtOrAfter(List<int> sorted, int value) {
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) =>
      old.color != color ||
      old.base != base ||
      old.compact != compact ||
      !identical(old.row, row) ||
      !identical(old.window, window);
}

/// The stretches of months a person is in, as (first, last) places on the axis: months in a row
/// make one stretch, and a gap of only a month or two does not end it.
List<(int, int)> timelineRuns(List<int> offsets, {int maxGap = _runGap}) {
  final runs = <(int, int)>[];
  for (final o in offsets) {
    if (runs.isNotEmpty && o - runs.last.$2 <= maxGap + 1) {
      runs[runs.length - 1] = (runs.last.$1, o);
    } else {
      runs.add((o, o));
    }
  }
  return runs;
}

/// In the collapsed list a gap of up to this many empty months does not break a line.
const int _runGap = 2;
