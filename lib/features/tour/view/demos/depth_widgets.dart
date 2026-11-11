import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_palette.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_widgets.dart';
import 'package:video_player/video_player.dart';
part 'depth_widgets/shared.dart';
part 'depth_widgets/search_results_card.dart';
part 'depth_widgets/note_card.dart';
part 'depth_widgets/day_card.dart';
part 'depth_widgets/people_card.dart';
part 'depth_widgets/then_now_card.dart';
part 'depth_widgets/video_card.dart';

/// The first screen's picture: the app's widgets floating at different depths. They are a video, "On this day",
/// people, Then and now, a memory, search and privacy.
///
/// Far ones are small and soft, near ones large and sharp. They take turns. One at a time glides forward, grows sharp
/// and moves in towards the middle while the one before it drifts back. Everything is one continuous motion, so
/// nothing jumps. It plays while its page is showing.
class DepthWidgets extends StatefulWidget {
  const DepthWidgets({super.key, required this.active});

  final bool active;

  @override
  State<DepthWidgets> createState() => _DepthWidgetsState();
}

class _DepthWidgetsState extends State<DepthWidgets>
    with SingleTickerProviderStateMixin {
  /// How long each widget's turn lasts. The loop is every widget once.
  static const Duration _turn = Duration(milliseconds: 2600);

  /// The video card is kept by key. The widget around it changes, because it is blurred only while it is far, and
  /// that would otherwise throw its player away in the middle of its turn.
  final GlobalKey<_VideoCardState> _videoKey = GlobalKey();

  /// The widgets in the order of their turns. The turns jump from one side of the picture to the other, so the one
  /// coming forward and the one going back are never next to each other.
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

  /// True when the phone asks for no animations. The picture then stands still and nothing keeps ticking.
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

  /// How much room to keep between two widgets, and from the edge, so shadows and softness are not cut.
  static const double _gap = 8;

  /// Lays out every widget for the loop position [t] from 0 to 1, with [k] as the scale against the reference size.
  ///
  /// The distance of a widget's turn from now, going round the loop, sets its focus. The focus is 1 at the middle of
  /// its turn and eases to 0 a turn and a bit away on either side. A focused widget glides a little towards the
  /// middle. Each widget also floats on a slow loop of its own, in whole numbers of cycles per loop so the end of the
  /// loop meets its start. The one coming forward holds its ground and the others make room.
  Widget _stage(double w, double h, double k, double t) {
    final n = _specs.length;
    final phase = t * n;
    final turns = List<_Turn>.filled(n, const _Turn(0, 0, 0, 0));
    final sizes = List<Size>.filled(n, Size.zero);
    final centres = List<Offset>.filled(n, Offset.zero);
    final moves = List<double>.filled(n, 1);
    for (var i = 0; i < n; i++) {
      final s = _specs[i];
      var d = (phase - i - 0.5) % n;
      if (d > n / 2) d -= n;
      final focus = _smooth(1 - d.abs() / 1.25);
      final depth = s.depth + (1 - s.depth) * focus;
      final ax = 2 * math.pi * (t * 3 + i * 0.37);
      final ay = 2 * math.pi * (t * 2 + i * 0.53);
      final drift = Offset(math.sin(ax) * 4 * k, math.cos(ay) * 3 * k);
      final rest = Offset(s.cx * w, s.cy * h);
      final centre = Offset(w * 0.5, h * 0.5);
      final scale = (0.7 + 0.3 * depth) * k;
      turns[i] = _Turn(depth, focus, d, t);
      sizes[i] = Size(s.w * scale, s.h * scale);
      centres[i] = Offset.lerp(rest, centre, 0.25 * focus)! + drift;
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

  /// Nudges the widgets apart so none overlaps another, so it does not matter which is painted on top, and keeps all
  /// of them inside the picture.
  /// The push is along the line between the two centres, stretched to their shapes, and grows with how far the nearer
  /// edges are into each other, so it is as smooth as the motion itself. Pushing along the shallower axis would flip
  /// direction, and jump, the moment two depths cross.
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

  /// Puts widget [i] at [at] with [size]. The card is drawn once and then moved, scaled and blurred as a picture, so
  /// its own paint does not run again every frame. The video and the divider change and repaint anyway. Shadow and
  /// softness follow the depth.
  Widget _placed(int i, _Spec s, Offset at, Size size, _Turn turn) {
    final depth = turn.depth;
    final sigma = (1 - depth) * 1.2;
    Widget card = RepaintBoundary(
      child: SizedBox(
        width: s.w,
        height: s.h,
        child: FixedTextScale(child: Builder(builder: (c) => s.build(c, turn))),
      ),
    );
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

/// One floating widget. It holds where the widget rests as shares of the picture's width and height, how big it is
/// at the reference size, and how near it is when it is not having its turn, from 0 far to 1 near.
class _Spec {
  const _Spec(this.cx, this.cy, this.w, this.h, this.depth, this.build);

  final double cx, cy, w, h, depth;
  final Widget Function(BuildContext context, _Turn turn) build;
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return _Glass(
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: TourPalette.teal,
          ),
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
                    color: TourPalette.text,
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
