part of '../video_full_screen.dart';

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.fraction,
    required this.grow,
    required this.markers,
    required this.durationMs,
  });

  /// How far along the bar the video is, from 0 to 1.
  final double fraction;
  /// How far the thumb has grown while held, from 0 to 1.
  final double grow;
  final List<int> markers;
  final int durationMs;

  /// Paints the bar with 7 units of room for the thumb at both ends. Where the picked person appears is marked by
  /// dots.
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final trackHeight = 3.5 + 2.5 * grow;
    final left = 7.0;
    final right = size.width - 7.0;
    final span = right - left;
    final x = left + span * fraction;

    final radius = Radius.circular(trackHeight / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(
        left,
        y - trackHeight / 2,
        right,
        y + trackHeight / 2,
        radius,
      ),
      Paint()..color = AppColors.onMedia.withValues(alpha: 0.24),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        left,
        y - trackHeight / 2,
        x,
        y + trackHeight / 2,
        radius,
      ),
      Paint()..color = AppColors.onMedia,
    );

    if (durationMs > 0) {
      for (final t in markers) {
        final mx = left + span * (t / durationMs).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset(mx, y),
          4.4,
          Paint()..color = AppColors.mediaInk,
        );
        canvas.drawCircle(
          Offset(mx, y),
          3.0,
          Paint()..color = AppColors.mediaAccent,
        );
      }
    }

    final thumb = 6.0 + 3.0 * grow;
    canvas.drawCircle(
      Offset(x, y),
      thumb + 1.2,
      Paint()..color = AppColors.scrim.withValues(alpha: 0.32),
    );
    canvas.drawCircle(Offset(x, y), thumb, Paint()..color = AppColors.onMedia);
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.fraction != fraction ||
      old.grow != grow ||
      old.durationMs != durationMs ||
      !identical(old.markers, markers);
}
