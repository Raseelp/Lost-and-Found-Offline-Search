part of '../photo_faces_layer.dart';

/// Shown while a photo's faces are being looked for (it has not been scanned yet). Soft pools of colour drift around
/// the edges of the screen, over the photo, and breathe, and a line at the bottom says what the scan is doing and how
/// far it has got. The mix of colours, where they start, how fast and which way they go are rolled fresh each time.
/// When the search ends it fades away and the faces it found take over.
class PhotoScanGlow extends StatefulWidget {
  const PhotoScanGlow({super.key, required this.visible, required this.message, this.bottomInset = 0});

  final bool visible;

  /// Extra room kept clear along the bottom (a video's controls).
  final double bottomInset;

  /// What the scan is doing, in a few words ("Found 12 faces · identifying").
  final String message;

  @override
  State<PhotoScanGlow> createState() => _PhotoScanGlowState();
}

class _PhotoScanGlowState extends State<PhotoScanGlow> with TickerProviderStateMixin {
  static const _palette = [
    FacePalette.mint350,
    FacePalette.sky250,
    FacePalette.indigo250,
    FacePalette.pink250,
    FacePalette.orange300,
  ];

  /// One long loop; every orb turns a whole number of times in it.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  /// How much of the glow shows (0..1), applied inside the painter: fading a whole
  /// screen-sized layer instead is what produced the blocky garbage on some phones.
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final math.Random _rng = math.Random();
  late List<_Orb> _orbs = _roll();
  bool _pillOn = false;

  List<_Orb> _roll() {
    final colours = List<Color>.from(_palette)..shuffle(_rng);
    return [for (var i = 0; i < 3; i++) _Orb(_rng, colours[i])];
  }

  /// Starts the glow with a freshly rolled look.
  void _start() {
    _orbs = _roll();
    _pillOn = true;
    _fade.forward();
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) _start();
  }

  /// The orbs go round while it shows. With motion off they stay where they are: the glow still says it is
  /// looking, without moving.
  void _loop() {
    if (_fade.isDismissed && !widget.visible) return;
    loopUnlessCalm(context, _c);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loop();
  }

  /// Keeps the glow going while it fades out, and stops it only once it cannot be seen.
  @override
  void didUpdateWidget(covariant PhotoScanGlow old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _start();
      _loop();
    } else if (!widget.visible && old.visible) {
      _fade.reverse().whenComplete(() {
        if (mounted && !widget.visible) _c.stop();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Fades out quickly, so it has gone before "Tap a face to see who" arrives in the same place.
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_c, _fade]),
              builder: (context, _) => CustomPaint(
                painter: _EdgeGlowPainter(_c.value, _orbs, Curves.easeInOut.transform(_fade.value)),
                size: Size.infinite,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xxl + widget.bottomInset,
            child: TickerMode(
              enabled: _pillOn,
              child: AnimatedOpacity(
                opacity: widget.visible ? 1 : 0,
                duration: Duration(milliseconds: widget.visible ? 500 : 350),
                curve: Curves.easeOut,
                onEnd: () {
                  if (!widget.visible && mounted) setState(() => _pillOn = false);
                },
                child: Center(
                  child: _FlowText(widget.message, leading: const _TwinkleStar()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small four-point star that twinkles and slowly turns, in the colours of the rest.
class _TwinkleStar extends StatefulWidget {
  const _TwinkleStar();

  @override
  State<_TwinkleStar> createState() => _TwinkleStarState();
}

class _TwinkleStarState extends State<_TwinkleStar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _TwinkleStarPainter(_c.value)),
      ),
    );
  }
}

class _TwinkleStarPainter extends CustomPainter {
  _TwinkleStarPainter(this.t);

  final double t;

  /// Paints the sparkle. It breathes twice a loop, and its colour drifts through the palette while a smaller, paler
  /// star turns the other way inside it.
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final a = t * 2 * math.pi;
    final pulse = 0.78 + 0.22 * math.sin(2 * a);
    final r = 8.5 * pulse;

    Path star(double radius, double turn) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final ang = -math.pi / 2 + turn + i * math.pi / 4;
        final rr = i.isEven ? radius : radius * 0.27;
        final p = c + Offset(math.cos(ang), math.sin(ang)) * rr;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path..close();
    }

    final f = t * (_ringColors.length - 1);
    final i0 = f.floor() % (_ringColors.length - 1);
    final colour = Color.lerp(_ringColors[i0], _ringColors[i0 + 1], f - f.floor())!;
    _light(canvas, c, 11, colour, 0.55);
    canvas.drawPath(star(r, a * 0.5), Paint()..color = colour.withValues(alpha: 0.95));
    canvas.drawPath(star(r * 0.55, -a * 0.8 + math.pi / 4), Paint()..color = FacePalette.white.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant _TwinkleStarPainter old) => old.t != t;
}
