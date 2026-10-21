import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:lost_and_found/view/tour/search_demo.dart';
import 'package:lost_and_found/view/tour/tour_scores.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/widget/scan_square.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart'
    show bentoRects;

// The app's primary teal, and the lighter teal the chip uses for its numbers.
const Color _teal = Color(0xFF165E59);
const Color _glow = Color(0xFF7FE3CC);

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);
double _ease(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
double _out(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _lerp(double a, double b, double x) => a + (b - a) * x;

/// When each thing happens, in seconds. The whole film is a function of this clock, so it can be run, paused or shown
/// at any second.
class _Time {
  static const double tap = 1.0; // the finger presses the chip
  static const double scan = 1.25; // and the scan starts
  static const double firstPhoto = 2.75; // the first photo is read
  static const double moreFeed =
      6.4; // the chip is still reading as the camera pulls away
  static const double pullStart = 6.6;
  static const double pullEnd = 10.2;
  static const double heroFadeStart = 8.4;
  static const double heroFadeEnd = 9.6;
  static const double heroGone = 9.8;
  static const double waveStart =
      7.4; // every photo is read, from the middle outwards
  static const double barIn = 10.9; // while the last photos are still settling
  static const double fingerIn = 11.2;
  static const double tapBar = 11.8;
  static const double typeStart = 12.1;
  static const double typeLength = 1.0;
  static const double tapSend = 13.5;
  static const double chipFly = 13.6; // the words leave the bar
  static const double queryLands = 14.5; // and land among the photos
  static const double compareStart = 14.9;
  static const double ringSeconds =
      1.7; // for the ring to reach the farthest best match
  static const double othersFade = 17.1;
  static const double flightStart = 17.3;
  static const double bestLabel = 19.2;
  static const double pillsOut = 22.2;
  static const double end = 26.5;
}

const String _query = 'a dog on a beach';

/// A photo of the wall: where it is, which photo it holds, and where it lies among the others when they are placed by
/// what is in them.
class _Cell {
  _Cell(this.i, this.j, this.id, this.flip, this.rank, this.score);

  final int i, j;
  final String id;
  final bool flip;

  /// -1, or the place among the best matches.
  final int rank;
  final double score;
  double x = 0, y = 0;
  double embedAt = 0;
  double collapseAt = 0;
  double pickAt = 0;
  double thumb = 24;
  double tilt = 0;
  int cluster = 0;
  Offset spot = Offset.zero;
  double get flightAt => _Time.flightStart + 0.09 * rank;
}

/// A group of photos that are alike, with its name.
class _Place {
  _Place(this.name, this.at);

  final String name;
  final Offset at;
}

class _Camera {
  const _Camera(this.scale, this.anchorY);

  final double scale;
  final double anchorY;
}

/// How the film is laid out for the room it has.
class _Geo {
  _Geo(Size size) : w = size.width, h = size.height {
    side = math.min(w, 320.0);
    heroHeight = side + 100;
    startScale = math.min(
      1.0,
      math.min((h - bottomGap - 8) / heroHeight, w / side),
    );
    startY = 8 + side * startScale / 2;
    endY = (h - bottomGap) / 2 + 24;
    map = Rect.fromLTRB(
      14,
      barTop + barHeight + 30,
      w - 14,
      h - bottomGap - 30,
    );
    query = Offset(map.left + map.width * 0.5, map.top + map.height * 0.30);
    clear = 0.27 * math.min(map.width, map.height);
    pop = (clear * 0.42).clamp(26.0, 40.0);
    thumb = (map.width * 0.052).clamp(14.0, 20.0);
  }

  final double w, h;
  late final double side, heroHeight, startScale, startY, endY;

  /// The part of the room the photos are placed in.
  late final Rect map;

  /// Where the words land, how far round it nothing else lies, how big a photo is when it is picked, and how big it is
  /// when it lies among the others.
  late final Offset query;
  late final double clear, pop, thumb;

  static const double bottomGap = 12;
  static const double pitch = 64;
  static const double tile = 58;
  static const double endScale = 0.38;
  static const double barTop = 10;
  static const double barHeight = 48;

  Offset mapPoint(double nx, double ny) =>
      Offset(map.left + nx * map.width, map.top + ny * map.height);

  _Camera camera(double t) {
    final pull = _ease(_seg(t, _Time.pullStart, _Time.pullEnd));
    return _Camera(
      startScale * math.pow(endScale / startScale, pull).toDouble(),
      _lerp(startY, endY, pull),
    );
  }

  /// Where the results land: the usual best-match layout under the bar.
  late final List<Rect> bento = () {
    const top = barTop + barHeight + 12;
    final area = Size(w - 20, h - bottomGap - top - 4);
    return [
      for (final r in bentoRects(7, area, gap: 6))
        r.shift(const Offset(10, top)),
    ];
  }();
}

/// Page 4's film: the chip reads one photo (the app's own chip), the camera pulls back to a wall of photos that are all
/// read the same way, and the photos sort themselves into heaps of ones that are alike, as prints would on a table. A
/// search is typed, its words land among the photos, and the photos nearest to them are the answer: they come out of
/// their heaps into the result. It is the app's real animation in a few places and drawn in the app's look everywhere
/// else; nothing in it is touched, and nothing goes out of the phone.
class TourEmbedFilm extends StatefulWidget {
  const TourEmbedFilm({super.key, required this.active, this.still = false});

  /// Whether the page showing it is the current one.
  final bool active;

  /// Shows the last picture and plays nothing (animations are turned off).
  final bool still;

  @override
  State<TourEmbedFilm> createState() => _TourEmbedFilmState();
}

class _TourEmbedFilmState extends State<TourEmbedFilm>
    with SingleTickerProviderStateMixin {
  static const List<String> _bestIds = [
    'dog_beach',
    'dog_adult',
    'friends_beach',
    'puppy',
    'sunset',
    'kayak',
    'cat',
  ];
  // Where the best matches sit in the wall, as steps from the middle (the first is the photo the chip reads).
  static const List<(int, int)> _bestCells = [
    (0, 0),
    (3, 2),
    (-4, 3),
    (4, -1),
    (-2, 5),
    (-5, -1),
    (2, 6),
  ];
  // How far from the words each best match lies (as a part of the clear radius), and in which direction.
  static const List<double> _bestRadius = [
    0.30,
    0.46,
    0.58,
    0.68,
    0.78,
    0.88,
    0.97,
  ];
  static const List<double> _bestAngle = [75, 190, 10, 228, 335, 40, 262];
  static const List<String> _firstFeed = ['dog_beach'];
  static const List<String> _moreFeed = ['tajmahal', 'sunset'];

  // Where the other photos are heaped, by what is in them: the middle of each heap (steps over the map's width and
  // height).
  static const List<(String, double, double)> _places = [
    ('sport', 0.20, 0.70),
    ('food', 0.50, 0.90),
    ('people', 0.80, 0.70),
    ('landmarks', 0.88, 0.42),
    ('mountains', 0.78, 0.12),
    ('water', 0.12, 0.40),
  ];
  static const Map<String, String> _kind = {
    'v_football': 'sport',
    'pro_ronaldo': 'sport',
    'pro_sansiro': 'sport',
    'pro_fans': 'sport',
    'running': 'sport',
    'cycling': 'sport',
    'cheering': 'sport',
    'cake': 'food',
    'apple_cake': 'food',
    'v_cooking': 'food',
    'party': 'people',
    'friends_walk': 'people',
    'dance': 'people',
    'tajmahal': 'landmarks',
    'qutub': 'landmarks',
    'hike': 'mountains',
    'snow_hike': 'mountains',
    'v_tram': 'mountains',
    'houseboat': 'water',
    'v_surf': 'water',
  };

  late final TourScores _scores = TourScores.forQuery(kSampleQueries[0], [
    for (final p in kSamplePhotos) p.id,
  ]);

  Ticker? _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);
  Duration _origin = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  int _epoch = 0;

  final Map<String, ui.Image> _small = {};
  final Map<String, ui.Image> _big = {};
  final Map<String, Uint8List> _bytes = {};
  bool _ready = false;
  bool _loading = false;
  bool _gone = false;

  // The chip's state (the real chip is fed these by the film's clock).
  bool _heroOn = false;
  ScanChipMode _mode = ScanChipMode.idle;
  List<OrbitPhoto> _photos = const [];
  int _indexed = 0;
  bool _fedFirst = false, _fedMore = false;

  Size _size = Size.zero;
  _Geo? _geo;
  List<_Cell> _cells = const [];
  List<_Place> _spots = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TourEmbedFilm old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  @override
  void dispose() {
    _gone = true;
    _ticker?.dispose();
    _t.dispose();
    for (final image in [..._small.values, ..._big.values]) {
      image.dispose();
    }
    super.dispose();
  }

  Future<ui.Image> _decode(String asset, int width) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      for (final p in kSamplePhotos) {
        final image = await _decode(p.asset, 96);
        if (_gone) {
          image.dispose();
          return;
        }
        _small[p.id] = image;
      }
      for (final id in _bestIds) {
        final image = await _decode(samplePhoto(id).asset, 420);
        if (_gone) {
          image.dispose();
          return;
        }
        _big[id] = image;
      }
      for (final id in [..._firstFeed, ..._moreFeed]) {
        final data = await rootBundle.load(samplePhoto(id).asset);
        _bytes[id] = data.buffer.asUint8List();
      }
    } catch (_) {
      // Whatever could not be read is left out of the picture.
    }
    if (_gone) return;
    setState(() => _ready = true);
    _sync();
  }

  void _sync() {
    if (!mounted || !_ready) return;
    if (widget.still) {
      _t.value = 23.0;
      return;
    }
    if (widget.active) {
      _restart();
      _ticker ??= createTicker(_tick);
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
      _heroOn = false;
      _mode = ScanChipMode.idle;
      _photos = const [];
      _indexed = 0;
      _t.value = 0;
    }
  }

  void _restart() {
    _epoch++;
    _origin = _ticker?.isActive == true ? _lastElapsed : Duration.zero;
    _t.value = 0;
    _heroOn = true;
    _mode = ScanChipMode.idle;
    _photos = const [];
    _indexed = 0;
    _fedFirst = false;
    _fedMore = false;
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    _lastElapsed = elapsed;
    final t = (elapsed - _origin).inMicroseconds / 1e6;
    if (t >= _Time.end) {
      _restart();
      return;
    }
    _t.value = t;
    // The few moments the chip itself has to be told something.
    if (_heroOn) {
      if (_mode == ScanChipMode.idle && t >= _Time.scan) {
        setState(() => _mode = ScanChipMode.scanning);
      }
      if (!_fedFirst && t >= _Time.firstPhoto) {
        _fedFirst = true;
        setState(() {
          _photos = _feed(_firstFeed);
          _indexed = 1;
        });
      }
      if (!_fedMore && t >= _Time.moreFeed) {
        _fedMore = true;
        setState(() {
          _photos = [..._feed(_moreFeed), ..._photos];
          _indexed = 3;
        });
      }
      if (t >= _Time.heroGone) setState(() => _heroOn = false);
    }
  }

  List<OrbitPhoto> _feed(List<String> ids) => [
    for (final id in ids.reversed)
      if (_bytes[id] != null) OrbitPhoto(id: 'tour_$id', bytes: _bytes[id]),
  ];

  static int _hash(int a, int b) {
    var h = (a * 73856093) ^ (b * 19349663);
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0x7fffffff;
  }

  static double _gauss(math.Random r) =>
      math.sqrt(-2 * math.log(r.nextDouble() + 1e-9)) *
      math.cos(2 * math.pi * r.nextDouble());

  // The wall for this room: a grid of photos round the chip, most of them not matches, the best seven among them; and
  // where each lies when the photos are placed by what is in them.
  void _build(Size size) {
    if (size == _size && _cells.isNotEmpty) return;
    _size = size;
    final geo = _geo = _Geo(size);
    final hc = (geo.w / (2 * _Geo.endScale * _Geo.pitch)).ceil() + 1;
    final hr = (geo.h / (2 * _Geo.endScale * _Geo.pitch)).ceil() + 1;
    final others = [
      for (final p in kSamplePhotos)
        if (!_bestIds.contains(p.id) &&
            !p.id.startsWith('messi') &&
            p.id != 'v_husky')
          p.id,
    ];
    final cam = geo.camera(_Time.pullEnd);
    final centre = Offset(geo.w / 2, cam.anchorY);
    final spots = [
      for (final p in _places) _Place(p.$1, geo.mapPoint(p.$2, p.$3)),
    ];
    final rnds = [
      for (var k = 0; k < spots.length; k++) math.Random(31 * k + 7),
    ];
    final width = geo.map.width, height = geo.map.height;
    const speed = _Time.ringSeconds;
    final ringSpeed = 1.12 * geo.clear / speed;
    final cells = <_Cell>[];
    for (var j = -hr; j <= hr; j++) {
      for (var i = -hc; i <= hc; i++) {
        final rank = _bestCells.indexOf((i, j));
        final id = rank >= 0
            ? _bestIds[rank]
            : others[_hash(i, j) % others.length];
        final cell = _Cell(
          i,
          j,
          id,
          _hash(j, i) % 2 == 0 && rank < 0,
          rank,
          _scores.score(id),
        );
        cell.x = i * _Geo.pitch;
        cell.y = j * _Geo.pitch;
        final wall = Offset(
          centre.dx + cell.x * cam.scale,
          centre.dy + cell.y * cam.scale,
        );
        // Only the photos that are in the picture when the camera has pulled back are on the wall.
        final ex = (wall.dx - centre.dx) / (geo.w * 0.62);
        final ey = (wall.dy - geo.endY) / (geo.h * 0.50);
        if (rank < 0 && math.sqrt(ex * ex + ey * ey) > 0.9) continue;
        cell.thumb = geo.thumb * (0.88 + (_hash(i + 5, j + 3) % 25) / 100);
        cell.tilt = ((_hash(i + 1, j + 8) % 100) / 100 - 0.5) * 0.34;
        cell.embedAt =
            _Time.waveStart +
            math.sqrt(cell.x * cell.x + cell.y * cell.y) / 260;
        cell.collapseAt = cell.embedAt + 0.55;
        if (rank >= 0) {
          final a = _bestAngle[rank] * math.pi / 180;
          final r = _bestRadius[rank] * geo.clear * 1.15;
          cell.spot = geo.query + Offset(math.cos(a), math.sin(a)) * r;
          cell.pickAt = _Time.compareStart + r / ringSpeed;
          cell.tilt *= 0.6;
        } else {
          final k = _places.indexWhere((p) => p.$1 == (_kind[id] ?? 'people'));
          cell.cluster = k;
          // A heap: two loose piles that overlap, the photos lying where they fell.
          final r = rnds[k];
          final pile = r.nextBool() ? -1.0 : 1.0;
          var p =
              spots[k].at +
              Offset(pile * 0.04 * width, -pile * 0.012 * height) +
              Offset(_gauss(r) * 0.058 * width, _gauss(r) * 0.040 * height);
          // Nothing but the best matches lies near the words.
          final away = p - geo.query;
          if (away.distance < geo.clear * 1.45) {
            p =
                geo.query +
                away / math.max(1, away.distance) * geo.clear * 1.45;
          }
          cell.spot = Offset(
            p.dx.clamp(geo.map.left + 6, geo.map.right - 6),
            p.dy.clamp(geo.map.top + 6, geo.map.bottom - 6),
          );
        }
        cells.add(cell);
      }
    }
    // The photos lie over each other in no order, but the best seven lie on top.
    cells.sort((a, b) {
      final ra = a.rank >= 0 ? 1 : 0, rb = b.rank >= 0 ? 1 : 0;
      if (ra != rb) return ra - rb;
      return _hash(a.i + 3, a.j) % 1000 - _hash(b.i + 3, b.j) % 1000;
    });
    _cells = cells;
    _spots = spots;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        _build(box.biggest);
        final geo = _geo!;
        return ClipRect(
          child: Semantics(
            label:
                'Film: the chip reads a photo into numbers, the camera pulls back to all the photos read the same way, they sort themselves into heaps of photos that are alike, a search is turned into a place among them, and the nearest photos come first. It all happens on the phone.',
            child: ExcludeSemantics(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _FilmPainter(
                          geo: geo,
                          cells: _cells,
                          spots: _spots,
                          small: _small,
                          big: _big,
                          clock: _t,
                        ),
                      ),
                    ),
                  ),
                  if (_heroOn) _hero(geo),
                  _bar(geo),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hero(_Geo geo) {
    final chip = SizedBox(
      key: ValueKey('hero$_epoch'),
      width: geo.side,
      height: geo.heroHeight,
      child: Align(
        alignment: Alignment.topCenter,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: SquareScanHero(
            mode: _mode,
            progress: _mode == ScanChipMode.idle ? null : _indexed / 36,
            photos: _photos,
            rate: 2.5,
            stats: ScanChipStats(indexed: _indexed, total: 36),
            loadPhoto: (_) async => null,
            semanticsLabel: 'The chip reads a photo',
          ),
        ),
      ),
    );
    return Positioned(
      left: 0,
      top: 0,
      child: AnimatedBuilder(
        animation: _t,
        child: chip,
        builder: (context, child) {
          final cam = geo.camera(_t.value);
          final alpha =
              1 - _ease(_seg(_t.value, _Time.heroFadeStart, _Time.heroFadeEnd));
          final moved = Transform(
            transform: Matrix4.identity()
              ..translate(geo.w / 2, cam.anchorY)
              ..scale(cam.scale, cam.scale, 1)
              ..translate(-geo.side / 2, -geo.side / 2),
            child: child,
          );
          return alpha >= 0.999 ? moved : Opacity(opacity: alpha, child: moved);
        },
      ),
    );
  }

  Widget _bar(_Geo geo) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        if (t < _Time.barIn && !widget.still) return const SizedBox.shrink();
        final entrance = _out(_seg(t, _Time.barIn, _Time.barIn + 0.9));
        final typed =
            (_seg(t, _Time.typeStart, _Time.typeStart + _Time.typeLength) *
                    _query.length)
                .floor();
        final typing = t >= _Time.typeStart && t < _Time.tapSend;
        final focus =
            _seg(t, _Time.tapBar, _Time.tapBar + 0.25) *
            (1 - _seg(t, _Time.compareStart, _Time.compareStart + 0.8));
        final ready = _seg(
          t,
          _Time.typeStart + _Time.typeLength,
          _Time.typeStart + _Time.typeLength + 0.4,
        );
        final press =
            _seg(t, _Time.tapSend, _Time.tapSend + 0.1) *
            (1 - _seg(t, _Time.tapSend + 0.2, _Time.tapSend + 0.4));
        return Positioned(
          left: 10,
          right: 10,
          top: _lerp(-72, _Geo.barTop, entrance),
          height: _Geo.barHeight,
          child: Opacity(
            opacity: entrance,
            child: TourSearchBar(
              text: _query.substring(0, typed.clamp(0, _query.length)),
              typing: typing,
              caret: typing && (t * 2).floor().isEven,
              focus: focus,
              ready: ready,
              press: press,
            ),
          ),
        );
      },
    );
  }
}

/// Everything of the film that is drawn: the wall, the heaps it sorts itself into, the words' place, the photos that are
/// picked and fly out, and the finger.
class _FilmPainter extends CustomPainter {
  _FilmPainter({
    required this.geo,
    required this.cells,
    required this.spots,
    required this.small,
    required this.big,
    required this.clock,
  }) : super(repaint: clock);

  final _Geo geo;
  final List<_Cell> cells;
  final List<_Place> spots;
  final Map<String, ui.Image> small;
  final Map<String, ui.Image> big;
  final ValueListenable<double> clock;

  static final Map<String, TextPainter> _text = {};

  Rect _cover(ui.Image im, double aspect) {
    final iw = im.width.toDouble(), ih = im.height.toDouble();
    if (iw / ih > aspect) {
      final w = ih * aspect;
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final h = iw / aspect;
    return Rect.fromLTWH(0, (ih - h) / 2, iw, h);
  }

  TextPainter _painter(
    String text,
    double size,
    FontWeight weight,
    Color color, {
    bool mono = false,
    double spacing = 0,
  }) {
    final key =
        '$text|$size|${weight.value}|${color.toARGB32()}|$mono|$spacing';
    return _text.putIfAbsent(key, () {
      if (_text.length > 200) _text.clear();
      final base = mono
          ? TextStyle(fontFamily: 'monospace', fontSize: size)
          : GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight);
      return TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            fontWeight: weight,
            color: color,
            height: 1.25,
            letterSpacing: spacing,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final cam = geo.camera(t);
    _mat(canvas, t);
    _sweep(canvas, t, cam);
    _leaders(canvas, t);
    _photos(canvas, size, t, cam);
    _words(canvas, t);
    _flights(canvas, t);
    _finger(canvas, t);
    final fadeIn = 1 - _seg(t, 0, 0.5);
    final fadeOut = _seg(t, _Time.end - 1.2, _Time.end);
    final cover = math.max(fadeIn, fadeOut);
    if (cover > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = kTourBottom.withValues(alpha: cover),
      );
    }
  }

  // The surface the photos are sorted on: a cutting mat, with a faint grid of dots, a stronger dot every fifth, and the
  // little marks of a ruler along its four edges.
  late final Rect _matRect = Rect.fromLTRB(
    8,
    _Geo.barTop + _Geo.barHeight + 12,
    geo.w - 8,
    geo.h - _Geo.bottomGap - 8,
  );
  late final Float32List _minorDots = _dots(false);
  late final Float32List _majorDots = _dots(true);
  late final Path _ruler = _rulerPath();

  static const double _step = 12;

  Float32List _dots(bool major) {
    final out = <double>[];
    var i = 1;
    for (
      var x = _matRect.left + _step;
      x < _matRect.right - 6;
      x += _step, i++
    ) {
      var j = 1;
      for (
        var y = _matRect.top + _step;
        y < _matRect.bottom - 6;
        y += _step, j++
      ) {
        final isMajor = i % 5 == 0 && j % 5 == 0;
        if (isMajor == major) {
          out
            ..add(x)
            ..add(y);
        }
      }
    }
    return Float32List.fromList(out);
  }

  Path _rulerPath() {
    final path = Path();
    final m = _matRect;
    var i = 1;
    for (var x = m.left + _step; x < m.right - 6; x += _step, i++) {
      final len = i % 5 == 0 ? 6.0 : 3.0;
      path
        ..moveTo(x, m.top + 1)
        ..lineTo(x, m.top + 1 + len)
        ..moveTo(x, m.bottom - 1)
        ..lineTo(x, m.bottom - 1 - len);
    }
    i = 1;
    for (var y = m.top + _step; y < m.bottom - 6; y += _step, i++) {
      final len = i % 5 == 0 ? 6.0 : 3.0;
      path
        ..moveTo(m.left + 1, y)
        ..lineTo(m.left + 1 + len, y)
        ..moveTo(m.right - 1, y)
        ..lineTo(m.right - 1 - len, y);
    }
    return path;
  }

  void _mat(Canvas canvas, double t) {
    final a =
        _ease(_seg(t, _Time.pullStart + 1.6, _Time.pullEnd + 0.6)) *
        (1 - _ease(_seg(t, _Time.flightStart + 0.2, _Time.flightStart + 1.4)));
    if (a <= 0.01) return;
    final shape = RRect.fromRectAndRadius(_matRect, const Radius.circular(16));
    // The mat: a pale green-grey, a little darker at its edge, with a thin line round it.
    canvas.drawRRect(
      shape,
      Paint()..color = kTourMint.withValues(alpha: 0.2 * a),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _teal.withValues(alpha: 0.16 * a),
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      _minorDots,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5
        ..color = _teal.withValues(alpha: 0.16 * a),
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      _majorDots,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6
        ..color = _teal.withValues(alpha: 0.28 * a),
    );
    canvas.drawPath(
      _ruler,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..color = _teal.withValues(alpha: 0.26 * a),
    );
  }

  // The ring of light that goes out from the chip over the wall as each photo is read.
  void _sweep(Canvas canvas, double t, _Camera cam) {
    final r = (t - _Time.waveStart) * 260 * cam.scale;
    if (r < 2 || t > _Time.waveStart + 4.6) return;
    final a = 1 - _seg(t, _Time.waveStart + 3.4, _Time.waveStart + 4.6);
    final centre = Offset(geo.w / 2, cam.anchorY);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          r,
          [
            _glow.withValues(alpha: 0),
            _glow.withValues(alpha: 0.12 * a),
            _glow.withValues(alpha: 0),
          ],
          const [0.8, 0.98, 1.0],
        ),
    );
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.7 * a),
    );
  }

  // The thin lines from the words' place to the photos that are picked.
  void _leaders(Canvas canvas, double t) {
    if (t < _Time.compareStart) return;
    for (final cell in cells) {
      if (cell.rank < 0) continue;
      final p = _ease(_seg(t, cell.pickAt, cell.pickAt + 0.5));
      if (p <= 0) continue;
      final a = 1 - _seg(t, cell.flightAt, cell.flightAt + 0.4);
      if (a <= 0) continue;
      canvas.drawLine(
        geo.query,
        Offset.lerp(geo.query, cell.spot, p)!,
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = _teal.withValues(alpha: 0.55 * a),
      );
    }
  }

  // The photos of the wall; they sort themselves into heaps, each lying a little crooked with a thin white edge, like
  // prints on a table.
  void _photos(Canvas canvas, Size size, double t, _Camera cam) {
    final reveal = _ease(
      _seg(_seg(t, _Time.pullStart, _Time.pullEnd), 0.25, 0.75),
    );
    if (reveal <= 0) return;
    final others = _ease(_seg(t, _Time.othersFade, _Time.othersFade + 0.9));
    final focus = _ease(
      _seg(t, _Time.compareStart + 0.2, _Time.compareStart + 2.0),
    );
    final wallSize = _Geo.tile * cam.scale;
    final centre = Offset(geo.w / 2, cam.anchorY);
    final image = Paint()..filterQuality = FilterQuality.low;
    final fill = Paint();
    for (final cell in cells) {
      final best = cell.rank >= 0;
      // A best match leaves its heap when its flight starts.
      if (best && t >= cell.flightAt) continue;
      final collapse = _ease(_seg(t, cell.collapseAt, cell.collapseAt + 1.1));
      final wall = centre + Offset(cell.x * cam.scale, cell.y * cam.scale);
      var pos = Offset.lerp(wall, cell.spot, collapse)!;
      // The wall fades out towards its edges; the heaps do not.
      final ex = (wall.dx - centre.dx) / (geo.w * 0.62);
      final ey = (wall.dy - geo.endY) / (geo.h * 0.50);
      final vignette = 1 - _ease(_seg(math.sqrt(ex * ex + ey * ey), 0.62, 1.0));
      var a = _lerp(reveal * vignette, 1.0, collapse);
      if (!best) {
        a *= 1 - 0.55 * focus;
        a *= 1 - others;
      }
      if (a <= 0.01) continue;
      final read = math.sin(
        math.pi * _seg(t, cell.embedAt, cell.embedAt + 0.5),
      );
      var sz = _lerp(wallSize * (1 + 0.1 * read), cell.thumb, collapse);
      var angle = cell.tilt * collapse;
      var radius = _lerp(1.5, 3.5, collapse);
      // A best match is picked when the ring reaches it: it lifts out of its heap.
      final pick = best ? _ease(_seg(t, cell.pickAt, cell.pickAt + 0.55)) : 0.0;
      if (pick > 0) {
        pos = cell.spot;
        sz = _lerp(cell.thumb, geo.pop, pick);
        angle = cell.tilt * (1 - pick);
        radius = _lerp(3.5, 7, pick);
      }
      if (pos.dx < -sz ||
          pos.dx > size.width + sz ||
          pos.dy < -sz ||
          pos.dy > size.height + sz) {
        continue;
      }
      final photo = (best && pick > 0 ? big[cell.id] : null) ?? small[cell.id];
      if (photo == null) continue;
      final print = math.max(collapse, pick);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      final rect = Rect.fromCenter(center: Offset.zero, width: sz, height: sz);
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      if (print > 0.02) {
        // A thin white edge, and a shadow made of two faint layers.
        final edge = 1.6 * print;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge + 1.5).shift(Offset(0, 2.2 + 3 * pick)),
            Radius.circular(radius + 2),
          ),
          fill..color = Colors.black.withValues(alpha: 0.05 * a * print),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge + 0.5).shift(Offset(0, 1.2 + 1.5 * pick)),
            Radius.circular(radius + 1),
          ),
          fill..color = Colors.black.withValues(alpha: 0.11 * a * print),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(edge),
            Radius.circular(radius + 1),
          ),
          fill..color = Colors.white.withValues(alpha: a),
        );
      }
      image.color = Colors.white.withValues(alpha: a);
      canvas.save();
      canvas.clipRRect(shape);
      if (cell.flip && !best) canvas.scale(-1, 1);
      canvas.drawImageRect(photo, _cover(photo, 1), rect, image);
      // As it is read, light goes over it.
      if (read > 0 && collapse < 0.5) {
        canvas.drawRect(
          rect,
          fill..color = Colors.white.withValues(alpha: 0.38 * read * a),
        );
      }
      canvas.restore();
      canvas.restore();
      if (best && pick > 0) {
        // Its score, as a small tag, once it has been picked.
        final tag = _seg(t, cell.pickAt + 0.4, cell.pickAt + 0.8);
        if (tag > 0) {
          final text = _painter(
            cell.score.toStringAsFixed(2),
            10,
            FontWeight.w700,
            const Color(0xFF1A1D1C),
          );
          // Outside the photo, away from the words.
          final away = pos - geo.query;
          final dir = away / math.max(1, away.distance);
          final reach =
              geo.pop / 2 +
              8 +
              text.width / 2 * dir.dx.abs() +
              text.height / 2 * dir.dy.abs();
          final box = Rect.fromCenter(
            center: pos + dir * reach,
            width: text.width + 10,
            height: text.height + 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              box.shift(const Offset(0, 1)),
              Radius.circular(box.height / 2),
            ),
            Paint()..color = Colors.black.withValues(alpha: 0.10 * tag),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
            Paint()..color = Colors.white.withValues(alpha: tag),
          );
          canvas.saveLayer(
            box,
            Paint()..color = Colors.white.withValues(alpha: tag),
          );
          text.paint(canvas, Offset(box.left + 5, box.top + 1));
          canvas.restore();
        }
      }
    }
  }

  // The words: they leave the bar as a small tag, land among the photos as a pin,
  // and then a ring goes out from them and picks the nearest photos.
  void _words(Canvas canvas, double t) {
    final q = geo.query;
    if (t >= _Time.chipFly && t < _Time.queryLands) {
      final f = _ease(_seg(t, _Time.chipFly, _Time.queryLands));
      final from = Offset(geo.w / 2, _Geo.barTop + _Geo.barHeight / 2);
      final control = Offset(geo.w * 0.78, (from.dy + q.dy) / 2);
      final p =
          from * ((1 - f) * (1 - f)) +
          control * (2 * f * (1 - f)) +
          q * (f * f);
      final scale = _lerp(1, 0.16, _ease(_seg(f, 0.2, 1)));
      final label = _painter(
        _query,
        12,
        FontWeight.w600,
        const Color(0xFF1A1D1C),
      );
      final box = Rect.fromCenter(
        center: p,
        width: (label.width + 22) * scale,
        height: 28 * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.shift(Offset(0, 4 * scale)),
          Radius.circular(14 * scale),
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.16 * (1 - f))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(14 * scale)),
        Paint()..color = Colors.white.withValues(alpha: 1 - 0.4 * f),
      );
      if (scale > 0.5) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.scale(scale);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
    if (t < _Time.queryLands - 0.1) return;
    final land = _out(_seg(t, _Time.queryLands - 0.1, _Time.queryLands + 0.5));
    final out = 1 - _ease(_seg(t, _Time.flightStart, _Time.flightStart + 0.6));
    if (out <= 0) return;
    // Rings that go out from the pin while it waits.
    for (var k = 0; k < 2; k++) {
      if (t >= _Time.compareStart) break;
      final p = ((t - _Time.queryLands) / 1.8 + k * 0.5) % 1.0;
      canvas.drawCircle(
        q,
        6 + 26 * _out(p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _teal.withValues(alpha: 0.4 * (1 - p) * land * out),
      );
    }
    // The ring that picks the nearest photos.
    if (t >= _Time.compareStart) {
      final r = (t - _Time.compareStart) * 1.12 * geo.clear / _Time.ringSeconds;
      final ring =
          1 - _seg(t, _Time.compareStart + 2.0, _Time.compareStart + 2.9);
      if (r > 3 && ring > 0) {
        canvas.drawCircle(
          q,
          r,
          Paint()..color = _teal.withValues(alpha: 0.05 * ring),
        );
        canvas.drawCircle(
          q,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = _teal.withValues(alpha: 0.7 * ring),
        );
      }
    }
    // The pin: a white head with a teal middle, standing on a small shadow.
    canvas.drawCircle(
      q + const Offset(0, 2),
      8.5 * land,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25 * out)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      q,
      8 * land,
      Paint()..color = Colors.white.withValues(alpha: out),
    );
    canvas.drawCircle(
      q,
      5.2 * land,
      Paint()..color = _teal.withValues(alpha: out),
    );
    canvas.drawCircle(
      q,
      1.8 * land,
      Paint()..color = Colors.white.withValues(alpha: out),
    );
  }

  // The best matches leave their heaps for the places of the result.
  void _flights(Canvas canvas, double t) {
    if (t < _Time.flightStart - 0.4) return;
    final bento = geo.bento;
    final fadeOut = 1 - _seg(t, _Time.end - 1.2, _Time.end);
    for (final cell in cells) {
      if (cell.rank < 0) continue;
      final f = _ease(_seg(t, cell.flightAt, cell.flightAt + 1.1));
      if (f <= 0) continue;
      final from = Rect.fromCenter(
        center: cell.spot,
        width: geo.pop,
        height: geo.pop,
      );
      final to = bento[cell.rank];
      final rect = Rect.lerp(
        from,
        to,
        f,
      )!.shift(Offset(0, -math.sin(f * math.pi) * 26));
      final image = big[cell.id] ?? small[cell.id];
      if (image == null) continue;
      final shape = RRect.fromRectAndRadius(
        rect,
        Radius.circular(_lerp(7, 14, f)),
      );
      canvas.drawRRect(
        shape.shift(Offset(0, 5 * f)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * f)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * f + 0.1),
      );
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawImageRect(
        image,
        _cover(image, rect.width / rect.height),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      // Its score, and which one is the best.
      final pill =
          _seg(t, cell.flightAt + 1.2, cell.flightAt + 1.6) *
          (1 - _seg(t, _Time.pillsOut, _Time.pillsOut + 0.6)) *
          fadeOut;
      if (pill > 0) {
        final text = _painter(
          cell.score.toStringAsFixed(2),
          cell.rank == 0 ? 12.5 : 10.5,
          FontWeight.w700,
          const Color(0xFF1A1D1C),
        );
        final padX = cell.rank == 0 ? 8.0 : 5.0;
        final box = Rect.fromLTWH(
          rect.right - text.width - padX * 2 - 4,
          rect.bottom - text.height - 7,
          text.width + padX * 2,
          text.height + 3,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
          Paint()..color = Colors.white.withValues(alpha: pill),
        );
        canvas.saveLayer(
          box,
          Paint()..color = Colors.white.withValues(alpha: pill),
        );
        text.paint(canvas, Offset(box.left + padX, box.top + 1.5));
        canvas.restore();
      }
      if (cell.rank == 0) {
        final label = _seg(t, _Time.bestLabel, _Time.bestLabel + 0.4);
        if (label > 0) {
          final text = _painter(
            'Best match',
            10.5,
            FontWeight.w500,
            Colors.white,
          );
          final box = Rect.fromLTWH(
            rect.left + 8,
            rect.bottom - text.height - 18,
            text.width + 20,
            text.height + 8,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
            Paint()..color = Colors.black.withValues(alpha: 0.5 * label),
          );
          canvas.saveLayer(
            box.inflate(2),
            Paint()..color = Colors.white.withValues(alpha: label),
          );
          text.paint(canvas, Offset(box.left + 10, box.top + 4));
          canvas.restore();
        }
      }
    }
  }

  // A finger that taps the chip, and later the search bar and its button.
  void _finger(Canvas canvas, double t) {
    final chip = Offset(geo.w / 2, geo.startY);
    final middle = _Geo.barTop + _Geo.barHeight / 2;
    final bar = Offset(geo.w * 0.34, middle);
    final send = Offset(geo.w - 33, middle);
    Offset? at;
    var alpha = 0.0;
    var down = 0.0;
    var presses = <double>[];
    if (t >= 0.2 && t <= 1.8) {
      at = Offset.lerp(
        Offset(geo.w * 0.9, geo.h * 0.8),
        chip,
        _ease(_seg(t, 0.2, 0.95)),
      );
      alpha = _seg(t, 0.2, 0.45) * (1 - _seg(t, 1.4, 1.8));
      presses = [_Time.tap];
    } else if (t >= _Time.fingerIn && t <= _Time.tapSend + 0.7) {
      final toBar = _ease(_seg(t, _Time.fingerIn, _Time.tapBar - 0.05));
      final toSend = _ease(_seg(t, _Time.tapBar + 0.6, _Time.tapSend - 0.05));
      at = Offset.lerp(
        Offset.lerp(Offset(geo.w * 0.9, geo.h * 0.55), bar, toBar)!,
        send,
        toSend,
      );
      alpha =
          _seg(t, _Time.fingerIn, _Time.fingerIn + 0.25) *
          (1 - _seg(t, _Time.tapSend + 0.35, _Time.tapSend + 0.7));
      presses = [_Time.tapBar, _Time.tapSend];
    }
    if (at == null || alpha <= 0) return;
    for (final p in presses) {
      down = math.max(
        down,
        _seg(t, p, p + 0.12) * (1 - _seg(t, p + 0.22, p + 0.4)),
      );
    }
    final r = 16 * (1 - 0.18 * down);
    canvas.drawCircle(
      at + const Offset(0, 3),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      at,
      r,
      Paint()..color = Colors.white.withValues(alpha: 0.82 * alpha),
    );
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _teal.withValues(alpha: 0.55 * alpha),
    );
    for (final p in presses) {
      final ring = _seg(t, p, p + 0.55);
      if (ring > 0 && ring < 1) {
        canvas.drawCircle(
          at,
          16 + 34 * _out(ring),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _teal.withValues(alpha: 0.5 * (1 - ring)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FilmPainter old) =>
      old.cells != cells || old.geo != geo;
}
