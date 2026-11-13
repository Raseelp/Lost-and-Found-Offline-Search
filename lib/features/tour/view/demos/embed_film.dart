import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_palette.dart';
import 'package:lost_and_found/features/tour/view/demos/search_demo.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_scores.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_samples.dart';
import 'package:lost_and_found/features/library/view/widgets/library_orbit.dart';
import 'package:lost_and_found/features/library/view/widgets/scan_steps.dart';
import 'package:lost_and_found/features/library/view/widgets/start_indexing_button.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_preview.dart'
    show bentoRects;
part 'embed_film/shared.dart';
part 'embed_film/time.dart';
part 'embed_film/geo.dart';
part 'embed_film/film_painter.dart';

/// Page 4's film: a finger starts a scan and the app's own scan card reads one photo, the camera pulls back to a wall of
/// photos that are all read the same way, and the photos sort themselves into heaps of ones that are alike, as prints would on a table. A
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
  /// Where the best matches sit in the wall, as steps from the middle. The first is the photo the chip reads.
  static const List<(int, int)> _bestCells = [
    (0, 0),
    (3, 2),
    (-4, 3),
    (4, -1),
    (-2, 5),
    (-5, -1),
    (2, 6),
  ];
  /// How far from the words each best match lies, as a part of the clear radius. [_bestAngle] gives the direction.
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

  /// Where the other photos are heaped, by what is in them: the middle of each heap, as a part of the map's width and
  /// height.
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

  /// The scan card's state. The real card is fed these by the film's clock.
  bool _heroOn = false;
  bool _running = false;
  List<String> _photoIds = const [];
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
      _running = false;
      _photoIds = const [];
      _indexed = 0;
      _t.value = 0;
    }
  }

  void _restart() {
    _epoch++;
    _origin = _ticker?.isActive == true ? _lastElapsed : Duration.zero;
    _t.value = 0;
    _heroOn = true;
    _running = false;
    _photoIds = const [];
    _indexed = 0;
    _fedFirst = false;
    _fedMore = false;
    if (mounted) setState(() {});
  }

  /// Moves the film to [elapsed]. The card has to be told something only at a few moments, and they are handled here.
  void _tick(Duration elapsed) {
    _lastElapsed = elapsed;
    final t = (elapsed - _origin).inMicroseconds / 1e6;
    if (t >= _Time.end) {
      _restart();
      return;
    }
    _t.value = t;
    if (_heroOn) {
      if (!_running && t >= _Time.scan) {
        setState(() => _running = true);
      }
      if (!_fedFirst && t >= _Time.firstPhoto) {
        _fedFirst = true;
        setState(() {
          _photoIds = _feed(_firstFeed);
          _indexed = 1;
        });
      }
      if (!_fedMore && t >= _Time.moreFeed) {
        _fedMore = true;
        setState(() {
          _photoIds = [..._feed(_moreFeed), ..._photoIds];
          _indexed = 3;
        });
      }
      if (t >= _Time.heroGone) setState(() => _heroOn = false);
    }
  }

  List<String> _feed(List<String> ids) => [
    for (final id in ids.reversed)
      if (_bytes[id] != null) id,
  ];

  static int _hash(int a, int b) {
    var h = (a * 73856093) ^ (b * 19349663);
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0x7fffffff;
  }

  static double _gauss(math.Random r) =>
      math.sqrt(-2 * math.log(r.nextDouble() + 1e-9)) *
      math.cos(2 * math.pi * r.nextDouble());

  /// Makes the wall for this room: a grid of photos round the chip, most of them not matches, the best seven among
  /// them; and where each lies when the photos are placed by what is in them. Only the photos that are in the picture
  /// when the camera has pulled back are on the wall. The photos of a heap lie in two loose piles that overlap, where
  /// they fell, and nothing but the best matches lies near the words. The photos lie over each other in no order,
  /// but the best seven lie on top.
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
          final r = rnds[k];
          final pile = r.nextBool() ? -1.0 : 1.0;
          var p =
              spots[k].at +
              Offset(pile * 0.04 * width, -pile * 0.012 * height) +
              Offset(_gauss(r) * 0.058 * width, _gauss(r) * 0.040 * height);
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
                'Film: a scan reads a photo into numbers, the camera pulls back to all the photos read the same way, they sort themselves into heaps of photos that are alike, a search is turned into a place among them, and the nearest photos come first. It all happens on the phone.',
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
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _FilmPainter(
                          geo: geo,
                          cells: const [],
                          spots: const [],
                          small: const {},
                          big: const {},
                          clock: _t,
                          fingerOnly: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The scan card with its button under it, moved and scaled by the camera. It is always wrapped in an [Opacity].
  /// Switching to one only when the fade begins replaces the card's whole subtree (fresh state, built and started from
  /// scratch) in the middle of the pull-back, which shows as a hitch. At full opacity it paints the child directly, with
  /// no layer.
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScanStepsCard(
                processed: _indexed,
                total: 36,
                searchable: _indexed,
                people: 0,
                faceWork: false,
                findingFaces: false,
                tuning: false,
                faceFraction: 0,
                batchPhotos: 0,
                idle: !_running,
                photoRate: _running ? 2.5 : null,
                photoIds: _photoIds,
                loadPhoto: (id) async => _bytes[id] ?? Uint8List(0),
                semanticsLabel: 'A scan reads a photo',
              ),
              const SizedBox(height: _Geo.buttonGap),
              Center(
                child: _running
                    ? OrbitPill(label: 'Stop indexing', icon: Icons.stop_rounded, onTap: () {})
                    : StartIndexingButton(onPressed: () {}),
              ),
            ],
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
              ..translate(-geo.side / 2, -geo.heroHeight / 2),
            child: child,
          );
          return Opacity(opacity: alpha.clamp(0.0, 1.0), child: moved);
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
