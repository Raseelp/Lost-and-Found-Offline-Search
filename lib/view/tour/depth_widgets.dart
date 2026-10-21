import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';
import 'package:video_player/video_player.dart';

/// The first screen's picture: the app's widgets (a video, "On this day", people, Then & now, a memory, search,
/// privacy) floating at different depths. Far ones are small and soft, near ones large and sharp. They take
/// turns: one at a time glides forward, grows sharp and moves in towards the middle while the one before it
/// drifts back. Everything is one continuous motion, so nothing jumps. Plays while its page is showing.
class DepthWidgets extends StatefulWidget {
  const DepthWidgets({super.key, required this.active});

  final bool active;

  @override
  State<DepthWidgets> createState() => _DepthWidgetsState();
}

/// One floating widget: where it rests (as shares of the picture's width and height), how big it is at the
/// reference size, and how near it is when it is not having its turn (0 far, 1 near).
class _Spec {
  const _Spec(this.cx, this.cy, this.w, this.h, this.depth, this.build);

  final double cx, cy, w, h, depth;
  final Widget Function(BuildContext context, _Turn turn) build;
}

/// Where a widget is in its turn, for the ones that do something while they are at the front.
class _Turn {
  const _Turn(this.depth, this.focus, this.d, this.t);

  /// 0 far, 1 near (a mix of its resting depth and how far forward it has come).
  final double depth;

  /// 0 when it is back, 1 at the middle of its turn.
  final double focus;

  /// Turns before (negative) or after (positive) the middle of its turn.
  final double d;

  /// Where the whole loop is, 0 to 1.
  final double t;
}

class _DepthWidgetsState extends State<DepthWidgets>
    with SingleTickerProviderStateMixin {
  // Each widget has a turn of this long; the loop is every widget once.
  static const Duration _turn = Duration(milliseconds: 2600);

  // In the order of their turns, which jump from one side of the picture to the other so the one coming
  // forward and the one going back are never next to each other.
  // Kept by key because the widget around it changes (it is blurred only while it is far), which would
  // otherwise throw its player away in the middle of its turn.
  final GlobalKey<_VideoCardState> _videoKey = GlobalKey();

  late final List<_Spec> _specs = [
    _Spec(
      0.26,
      0.5,
      150,
      105,
      0.62,
      (c, t) =>
          _VideoCard(key: _videoKey, turn: t, awake: widget.active && !_still),
    ),
    _Spec(0.76, 0.05, 152, 46, 0.14, (c, t) => const _PrivacyCard()),
    _Spec(0.27, 0.8, 150, 100, 0.3, (c, t) => const _SearchResultsCard()),
    _Spec(0.77, 0.23, 112, 112, 0.5, (c, t) => _ThenNowCard(turn: t)),
    _Spec(0.24, 0.2, 150, 105, 0.62, (c, t) => const _DayCard()),
    _Spec(0.74, 0.79, 172, 56, 0.2, (c, t) => const _NoteCard()),
    _Spec(0.76, 0.53, 150, 50, 0.62, (c, t) => const _PeopleCard()),
  ];

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _turn * _specs.length,
  );

  // When the phone asks for no animations the picture stands still (and nothing keeps ticking).
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant DepthWidgets old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !_still && !_c.isAnimating) {
      _c.repeat();
    } else if ((!widget.active || _still) && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _smooth(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  Widget build(BuildContext context) {
    final still = _still;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth,
            h = box.maxHeight.isFinite ? box.maxHeight : 260.0;
        final k = math.min(w / 300, h / 300);
        return still
            ? _stage(w, h, k, 0.12)
            : AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _stage(w, h, k, _c.value),
              );
      },
    );
  }

  // How much room to keep between two widgets, and from the edge, so shadows and softness are not cut.
  static const double _gap = 8;

  Widget _stage(double w, double h, double k, double t) {
    final n = _specs.length;
    final phase = t * n;
    final turns = List<_Turn>.filled(n, const _Turn(0, 0, 0, 0));
    final sizes = List<Size>.filled(n, Size.zero);
    final centres = List<Offset>.filled(n, Offset.zero);
    final moves = List<double>.filled(n, 1);
    for (var i = 0; i < n; i++) {
      final s = _specs[i];
      // How far this widget's turn is from now, going round the loop.
      var d = (phase - i - 0.5) % n;
      if (d > n / 2) d -= n;
      // 1 at the middle of its turn, easing to 0 a turn and a bit away either side.
      final focus = _smooth(1 - d.abs() / 1.25);
      final depth = s.depth + (1 - s.depth) * focus;
      // Floating: a slow loop, a different one for each widget.
      // Whole numbers of cycles per loop, so the end of the loop meets its start.
      final ax = 2 * math.pi * (t * 3 + i * 0.37);
      final ay = 2 * math.pi * (t * 2 + i * 0.53);
      final drift = Offset(math.sin(ax) * 4 * k, math.cos(ay) * 3 * k);
      // A focused widget glides in a little towards the middle.
      final rest = Offset(s.cx * w, s.cy * h);
      final centre = Offset(w * 0.5, h * 0.5);
      final scale = (0.7 + 0.3 * depth) * k;
      turns[i] = _Turn(depth, focus, d, t);
      sizes[i] = Size(s.w * scale, s.h * scale);
      centres[i] = Offset.lerp(rest, centre, 0.25 * focus)! + drift;
      // The one coming forward holds its ground; the others make room.
      moves[i] = 1.2 - depth;
    }
    _makeRoom(centres, sizes, moves, w, h, _gap * math.min(1.0, k));
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => turns[a].depth.compareTo(turns[b].depth));
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final i in order)
            _placed(i, _specs[i], centres[i], sizes[i], turns[i]),
        ],
      ),
    );
  }

  /// Nudges the widgets apart so none ever overlaps another, which also means it does not matter which is
  /// painted on top: a widget coming forward never slides over (or out from under) another. The push grows with
  /// how far two are into each other, so it is as smooth as the motion itself. Also keeps all inside the picture.
  static void _makeRoom(
    List<Offset> c,
    List<Size> sz,
    List<double> moves,
    double w,
    double h,
    double gap,
  ) {
    final n = c.length;
    for (var pass = 0; pass < 10; pass++) {
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final dx = c[j].dx - c[i].dx, dy = c[j].dy - c[i].dy;
          final ox = (sz[i].width + sz[j].width) / 2 + gap - dx.abs();
          final oy = (sz[i].height + sz[j].height) / 2 + gap - dy.abs();
          if (ox <= 0 || oy <= 0) continue;
          final share = moves[i] / (moves[i] + moves[j]);
          // Pushed along the line between the two centres (stretched to their shapes) by how far the nearer
          // edges are into each other. Pushing along whichever axis is shallower would flip direction, and
          // so jump, the moment the two depths cross.
          final u = Offset(
            dx / ((sz[i].width + sz[j].width) / 2),
            dy / ((sz[i].height + sz[j].height) / 2),
          );
          final len = u.distance;
          final dir = len < 1e-6 ? const Offset(1, 0) : u / len;
          final push = math.min(ox, oy);
          c[i] -= dir * (push * (1 - share));
          c[j] += dir * (push * share);
        }
      }
      for (var i = 0; i < n; i++) {
        final halfW = sz[i].width / 2 + gap / 2;
        final halfH = sz[i].height / 2 + gap / 2;
        c[i] = Offset(
          c[i].dx.clamp(halfW, math.max(halfW, w - halfW)),
          c[i].dy.clamp(halfH, math.max(halfH, h - halfH)),
        );
      }
    }
  }

  Widget _placed(int i, _Spec s, Offset at, Size size, _Turn turn) {
    final depth = turn.depth;
    final sigma = (1 - depth) * 1.2;
    // The card is drawn once and moved, scaled and blurred as a picture: its own paint does not run again
    // every frame (the video and the divider, which do change, are the exceptions and repaint anyway).
    Widget card = RepaintBoundary(
      child: SizedBox(
        width: s.w,
        height: s.h,
        child: FixedTextScale(child: Builder(builder: (c) => s.build(c, turn))),
      ),
    );
    // Shadow and softness follow the depth.
    card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF10211F,
            ).withValues(alpha: 0.05 + 0.1 * depth),
            blurRadius: 6 + 18 * depth,
            offset: Offset(0, 3 + 8 * depth),
          ),
        ],
      ),
      child: card,
    );
    if (sigma > 0.35) {
      card = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: card,
      );
    }
    return Positioned(
      key: ValueKey(i),
      left: at.dx - size.width / 2,
      top: at.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: Opacity(
        opacity: (0.72 + 0.28 * depth).clamp(0.0, 1.0),
        child: FittedBox(fit: BoxFit.fill, child: card),
      ),
    );
  }
}

// --------------------------------------------------------------------------------------- the widgets

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }
}

TextStyle _small(
  BuildContext context, {
  Color? color,
  FontWeight? weight,
  double size = 10,
  double? height,
}) => Theme.of(context).textTheme.labelSmall!.copyWith(
  color: color ?? kTourText60,
  fontWeight: weight ?? FontWeight.w400,
  fontSize: size,
  height: height ?? 1.2,
);

/// A search with its results, as the results page lists them: the words that were typed, then the photos and
/// videos that match, the best one largest.
class _SearchResultsCard extends StatelessWidget {
  const _SearchResultsCard();

  Widget _tile(String asset, {bool video = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset, fit: BoxFit.cover, cacheWidth: 300),
        if (video)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF10211F).withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        children: [
          // The search bar of the app, small: a white pill with a hairline edge, the search mark in a tinted circle and the
          // round button.
          Container(
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0x1A102220)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14102220),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 3),
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x12165E59),
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    size: 12,
                    color: kTourAccent,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'surfing at sunset',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _small(context, color: kTourText, size: 10.5),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: kTourAccent,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _tile('assets/tour/videos/v_surf.jpg', video: true),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(child: _tile('assets/tour/photos/kayak.jpg')),
                      const SizedBox(height: 4),
                      Expanded(child: _tile('assets/tour/photos/sunset.jpg')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return _Glass(
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: kTourAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On this phone',
                  maxLines: 1,
                  style: _small(
                    context,
                    color: kTourText,
                    weight: FontWeight.w700,
                    size: 10.5,
                  ),
                ),
                Text(
                  'Nothing uploaded',
                  maxLines: 1,
                  style: _small(context, size: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The daily memory: a photo from this day in an earlier year, with what it is.
class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/tour/photos/tajmahal.jpg',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              cacheWidth: 120,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'A memory from this day',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: kTourText,
                      weight: FontWeight.w700,
                      size: 10.5,
                    ),
                  ),
                ),
                Text(
                  '3 years ago',
                  maxLines: 1,
                  style: _small(context, size: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "On this day": a photo from this date in an earlier year, with the date over it. The same size as the video.
class _DayCard extends StatelessWidget {
  const _DayCard();

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/tour/photos/houseboat.jpg',
              fit: BoxFit.cover,
              cacheWidth: 400,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF10211F).withValues(alpha: 0.7),
                  ],
                  stops: const [0.35, 1],
                ),
              ),
            ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ON THIS DAY',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: Colors.white.withValues(alpha: 0.85),
                      weight: FontWeight.w700,
                      size: 8.5,
                    ).copyWith(letterSpacing: 1),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_months[now.month - 1]} ${now.day}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'From 3 years',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard();

  static const _faces = ['messi', 'sam', 'leo'];

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26 + 2 * 12.0,
            height: 26,
            child: Stack(
              children: [
                for (var i = 0; i < _faces.length; i++)
                  Positioned(
                    left: i * 12.0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/tour/faces/${_faces[i]}.jpg',
                          fit: BoxFit.cover,
                          cacheWidth: 80,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Leo and 57 others',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: kTourText,
                      weight: FontWeight.w700,
                      size: 10.5,
                    ),
                  ),
                ),
                Text(
                  '248 photos',
                  maxLines: 1,
                  style: _small(context, size: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Then and now: two photos of one person with a divider. Back in the crowd it is a plain split down the middle; as
/// it comes forward the handle appears and the divider sweeps to one side, then the other, and settles again as
/// it goes back. All of it follows the turn, so it never jumps.
class _ThenNowCard extends StatelessWidget {
  const _ThenNowCard({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    // Always sliding, a whole number of sweeps to the loop so the end of it meets the start.
    final s = 0.5 + 0.3 * math.sin(turn.t * 2 * math.pi * 5);
    Widget tag(String label, Alignment at, double opacity) => Align(
      alignment: at + const Alignment(0, 0.82),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFF10211F).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: _small(
              context,
              color: Colors.white,
              weight: FontWeight.w700,
              size: 8,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: LayoutBuilder(
          builder: (context, box) {
            final x = s * box.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/tour/photos/messi_now.jpg',
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                ),
                ClipRect(
                  clipper: _LeftOf(s),
                  child: Image.asset(
                    'assets/tour/photos/messi_then.jpg',
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                  ),
                ),
                Positioned(
                  left: x - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const ColoredBox(color: Colors.white),
                ),
                Positioned(
                  left: x - 11,
                  top: box.maxHeight / 2 - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 11,
                          color: kTourAccent,
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 11,
                          color: kTourAccent,
                        ),
                      ],
                    ),
                  ),
                ),
                tag('THEN', Alignment.centerLeft, (s - 0.1) / 0.2),
                tag('NOW', Alignment.centerRight, (0.9 - s) / 0.2),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.share != share;
}

/// A video. Until its first turn it is a still with a play mark. When that turn comes the play mark is tapped
/// (it presses, a ring spreads), the clip starts and the bar under it begins to fill. From then on it keeps
/// playing, in a loop, whether it is at the front or far back, for as long as the page is showing.
class _VideoCard extends StatefulWidget {
  const _VideoCard({super.key, required this.turn, required this.awake});

  final _Turn turn;

  /// Whether the page is showing (and motion is allowed): the clip only runs then.
  final bool awake;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard>
    with SingleTickerProviderStateMixin {
  static const String _asset = 'assets/tour/videos/v_football.mp4';
  static const Duration _tapTime = Duration(milliseconds: 560);
  // When the press lands and the clip starts, a little before the end of the tap.
  static const Duration _landAt = Duration(milliseconds: 330);

  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: _tapTime,
  );
  final Stopwatch _clock = Stopwatch();
  VideoPlayerController? _video;
  bool _ready = false;
  bool _pressed = false;
  bool _landed = false;
  Timer? _landTimer;
  int _generation = 0;

  // The clip could not be loaded on this phone: the still stays, and it is not tried again every frame.
  bool _failed = false;

  // The bar runs off the clock (the player only says where it is every half second, which would make the bar
  // step); this is how far the clock is behind or ahead of the clip, corrected whenever the player reports.
  Duration _offset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _VideoCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.awake && _video == null && !_failed) {
      unawaited(_load(++_generation));
    }
    if (!widget.awake) {
      if (_pressed || _video != null) _sleep();
    } else if (!_pressed && widget.turn.focus > 0.45) {
      _press();
    }
  }

  Future<void> _load(int generation) async {
    final controller = VideoPlayerController.asset(
      _asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        if (identical(_video, controller)) _video = null;
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || generation != _generation) return;
      controller.addListener(_follow);
      if (_landed) await controller.play();
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
    } catch (_) {
      // No player here (or the clip is not playable): the still stays and the bar still fills.
      _failed = true;
      if (identical(_video, controller)) _video = null;
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  void _follow() {
    final v = _video?.value;
    if (v == null || !v.isPlaying || !_clock.isRunning) return;
    final length = v.duration.inMilliseconds;
    if (length <= 0) return;
    var diff = v.position.inMilliseconds - _here(length);
    // Across the loop point the two can sit either side of it.
    if (diff > length / 2) diff -= length;
    if (diff < -length / 2) diff += length;
    if (diff.abs() > 120) _offset += Duration(milliseconds: diff);
  }

  int _here(int length) =>
      (_clock.elapsedMilliseconds + _offset.inMilliseconds) % length;

  void _press() {
    _pressed = true;
    _tap.forward(from: 0);
    _landTimer?.cancel();
    _landTimer = Timer(_landAt, () {
      if (!mounted || !_pressed) return;
      setState(() => _landed = true);
      _clock.start();
      if (_ready) unawaited(_video?.play());
    });
  }

  // The page went away: stop, give the player back (a phone only has a few video decoders, and the other pages
  // want them), and be a still again for when it comes back.
  void _sleep() {
    _generation++;
    _pressed = false;
    _landed = false;
    _ready = false;
    _landTimer?.cancel();
    _clock.stop();
    _clock.reset();
    _offset = Duration.zero;
    final controller = _video;
    _video = null;
    controller?.removeListener(_follow);
    if (controller != null) unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _generation++;
    _landTimer?.cancel();
    _tap.dispose();
    final controller = _video;
    _video = null;
    controller?.removeListener(_follow);
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.turn.focus;
    final length = _ready
        ? _video!.value.duration.inMilliseconds.clamp(1, 1 << 30)
        : 4000;
    final progress = _landed ? _here(length) / length : 0.0;
    // The still lies over the clip until the press lands.
    final showStill = !(_ready && _landed);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && _video != null)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            AnimatedOpacity(
              opacity: showStill ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Image.asset(
                'assets/tour/videos/v_football.jpg',
                fit: BoxFit.cover,
                cacheWidth: 400,
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _tap,
                builder: (context, _) {
                  final t = _tap.value;
                  final press =
                      1 - 0.16 * math.sin((t / 0.55).clamp(0.0, 1.0) * math.pi);
                  final u = ((t - 0.08) / 0.62).clamp(0.0, 1.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_pressed && u > 0 && u < 1)
                        Container(
                          width: 30 + 26 * u,
                          height: 30 + 26 * u,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(
                              alpha: 0.42 * (1 - u),
                            ),
                          ),
                        ),
                      AnimatedOpacity(
                        opacity: _landed ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: Transform.scale(
                          scale: _pressed ? press : 1,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                              color: kTourAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Opacity(
                opacity: _landed
                    ? 1
                    : _DepthWidgetsState._smooth((f - 0.1) / 0.4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.5),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
