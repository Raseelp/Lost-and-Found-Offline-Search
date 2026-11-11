part of '../video_full_screen.dart';

/// A thin seek bar: a rounded track, a small thumb that grows while you hold it, and (for a person
/// picked in the People panel) small dots where they appear. Tap anywhere on it to jump there, or
/// drag; the video pauses while you drag and carries on afterwards if it was playing.
class _VideoScrubber extends StatefulWidget {
  const _VideoScrubber({required this.controller, required this.markers});

  final VideoPlayerController controller;
  final List<int> markers;

  @override
  State<_VideoScrubber> createState() => _VideoScrubberState();
}

class _VideoScrubberState extends State<_VideoScrubber> {
  bool _dragging = false;
  bool _wasPlaying = false;
  double _dragFraction = 0;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  double _fractionAt(double dx, double width) => (dx / width).clamp(0.0, 1.0);

  /// Seeks to [fraction] of the video. Seeking on every drag event floods the player, so one every 70 ms is plenty and
  /// the last one always lands.
  void _seek(double fraction, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSeek) < const Duration(milliseconds: 70)) {
      return;
    }
    _lastSeek = now;
    final ms = widget.controller.value.duration.inMilliseconds;
    widget.controller.seekTo(Duration(milliseconds: (fraction * ms).round()));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final durationMs = value.duration.inMilliseconds;
    final positionMs = value.position.inMilliseconds;
    final playedFraction = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              _seek(_fractionAt(d.localPosition.dx, width), force: true),
          onHorizontalDragStart: (d) {
            _wasPlaying = widget.controller.value.isPlaying;
            widget.controller.pause();
            setState(() {
              _dragging = true;
              _dragFraction = _fractionAt(d.localPosition.dx, width);
            });
            _seek(_dragFraction, force: true);
          },
          onHorizontalDragUpdate: (d) {
            setState(
              () => _dragFraction = _fractionAt(d.localPosition.dx, width),
            );
            _seek(_dragFraction);
          },
          onHorizontalDragEnd: (_) {
            _seek(_dragFraction, force: true);
            setState(() => _dragging = false);
            if (_wasPlaying) widget.controller.play();
          },
          child: SizedBox(
            height: 30,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _dragging ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 140),
              builder: (context, grow, _) => CustomPaint(
                painter: _ScrubberPainter(
                  fraction: _dragging ? _dragFraction : playedFraction,
                  grow: grow,
                  markers: widget.markers,
                  durationMs: durationMs,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
