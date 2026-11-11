part of '../timeline_preview.dart';

/// How [count] pictures are laid out in a box [size]: the first, the hero, biggest and the rest around it, with no
/// gaps but [gap]. [heroRight] puts the hero on the right instead of the left.
///
/// From four pictures on there are four columns. The hero is two across and two down, and the rest fill the cells
/// round it a row at a time, with the last row stretched so nothing is left empty.
List<Rect> bentoRects(int count, Size size, {bool heroRight = false, double gap = 4}) {
  if (count <= 0) return const [];
  final w = size.width, h = size.height;
  var rects = <Rect>[];
  if (count == 1) {
    rects = [Rect.fromLTWH(0, 0, w, h)];
  } else if (count == 2) {
    final cw = (w - gap) / 2;
    rects = [Rect.fromLTWH(0, 0, cw, h), Rect.fromLTWH(cw + gap, 0, cw, h)];
  } else if (count == 3) {
    final big = (w - gap) * 0.6, small = (w - gap) - big, ch = (h - gap) / 2;
    rects = [
      Rect.fromLTWH(0, 0, big, h),
      Rect.fromLTWH(big + gap, 0, small, ch),
      Rect.fromLTWH(big + gap, ch + gap, small, ch),
    ];
  } else {
    const cols = 4;
    final rows = count <= 5 ? 2 : (count <= 9 ? 3 : 4);
    final cw = (w - gap * (cols - 1)) / cols, ch = (h - gap * (rows - 1)) / rows;
    rects.add(Rect.fromLTWH(0, 0, cw * 2 + gap, ch * 2 + gap));
    var left = count - 1;
    for (var r = 0; r < rows && left > 0; r++) {
      final first = r < 2 ? 2 : 0;
      final available = cols - first;
      final used = math.min(available, left);
      left -= used;
      final rowWidth = available * cw + (available - 1) * gap;
      final each = (rowWidth - (used - 1) * gap) / used;
      final x0 = first * (cw + gap);
      for (var k = 0; k < used; k++) {
        rects.add(Rect.fromLTWH(x0 + k * (each + gap), r * (ch + gap), each, ch));
      }
    }
  }
  if (heroRight) {
    rects = [for (final r in rects) Rect.fromLTWH(w - r.right, r.top, r.width, r.height)];
  }
  return rects;
}
