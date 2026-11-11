part of '../people_timeline.dart';

/// One person's strip: moved sideways by a finger and zoomed by a pinch, both through the shared
/// window.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.row,
    required this.layout,
    required this.window,
    required this.tone,
    required this.develop,
    required this.onTap,
    this.compact = false,
  });

  final TimelineRowData row;
  final TimelineLayout layout;
  final TimelineWindow window;
  final Color tone;
  final Animation<double> develop;
  final bool compact;

  /// A tap on the row (it opens the person).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (r) => r.onTap = onTap,
        ),
        // Only a sideways drag, so scrolling the list and tapping the row work as ever.
        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
          (r) => r
            ..onStart = ((_) => window.dragStart(fromStrip: true))
            ..onUpdate = ((d) => window.dragBy(d.delta.dx))
            ..onEnd = ((d) => window.dragEnd(d.velocity.pixelsPerSecond.dx))
            ..onCancel = (() => window.dragEnd(0)),
        ),
      },
      child: Listener(
        // Two fingers anywhere on the strips are a pinch, followed here and not through the gesture arena, so the list
        // can stand still while it lasts.
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final box = context.findRenderObject() as RenderBox?;
          window.pointerDown(e.pointer, e.position, box == null ? 0 : box.localToGlobal(Offset.zero).dx);
        },
        onPointerMove: (e) => window.pointerMove(e.pointer, e.position),
        onPointerUp: (e) => window.pointerUp(e.pointer),
        onPointerCancel: (e) => window.pointerUp(e.pointer),
        child: SizedBox(
          height: compact ? _compactStripHeight : _stripHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _StripPainter(
              row: row,
              base: layout.startMonth,
              window: window,
              color: tone,
              develop: develop,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }
}

const double _stripHeight = 40;

const double _compactStripHeight = 30;
