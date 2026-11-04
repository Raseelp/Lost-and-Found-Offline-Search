import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:lost_and_found/view/splash/splash_timeline.dart';

/// Draws the splash for the moment the animation is at. All the numbers come from [SplashFrame]; this only
/// turns them into shapes. The icon is drawn on its own 108 unit canvas and scaled to the screen.
class SplashPainter extends CustomPainter {
  SplashPainter(this.progress, {required this.ambient, required this.devicePixelRatio}) : super(repaint: Listenable.merge([progress, ambient]));

  /// 0 to 1 over [SplashTimeline.totalMs].
  final Animation<double> progress;

  /// Real time since the splash began, 0 to 1 over [ambientSpanMs]. It runs on while the main clock waits for the
  /// app, so the sky keeps drifting and the screen never looks stuck.
  final Animation<double> ambient;

  static const double ambientSpanMs = 3600000;

  /// The ambient time in the main clock's own units: equal to it for as long as the main clock has not waited.
  double get _ambientT => ambient.value * ambientSpanMs / SplashTimeline.slowdown;

  /// The screen's pixels per logical pixel, for the picture of the cover that is made once.
  final double devicePixelRatio;

  /// The sky behind the tile once the lens is out, as one picture made once (see [_bakeCover]), so that each frame
  /// draws one filled shape instead of a clip and five soft circles.
  ui.Image? _cover;
  ui.ImageShader? _coverShader;
  Size? _coverSize;

  /// Set when the graphics layer refused to make [_cover]. The cover is then drawn live, through a clip.
  bool _coverFailed = false;

  /// The gradient of the sky, which only depends on the screen's height.
  ui.Shader? _skyShader;
  double _skyShaderHeight = 0;

  static const double _iconPx = 170;
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _teal = Color(0xFF165E59);

  /// The shaders are in canvas units, so they are made once and work at any scale.
  static const Rect _canvas = Rect.fromLTWH(0, 0, 108, 108);
  static final ui.Shader _skyOld = ui.Gradient.linear(_canvas.topLeft, _canvas.bottomLeft, const [Color(0xFF4FB8FF), Color(0xFFB9E6FF)], const [0, 0.7]);
  static final ui.Shader _skyNew = ui.Gradient.linear(_canvas.topLeft, _canvas.bottomLeft, const [Color(0xFFFAFBFA), Color(0xFFDCEBE7)], const [0, 0.7]);

  static final Path _hill1 = Path()
    ..moveTo(0, 68.04)
    ..cubicTo(21.6, 57.24, 39.96, 56.16, 57.24, 61.56)
    ..cubicTo(75.6, 66.96, 89.64, 64.8, 108, 56.16)
    ..lineTo(108, 108)
    ..lineTo(0, 108)
    ..close();
  static final Path _hill2 = Path()
    ..moveTo(0, 108)
    ..lineTo(0, 84.24)
    ..cubicTo(24.84, 76.68, 45.36, 77.76, 62.64, 81)
    ..cubicTo(79.92, 84.24, 95.04, 83.16, 108, 78.84)
    ..lineTo(108, 108)
    ..close();

  /// The f and the l, on their own canvas (see [_toLetters]), and the crossbar.
  static final Path _letters = Path()
    ..moveTo(34, 26)
    ..lineTo(34, 58)
    ..arcToPoint(const Offset(45, 69), radius: const Radius.circular(11), clockwise: false)
    ..moveTo(60, 78)
    ..lineTo(60, 44)
    ..arcToPoint(const Offset(72, 32), radius: const Radius.circular(12))
    ..moveTo(51, 53)
    ..lineTo(70, 53);
  static const Rect _letterBounds = Rect.fromLTRB(24, 18, 88, 84);

  /// The two arrows on the slider's handle, around its centre.
  static final Path _arrows = Path()
    ..moveTo(-1.1, -1.6)
    ..lineTo(-2.7, 0)
    ..lineTo(-1.1, 1.6)
    ..moveTo(1.1, -1.6)
    ..lineTo(2.7, 0)
    ..lineTo(1.1, 1.6);

  static final RRect _window = RRect.fromLTRBR(18, 18, 90, 90, const Radius.circular(16));

  /// The sky behind the icon: pale blue fading to white by the bottom, with soft white clouds and fine hill lines
  /// drifting across the lower part.
  static const List<Color> _skyColours = [Color(0xFFBFE3FF), Color(0xFFE6F4FF), Color(0xFFFFFFFF)];
  static const List<double> _skyStops = [0, 0.5, 0.85];
  /// Each cloud as where it is (fractions of the screen), its size (on a 360 wide screen) and how strong it is.
  static const List<({double x, double y, double size, double strength})> _clouds = [
    (x: 70 / 360, y: 150 / 780, size: 120, strength: 0.9),
    (x: 290 / 360, y: 260 / 780, size: 140, strength: 0.85),
    (x: 160 / 360, y: 560 / 780, size: 150, strength: 0.7),
  ];
  static const Color _lineColour = Color(0xFF2E7FB8);

  /// Where the big lens goes, as fractions of the screen: over the top (the search field, the stories), then the
  /// middle (the photos), where it widens from.
  static const Pt _tripTop = (x: 118 / 360, y: 200 / 780);
  static const Pt _tripMiddle = (x: 252 / 360, y: 440 / 780);

  /// The shadow along the letters, drawn once into a picture for each side of the slider. It never changes, so a
  /// layer per frame would be wasted work.
  static ui.Image? _rimOld;
  static ui.Image? _rimNew;
  static const double _rimScale = 4;
  static const Color _rimOldColour = Color(0x4D0B3B50);
  static const Color _rimNewColour = Color(0x5904201D);

  /// Works out the shared shapes before the animation starts, so that the first frames do not have to. Without the
  /// letters' shadow they are a little flatter, and the splash goes on.
  static void warmUp() {
    _skyOld;
    _skyNew;
    try {
      _rimOld ??= _makeRim(_rimOldColour);
      _rimNew ??= _makeRim(_rimNewColour);
    } catch (e) {
      debugPrint('splash: could not make the letters shadow: $e');
    }
  }

  /// The letters minus themselves moved down a little, in [colour], on the area of [_letterBounds].
  static ui.Image _makeRim(Color colour) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_rimScale);
    canvas.translate(-_letterBounds.left, -_letterBounds.top);
    final bounds = _letterBounds;
    canvas.saveLayer(bounds, Paint());
    canvas.save();
    _toLettersOn(canvas);
    canvas.drawPath(_letters, _strokePaint(_white, 12));
    canvas.restore();
    canvas.save();
    canvas.translate(0, 1.87);
    _toLettersOn(canvas);
    canvas.drawPath(_letters, _strokePaint(_white, 12)..blendMode = BlendMode.clear);
    canvas.restore();
    canvas.drawRect(bounds, Paint()
      ..color = colour
      ..blendMode = BlendMode.srcIn);
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync((bounds.width * _rimScale).round(), (bounds.height * _rimScale).round());
    picture.dispose();
    return image;
  }

  /// Draws the frame for [progress]: the sky with the tile and the icon on it, and once the lens is out, the cover
  /// with a round hole where the lens is, so the app shows through.
  /// The hole stays open to the end, or the cover would show again for a moment, so its radius aims well past the
  /// farthest corner. It is cut at the middle of the ring's stroke, so the ring always covers its edge. The cover
  /// picture is made by [prepare] while the animation waited, and drawn live in the same shape without one.
  @override
  void paint(Canvas canvas, Size size) {
    final f = SplashFrame(progress.value * SplashTimeline.totalMs);
    final centre = Offset(size.width / 2, size.height * 0.487);
    final iconPx = _iconPx < size.width * 0.5 ? _iconPx : size.width * 0.5;
    final unit = iconPx / 72;

    Offset? lensAt;
    var lensR = 0.0;
    if (f.t >= SplashTimeline.lensStartMs) {
      Pt at(Pt p) => (x: p.x * size.width, y: p.y * size.height);
      final start = (x: centre.dx + (52.5 - 54) * unit, y: centre.dy + (51 - 54) * unit);
      final open = at(_tripMiddle);
      final p = tripAt(f.trip, [start, at(_tripTop), open]);
      lensAt = Offset(p.x, p.y);
      final reach = [(0.0, 0.0), (size.width, 0.0), (0.0, size.height), (size.width, size.height)]
          .map((c) => math.sqrt(math.pow(c.$1 - open.x, 2) + math.pow(c.$2 - open.y, 2)))
          .reduce(math.max);
      lensR = lerp(lerp(12.5 * unit, 30.6 * unit, f.lensGrow), reach * 1.5 + 8 * unit, f.widen);
    }

    final amb = _ambientT;
    if (f.t >= SplashTimeline.coverBakedMs && !_coverFailed && (_cover == null || _coverSize != size)) _bakeCover(size, amb);
    if (f.t < SplashTimeline.coverBakedMs) {
      _background(canvas, size, amb);
      if (f.iconOpacity > 0) {
        canvas.save();
        canvas.translate(centre.dx, centre.dy);
        canvas.scale(unit * f.iconScale);
        canvas.translate(-54, -54);
        final fade = f.iconOpacity < 1;
        if (fade) canvas.saveLayer(_canvas, Paint()..color = _white.withValues(alpha: f.iconOpacity));
        _icon(canvas, f);
        if (fade) canvas.restore();
        canvas.restore();
      }
    } else {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size);
      final holeR = lensR * f.holeOpen;
      if (lensAt != null && holeR > 0) path.addOval(Rect.fromCircle(center: lensAt, radius: holeR));
      final shader = _coverShader;
      if (shader != null) {
        canvas.drawPath(path, Paint()..shader = shader);
      } else {
        canvas.save();
        canvas.clipPath(path);
        _background(canvas, size, amb);
        canvas.restore();
      }
    }

    if (lensAt != null && f.lensOpacity > 0) _bigLens(canvas, lensAt, lensR, unit, f.lensOpacity);
  }

  /// Makes the picture of the cover for a screen of [size], so that no frame has to. It is made as the sweep
  /// starts, drawn as the sky will be when the cover is switched to it (the sky drifts on until then at the pace
  /// of the clocks, so that can be worked out), and the switch then shows no jump.
  void prepare(Size size) {
    if (_coverFailed) return;
    final until = SplashTimeline.coverBakedMs - progress.value * SplashTimeline.totalMs;
    _bakeCover(size, _ambientT + until);
  }

  /// Draws the sky as it is at [ambientT] into one picture, the size of the screen in pixels.
  void _bakeCover(Size size, double ambientT) {
    _releaseCover();
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(devicePixelRatio);
      _background(canvas, size, ambientT);
      final picture = recorder.endRecording();
      final image = picture.toImageSync((size.width * devicePixelRatio).ceil(), (size.height * devicePixelRatio).ceil());
      picture.dispose();
      final scale = 1 / devicePixelRatio;
      _coverShader = ui.ImageShader(image, TileMode.clamp, TileMode.clamp, Float64List.fromList([scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
      _cover = image;
      _coverSize = size;
    } catch (e) {
      _coverFailed = true;
      debugPrint('splash: could not make the cover picture: $e');
    }
  }

  void _releaseCover() {
    _coverShader?.dispose();
    _coverShader = null;
    _cover?.dispose();
    _cover = null;
  }

  /// Lets go of everything the painter holds on to in the graphics layer.
  void dispose() {
    _releaseCover();
    _skyShader?.dispose();
    _skyShader = null;
    _rimOld?.dispose();
    _rimOld = null;
    _rimNew?.dispose();
    _rimNew = null;
  }

  /// Everything behind the tile at time [t]: white, the sky, the clouds and the seven fine hill lines.
  ///
  /// The sky fades in from the white the system showed before. The lines keep their shape on a wide screen (a phone
  /// on its side) instead of tangling.
  void _background(Canvas canvas, Size size, double t) {
    final scale = size.width / 360;
    final sy = size.height / 780;
    final fine = math.min(scale, sy);
    final fade = seg(t, 0, 600);
    canvas.drawRect(Offset.zero & size, Paint()..color = _white);
    if (fade <= 0) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = _skyFor(size.height),
    );
    if (fade < 1) canvas.drawRect(Offset.zero & size, Paint()..color = _white.withValues(alpha: 1 - fade));

    for (var i = 0; i < _clouds.length; i++) {
      final a = _clouds[i];
      final centre = Offset(a.x * size.width + 40 * scale * math.sin(t / 2600 + i * 2), a.y * size.height);
      final r = a.size * scale;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = ui.Gradient.radial(centre, r, [
            _white.withValues(alpha: a.strength * fade),
            _white.withValues(alpha: 0),
          ]),
      );
    }

    final lines = seg(t, 0, 700);
    for (var i = 0; i < 7; i++) {
      final base = (470 + i * 42) * sy;
      final amp = (14 + i * 3) * fine;
      final phase = t / (2400 - i * 160) * (i.isOdd ? 1 : -1) + i * 1.3;
      final path = Path();
      for (var x = -10; x <= 370; x += 10) {
        final y = base + amp * math.sin(x / (60 + i * 8) + phase) + amp * 0.4 * math.sin(x / 23 - phase);
        if (x == -10) {
          path.moveTo(x * scale, y);
        } else {
          path.lineTo(x * scale, y);
        }
      }
      canvas.drawPath(
        path,
        _stroke(_lineColour.withValues(alpha: (0.1 + 0.03 * i) * lines), math.max(1, 1.3 * fine)),
      );
    }
  }

  ui.Shader _skyFor(double height) {
    if (_skyShader == null || _skyShaderHeight != height) {
      _skyShader?.dispose();
      _skyShader = ui.Gradient.linear(Offset.zero, Offset(0, height), _skyColours, _skyStops);
      _skyShaderHeight = height;
    }
    return _skyShader!;
  }

  /// The big lens: a teal ring and its handle.
  void _bigLens(Canvas canvas, Offset at, double r, double unit, double opacity) {
    final paint = _stroke(_teal.withValues(alpha: opacity), 3 * unit);
    canvas.drawCircle(at, r, paint);
    const k = 0.7071;
    final from = at + Offset(r * k, r * k);
    canvas.drawLine(from, from + Offset(r * 0.62 * k, r * 0.62 * k), paint);
  }

  /// The icon on its 108 unit canvas. The old look is on the right of the slider and the new look on the left: the
  /// sky and hills, then the letters (white on the old side, teal on the new), then the slider with its round handle
  /// and two small arrows.
  void _icon(Canvas canvas, SplashFrame f) {
    final split = f.splitX;
    canvas.save();
    canvas.clipRRect(_window);

    canvas.drawRect(_canvas, Paint()..shader = _skyOld);
    _newSide(canvas, split, () => canvas.drawRect(_canvas, Paint()..shader = _skyNew));
    _hill(canvas, _hill1, split, const Color(0xFF46B37B), const Color(0xFFA9D6CE));
    _hill(canvas, _hill2, split, const Color(0xFF2E8E5E), const Color(0xFF6FB8AC));

    void letters(Color colour) {
      canvas.save();
      _toLetters(canvas);
      canvas.drawPath(_letters, _stroke(colour, 12));
      canvas.restore();
    }

    _oldSide(canvas, split, () => letters(_white));
    _newSide(canvas, split, () => letters(_teal));
    _rim(canvas, split);

    if (f.lineOpacity > 0) {
      canvas.drawRect(Rect.fromLTWH(split - 0.8, 0, 1.6, 108), Paint()..color = _white.withValues(alpha: f.lineOpacity));
      canvas.save();
      canvas.translate(split, 27);
      canvas.drawCircle(Offset.zero, 4.6, Paint()..color = _white.withValues(alpha: f.lineOpacity));
      canvas.drawPath(_arrows, _stroke(_teal.withValues(alpha: f.lineOpacity), 1));
      canvas.restore();
    }
    canvas.restore();

    canvas.drawRRect(_window, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFFCBD6D2));
  }

  void _hill(Canvas canvas, Path hill, double split, Color old, Color fresh) {
    canvas.drawPath(hill, Paint()..color = old);
    _newSide(canvas, split, () => canvas.drawPath(hill, Paint()..color = fresh));
  }

  void _newSide(Canvas canvas, double split, VoidCallback draw) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, split, 108));
    draw();
    canvas.restore();
  }

  void _oldSide(Canvas canvas, double split, VoidCallback draw) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(split, 0, 108, 108));
    draw();
    canvas.restore();
  }

  void _toLetters(Canvas canvas) => _toLettersOn(canvas);

  /// Puts the letters on the icon: moved to its middle, scaled to 0.72 and moved back by 52.
  static void _toLettersOn(Canvas canvas) {
    canvas.translate(54, 54);
    canvas.scale(0.72);
    canvas.translate(-52, -52);
  }

  Paint _stroke(Color colour, double width) => _strokePaint(colour, width);

  static Paint _strokePaint(Color colour, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = colour;

  /// The thin shadow along the upper edge of the letters, in the colour of the side of the slider it is on.
  void _rim(Canvas canvas, double split) {
    final old = _rimOld, fresh = _rimNew;
    if (old == null || fresh == null) return;
    final paint = Paint()..filterQuality = FilterQuality.low;
    void side(ui.Image image) => canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), _letterBounds, paint);
    _oldSide(canvas, split, () => side(old));
    _newSide(canvas, split, () => side(fresh));
  }

  @override
  bool shouldRepaint(SplashPainter oldDelegate) => oldDelegate.progress != progress;
}
