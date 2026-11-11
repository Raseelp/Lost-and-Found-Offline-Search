part of '../photo_faces_layer.dart';

/// The colours of the selection outline: the app's teal (lightened so it glows on a
/// photo) flowing into cool blue, violet, pink and warm gold, and back to teal.
const List<Color> _ringColors = [
  FacePalette.mint350,
  FacePalette.sky250,
  FacePalette.indigo250,
  FacePalette.pink250,
  FacePalette.orange300,
  FacePalette.mint350,
];

/// [path] as a glowing line: soft wide strokes underneath, a crisp thin one on top. A crowded photo gets one soft
/// layer instead of three, which looks the same at a glance for a third of the work.
void _glowStroke(Canvas canvas, Path path, Offset centre, double radius, double rotation, int tint,
    {required double alpha, double line = 2.4, double glow = 1.0, bool soft = true}) {
  const layers = [
    [15.0, 0.07],
    [10.0, 0.11],
    [6.0, 0.17],
  ];
  final used = soft ? layers : const [[9.0, 0.15]];
  final rect = radius * 1.2;
  for (final l in used) {
    canvas.drawPath(
      path,
      Paint()
        ..shader = _sweepShader(centre, rect, rotation, tint, alpha * l[1] * glow)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = l[0],
    );
  }
  canvas.drawPath(
    path,
    Paint()
      ..shader = _sweepShader(centre, rect, rotation, tint, alpha * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line,
  );
}

/// Everything below is drawn WITHOUT blur filters and with the transparency baked into the
/// colours themselves: a blurred, gradient-shaded stroke can render as a hard rectangle on
/// some GPUs (the flash of squares), and a paint's own alpha is not reliably applied on top
/// of a gradient. A soft glow is built from a few widening, fainter strokes instead.
Shader _sweepShader(Offset centre, double radius, double rotation, int tint, double alpha) {
  final colours = [..._ringColors.skip(tint), ..._ringColors.take(tint + 1)]
      .map((c) => c.withValues(alpha: alpha))
      .toList();
  return SweepGradient(colors: colours, transform: GradientRotation(rotation))
      .createShader(Rect.fromCircle(center: centre, radius: radius));
}

/// A small soft light (a radial fade, not a blur).
void _light(Canvas canvas, Offset at, double radius, Color colour, double alpha) {
  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [colour.withValues(alpha: alpha), colour.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: at, radius: radius)),
  );
}

/// A living outline: a circle whose edge swells and dips in a few slow waves, so it
/// reads as a small amoeba rather than a ring. [phase] runs 0..1 and the motion
/// loops seamlessly (every wave turns a whole number of times per loop);
/// [wobble] > 0 exaggerates it (used while the outline settles in).
double _blobRadius(double angle, double radius, double phase, double wobble, [double offset = 0, double amp = 1]) {
  final t = phase * 2 * math.pi + offset;
  final wave = 0.055 * math.sin(2 * angle + t) +
      0.045 * math.sin(3 * angle - 2 * t + 1.3) +
      0.030 * math.sin(5 * angle + t + 2.6) +
      0.022 * math.sin(4 * angle - t + 0.7);
  return radius * (1 + wave * (1 + 1.6 * wobble) * amp);
}

Path _blobPath(Offset center, double radius, double phase, double wobble,
    {double offset = 0, double start = -math.pi / 2, int steps = 140, double amp = 1}) {
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final a = start + i / steps * 2 * math.pi;
    final r = _blobRadius(a, radius, phase, wobble, offset, amp);
    final point = center + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

/// The dice for one showing of an effect, so no two look the same: where the outline
/// starts, which way it turns, what shape the waves begin in, where the sparkle lands.
class _Roll {
  _Roll(math.Random r)
      : offset = r.nextDouble() * 2 * math.pi,
        start = r.nextDouble() * 2 * math.pi,
        dir = r.nextBool() ? 1.0 : -1.0,
        sparkleAngle = (r.nextBool() ? -1 : 1) * (0.25 + r.nextDouble() * 1.2) - (r.nextBool() ? 0 : math.pi),
        tint = r.nextInt(_ringColors.length - 1),
        lag = r.nextDouble() * 0.12;

  _Roll.fixed(RingEntry e)
      : offset = e.offset,
        start = e.start,
        dir = e.dir,
        sparkleAngle = 0,
        tint = e.tint,
        lag = 0;

  final double offset;
  final double start;
  final double dir;
  final double sparkleAngle;
  /// Which colour the outline starts on.
  final int tint;
  /// The fraction of the hint's length this face waits before starting.
  final double lag;
}

/// The look of one outline: where its edge starts, which way it turns, its colours, the shape its waves begin in. The
/// flight and the outline it lands in share one, so the outline picks up exactly where the flight leaves off and they
/// are the same band.
class RingEntry {
  const RingEntry({required this.offset, required this.start, required this.dir, required this.tint});

  factory RingEntry.random() {
    final r = math.Random();
    return RingEntry(
      offset: r.nextDouble() * 2 * math.pi,
      start: r.nextDouble() * 2 * math.pi,
      dir: r.nextBool() ? 1.0 : -1.0,
      tint: r.nextInt(_ringColors.length - 1),
    );
  }

  final double offset;
  final double start;
  final double dir;
  final int tint;
}

/// Where a head is inside a picture shown "contain"-fitted in [size]: its centre and radius.
class HeadSpot {
  const HeadSpot(this.center, this.radius);

  final Offset center;
  final double radius;
}

/// The same geometry the outline uses (around the whole head, a little bigger and higher than
/// the face box), for a picture that isn't zoomed. Null if the picture's size isn't known.
HeadSpot? headSpotFor(PhotoFace f, Size size) {
  if (f.photoW <= 0 || f.photoH <= 0 || size.isEmpty) return null;
  final aspect = f.photoW / f.photoH;
  final double w, h;
  if (size.width / size.height > aspect) {
    h = size.height;
    w = h * aspect;
  } else {
    w = size.width;
    h = w / aspect;
  }
  final origin = Offset((size.width - w) / 2, (size.height - h) / 2);
  final faceW = (f.right - f.left) * w;
  final faceH = (f.bottom - f.top) * h;
  final centre = origin + Offset((f.left + f.right) / 2 * w, (f.top + f.bottom) / 2 * h - faceH * 0.06);
  return HeadSpot(centre, math.max(faceW, faceH) * 0.5 * 1.4);
}

/// Where a face sits on screen: the centre and radius of a circle around the whole head, following the photo as it is
/// zoomed and panned.
class _Head {
  const _Head(this.center, this.radius);

  final Offset center;
  final double radius;
}

/// The floating pill surface for this feature's text and name chip: a soft dark tint
/// with a hairline edge, in the viewer's pill shape. (No backdrop blur: these fade and
/// scale in and out, and a blur inside a fading layer can render as garbage on some phones.)
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: FacePalette.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: FacePalette.white.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }
}

class _Orb {
  _Orb(math.Random r, this.color)
      : phase = r.nextDouble(),
        turns = (r.nextBool() ? 1 : -1) * (3 + r.nextInt(3)),
        breathPhase = r.nextDouble() * 2 * math.pi,
        breathTurns = 5 + r.nextInt(4),
        size = 0.34 + r.nextDouble() * 0.12;

  final Color color;
  /// Where round the edge it starts.
  final double phase;
  /// Whole turns per loop, so the loop is seamless.
  final int turns;
  final double breathPhase;
  final int breathTurns;
  /// Radius as a fraction of the screen's short side.
  final double size;
}

/// For the first-run tour. Its demo shows what happens when a photo is opened and a face is tapped,
/// on a bundled picture that has not been scanned, so it cannot use the layer above (that needs real
/// faces from the face database). These draw exactly what the layer draws, from the same code, so the
/// tour and the viewer cannot drift apart.
/// The viewer's outlines and sparkles, drawn for the tour's demo.
class FaceOutlineDemo {
  FaceOutlineDemo._();

  /// The hint on opening a photo: each head faintly traced with a sparkle. [progress] 0..1.
  static void paintHint(Canvas canvas, Size size, List<HeadSpot> heads, double progress, {int seed = 7}) {
    final rolls = [for (var i = 0; i < heads.length; i++) _Roll(math.Random(seed + i))];
    _HintPainter([for (final h in heads) _Head(h.center, h.radius)], rolls, progress).paint(canvas, size);
  }

  /// A tapped head: the photo dims round it and the glowing outline draws itself and keeps turning.
  /// [progress] 0..1 as it appears, [spin] in radians.
  static void paintRing(Canvas canvas, Size size, HeadSpot head,
      {required double progress, required double spin, int seed = 7}) {
    _RingPainter(
      center: head.center,
      radius: head.radius,
      progress: progress,
      spin: spin,
      roll: _Roll(math.Random(seed)),
    ).paint(canvas, size);
  }
}

/// "Tap a face to see who": the line the viewer shows when a photo opens.
class FaceHintLabel extends StatelessWidget {
  const FaceHintLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FlowText(
      'Tap a face to see who',
      leading: Icon(Icons.face_outlined, size: 20, color: FacePalette.white),
    );
  }
}

/// The chip the viewer pops up under a tapped head (the person's picture, name and number of photos),
/// from a bundled picture.
class FaceChipDemo extends StatelessWidget {
  const FaceChipDemo({super.key, required this.face, required this.name, required this.photos});

  final ImageProvider face;
  final String name;
  final int photos;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Glass(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs + 2, AppSpacing.xs + 2, AppSpacing.md, AppSpacing.xs + 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(child: Image(image: face, width: 40, height: 40, fit: BoxFit.cover)),
          const SizedBox(width: AppSpacing.md - 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, style: textTheme.titleSmall?.copyWith(color: FacePalette.white)),
              Text(
                photos == 1 ? '1 photo' : '$photos photos',
                style: textTheme.bodySmall?.copyWith(color: FacePalette.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right_rounded, size: 22, color: FacePalette.white.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}
