part of '../photo_faces_layer.dart';

class FaceFlightOverlay extends StatelessWidget {
  const FaceFlightOverlay({super.key, required this.flight, required this.t});

  final FaceFlight flight;

  /// 0..1. The journey is 0..[landingAt]; after it the band melts into the outline that has taken over.
  final double t;

  /// Where the journey ends and the hand-over begins.
  static const double landingAt = 0.86;

  /// Draws the travelling face along a gentle arc, up and over, rather than a straight line. The landing value goes
  /// from a true circle at 0 to the living band at 1.
  @override
  Widget build(BuildContext context) {
    final travel = (t / landingAt).clamp(0.0, 1.0);
    final e = Curves.easeInOutCubic.transform(travel);
    final control = Offset.lerp(flight.from, flight.to, 0.5)! + const Offset(0, -60);
    final at = Offset.lerp(Offset.lerp(flight.from, control, e), Offset.lerp(control, flight.to, e), e)!;
    final radius = 22 + (flight.endRadius - 22) * Curves.easeOut.transform(e);
    final amp = Curves.easeIn.transform(e);
    final landing = ((t - landingAt) / (1 - landingAt)).clamp(0.0, 1.0);
    final ringAlpha = 1 - Curves.easeIn.transform(landing);
    final photo = (1 - Curves.easeIn.transform(((e - 0.45) / 0.55).clamp(0.0, 1.0))).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _FlightPainter(at, radius, amp, ringAlpha, e, flight.entry)),
        if (photo > 0)
          Positioned(
            left: at.dx - radius * 0.86,
            top: at.dy - radius * 0.86,
            width: radius * 1.72,
            height: radius * 1.72,
            child: Opacity(
              opacity: photo,
              child: ClipOval(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: 56, height: 56, child: FaceAvatar(faceId: flight.faceId, size: 56)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A face travelling to where it is in the picture: it sets off as a circle around their photo, and on the way the
/// circle grows to the size of the head and its edge starts to swell and dip, becoming the same living band the
/// outline is, while the photo inside dissolves to show the real head. Meant to be given to the outline as it lands.
class FaceFlight {
  const FaceFlight({
    required this.faceId,
    required this.from,
    required this.to,
    required this.endRadius,
    required this.entry,
  });

  /// The look the band ends in. The outline that takes over is given the same one.
  final RingEntry entry;

  final int faceId;
  /// In screen coordinates.
  final Offset from;
  final Offset to;
  final double endRadius;
}

class _FlightPainter extends CustomPainter {
  _FlightPainter(this.at, this.radius, this.amp, this.alpha, this.e, this.entry);

  final Offset at;
  final double radius;
  final double amp;
  final double alpha;
  /// How far along the journey, from 0 to 1.
  final double e;
  final RingEntry entry;

  /// Draws exactly what the outline draws when it takes over (same shape, start, colours and weight), with the swell
  /// of the waves growing from nothing, a circle, on the way. The colours turn a little as it travels and are at rest,
  /// the outline's own start, on landing.
  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final phase = entry.dir > 0 ? 0.0 : 1.0;
    final path = _blobPath(at, radius, phase, 0, offset: entry.offset, start: entry.start, amp: amp);
    final rotation = entry.start + entry.dir * (1 - e) * 4.0;
    _glowStroke(canvas, path, at, radius, rotation, entry.tint, alpha: alpha, line: 2.8, glow: 1.3);
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.at != at || old.radius != radius || old.amp != amp || old.alpha != alpha || old.e != e;
}
