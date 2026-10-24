import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';

/// One round button of the fan: what a page offers besides looking at it.
class FabAction {
  const FabAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The round bolt button above the search button, the same 58 dp circle. Tapping it strikes: the bolt
/// shakes and flashes, the page dims, and the page's actions fly out of the button along an arc, each on a
/// jagged line of lightning. Tapping the button again, the dimmed page or back puts it all away.
///
/// Place it as a [Positioned.fill] over the home screen; it only catches touches on the button, and (while
/// open) on the dimmed page and the actions.
class ActionFab extends StatefulWidget {
  const ActionFab({
    super.key,
    required this.actions,
    required this.visible,
    this.shrunk = false,
    this.searchActive = false,
  });

  /// How much of the search button is being drawn by this button's liquid (see _BlobPainter) instead of by
  /// the search button itself, 0 to 1. It fades from one to the other, so there is no moment where the two
  /// look different from each other and one pops.
  static final ValueNotifier<double> ownsSearch = ValueNotifier<double>(0);

  /// What the page offers. None on the tabs that have nothing to offer, and while choosing: the button then
  /// runs into the search button.
  final List<FabAction> actions;

  /// False while typing: the bar is out of the way then, and so is this.
  final bool visible;

  /// The bottom bar has shrunk away from a list being scrolled: the button runs into the search button, and
  /// comes back out of it when the list is scrolled back up.
  final bool shrunk;

  /// Search is the tab showing: its button is filled, and the liquid takes that colour.
  final bool searchActive;

  @override
  State<ActionFab> createState() => ActionFabState();
}

class ActionFabState extends State<ActionFab> with TickerProviderStateMixin {
  static const double _size = kFloatingBarHeight;
  static const double _item = 52;
  static const double _radius = 122;

  // 0 closed, 1 open: the dimming and every action's flight hang on it.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    reverseDuration: const Duration(milliseconds: 340),
  );
  // The strike when it opens: shake, pop, flash, ring.
  late final AnimationController _strike = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );
  // The slow flicker and glow once it has struck: one round of it, then the bolt holds still (anything still
  // moving would have the blurred page behind it worked out again every frame).
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  // 0: the button floats above the search button, 1: it has run into it. Goes past both a little (the
  // liquid sloshes), hence the room either side.
  late final AnimationController _dock = AnimationController(
    vsync: this,
    lowerBound: -0.6,
    upperBound: 1.6,
    value: _wantsDock ? 1 : 0,
  );

  // How much the liquid owns of the search circle: fades in as the button starts to fall and out once the
  // liquid has settled.
  late final AnimationController _own = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  double _ownTarget = 0;

  bool _wantOpen = false;

  bool get isOpen => _wantOpen;

  bool get _wantsDock => widget.actions.isEmpty || widget.shrunk;

  @override
  void initState() {
    super.initState();
    _dock.addListener(_syncOwnership);
    _dock.addStatusListener((_) => _syncOwnership());
    _own.addListener(() => ActionFab.ownsSearch.value = _own.value);
  }

  // The real search button steps aside while the liquid is drawing it (moving, or not yet settled).
  void _syncOwnership() {
    // Called from the middle of a build (an animation that was just started): the search button cannot be
    // told then, so it is told right after.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncOwnership();
      });
      return;
    }
    final v = _dock.value;
    final owns = _dock.isAnimating || (v > 0.005 && v < 0.995);
    final target = owns ? 1.0 : 0.0;
    if (_ownTarget == target) return;
    _ownTarget = target;
    // Quickly in (the button is about to move), slowly out (the liquid has settled and lets go gently).
    _own.animateTo(
      target,
      duration: Duration(milliseconds: owns ? 160 : 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    // The search button comes back, once the tree has finished coming apart.
    if (ActionFab.ownsSearch.value > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ActionFab.ownsSearch.value = 0);
    }
    _own.dispose();
    _dock.dispose();
    _open.dispose();
    _strike.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ActionFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasDocked = oldWidget.actions.isEmpty || oldWidget.shrunk;
    final calm = MediaQuery.disableAnimationsOf(context);
    if (_wantsDock && !wasDocked) {
      // It falls into the search button: gravity pulls it in, and what it hits slops about.
      if (calm) {
        _dock.value = 1;
      } else {
        _dock.animateTo(1, duration: const Duration(milliseconds: 950), curve: const _LiquidFall());
      }
    } else if (!_wantsDock && wasDocked) {
      // The search button lets go of it: it stretches out slowly, then springs free and settles.
      if (calm) {
        _dock.value = 0;
      } else {
        _dock.animateTo(0, duration: const Duration(milliseconds: 1050), curve: const _LiquidRise());
      }
    }
    // Another tab, choosing started, the keyboard came up: the actions it was showing are gone.
    final gone = !widget.visible || widget.actions.isEmpty;
    final changed = widget.actions.length != oldWidget.actions.length ||
        [for (final a in widget.actions) a.label].join('|') != [for (final a in oldWidget.actions) a.label].join('|');
    if (_wantOpen && (gone || changed || _wantsDock)) close();
  }

  void toggle() => _wantOpen ? close() : open();

  void open() {
    // Not while it is still on its way out of the search button.
    if (_wantOpen || _wantsDock || _dock.value > 0.2) return;
    setState(() => _wantOpen = true);
    final calm = MediaQuery.disableAnimationsOf(context);
    _open.forward();
    if (!calm) {
      _strike.forward(from: 0);
      _idle.forward(from: 0);
      // A thunderclap: one firm tap, then the rumble after it.
      HapticFeedback.mediumImpact();
      Future<void>.delayed(const Duration(milliseconds: 110), () {
        if (mounted && _wantOpen) HapticFeedback.lightImpact();
      });
    }
  }

  void close() {
    if (!_wantOpen) return;
    setState(() => _wantOpen = false);
    _open.reverse();
    _idle.stop();
    _strike.value = 0;
  }

  // Where the fan's circles sit, as angles in degrees (0 right, 90 up, 180 left).
  List<double> _angles(int n) {
    if (n == 1) return const [135];
    const from = 100.0, to = 176.0;
    return [for (var i = 0; i < n; i++) from + (to - from) * i / (n - 1)];
  }

  double _stagger(int i, double v) {
    final start = 0.06 + i * 0.1;
    final end = math.min(1.0, start + 0.62);
    return Interval(start, end, curve: Curves.easeOutBack).transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final calm = media.disableAnimations;
    final margin = media.size.width >= 400 ? 20.0 : 16.0;
    final bottom = kFloatingBarBottomGap + media.padding.bottom + kFloatingBarHeight + AppSpacing.md;
    final actions = widget.actions;
    final bottomInset = kFloatingBarBottomGap + media.padding.bottom;

    return LayoutBuilder(
      builder: (context, box) {
        final center = Offset(box.maxWidth - margin - _size / 2, box.maxHeight - bottom - _size / 2);
        final angles = _angles(actions.length);
        final itemCenters = [
          for (final a in angles)
            center + Offset(_radius * math.cos(a * math.pi / 180), -_radius * math.sin(a * math.pi / 180)),
        ];

        return AnimatedBuilder(
          animation: Listenable.merge([_open, _strike, _idle, _dock, _own]),
          builder: (context, _) {
            final v = _open.value;
            final strike = _strike.value;
            final idle = _idle.value;
            final live = _wantOpen || v > 0;

            // The bolt: a quick shake and pop when it strikes, then a faint flicker; it glows and
            // turns icy while open.
            final shake = calm ? 0.0 : math.sin(strike * math.pi * 8) * (1 - strike) * 0.32;
            final jitter = calm ? 0.0 : math.sin(strike * math.pi * 11) * (1 - strike) * 2.6;
            final pop = 1 + (calm ? 0.0 : 0.26 * math.sin(math.min(strike * 2.4, 1) * math.pi));
            final flicker = (_wantOpen && !calm)
                ? 1 - 0.14 * math.max(0, math.sin(idle * math.pi * 4)) * math.max(0, math.sin(idle * math.pi * 10))
                : 1.0;
            final glow = _wantOpen && !calm ? 0.5 + 0.5 * math.sin(idle * math.pi * 2) : 0.0;
            final boltColor = Color.lerp(AppColors.onPrimary, AppColors.mediaAccentSoft, v)!;

            final ringT = calm ? 1.0 : Interval(0, 0.75, curve: Curves.easeOutCubic).transform(strike);
            final flash = calm ? 0.0 : 0.24 * (1 - Interval(0, 0.42, curve: Curves.easeOut).transform(strike));

            // Everything the button looks like - its liquid, the search button's circle while they run into
            // each other, the bolt - is drawn in the bottom bar's own frame (same slide and shrink as the bar,
            // same size), so the circles line up with the real search button exactly.
            final d = _dock.value;
            final docked = !_dock.isAnimating && d >= 0.999;
            final extra = 130.0;
            final barBox = AppSpacing.sm + kFloatingBarHeight + bottomInset;
            final searchAt = Offset(box.maxWidth - margin - _size / 2, extra + AppSpacing.sm + _size / 2);
            final fabAt = searchAt - Offset(0, (_size + AppSpacing.md) * (1 - d));
            final r = _size / 2;
            final speed = _dock.isAnimating ? _dock.velocity.abs() : 0.0;
            final stretch = calm ? 1.0 : 1 + math.min(0.3, speed * 0.07);
            final squashX = 1 / math.sqrt(stretch);
            // How much the liquid is drawing of the search circle (fades in and out, see _own).
            final level = _own.value;
            final showSearch = level > 0.002;
            final searchTint = widget.searchActive
                ? AppColors.primary.withValues(alpha: widget.shrunk ? 0.72 : 0.85)
                : AppColors.parchment.withValues(alpha: widget.shrunk ? 0.55 : 0.72);
            // How far the button is from the search button, 1 floating, 0 on top of it (never past either:
            // the slosh must not make anything flicker).
            final g = 1 - d.clamp(0.0, 1.0);
            // The two icons never share a spot: the bolt fades as the button comes down onto the search
            // button, the magnifier is out of sight while the button covers it and comes back as the
            // liquid settles.
            final boltFade = const Interval(0.35, 0.72, curve: Curves.easeInOut).transform(g);
            final searchIconFade =
                1 - const Interval(0.06, 0.34, curve: Curves.easeInOut).transform(g) * (1 - const Interval(0.72, 0.95, curve: Curves.easeInOut).transform(g));
            // The button's shadow thins as it nears the search button, so nothing dark shows through the glass.
            final shadowK = const Interval(0.3, 1, curve: Curves.easeIn).transform(g);

            final liquid = (docked && !showSearch)
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: searchTint),
                    duration: const Duration(milliseconds: 340),
                    builder: (context, tint, _) {
                      final glass = tint ?? searchTint;
                      // Once the button has run into the search button its colour is the search button's:
                      // from there on it fades out with the rest of the liquid, as the real button fades in.
                      final copyAlpha = 1 - (1 - glass.a) / (1 - glass.a * (1 - level));
                      final fabScale = 1 + (copyAlpha / glass.a - 1) * const Interval(0.5, 1).transform(d.clamp(0.0, 1.0));
                      final fabColor = Color.lerp(
                        AppColors.primary,
                        glass,
                        const Interval(0.1, 0.85, curve: Curves.easeInOut).transform(d.clamp(0.0, 1.0)),
                      )!;
                      final blob = _BlobGeometry(
                        fab: fabAt,
                        rx: r * squashX,
                        ry: r * stretch,
                        search: searchAt,
                        r: r,
                        withSearch: showSearch,
                      ).path();
                      final bounds = blob.getBounds().inflate(1);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // The search part of the liquid is frosted glass, like the search button itself; the
                          // frost fades with the liquid (an Opacity around it would blank the frost).
                          if (showSearch)
                            Positioned.fromRect(
                              rect: bounds,
                              child: IgnorePointer(
                                child: ClipPath(
                                  clipper: _PathClipper(blob.shift(-bounds.topLeft)),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(sigmaX: 14 * level, sigmaY: 14 * level),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _BlobPainter(
                                  path: blob,
                                  fab: fabAt,
                                  rx: r * squashX,
                                  ry: r * stretch,
                                  search: searchAt,
                                  fabColor: fabColor.withValues(alpha: fabColor.a * fabScale),
                                  searchColor: glass.withValues(alpha: copyAlpha),
                                  merge: d.clamp(0.0, 1.0),
                                  withSearch: showSearch,
                                  glow: glow,
                                  lift: shadowK,
                                ),
                              ),
                            ),
                          ),
                          // The search icon, while the real one is fading out (and gone while the button covers it).
                          if (showSearch)
                            Positioned(
                              left: searchAt.dx - r,
                              top: searchAt.dy - r,
                              width: _size,
                              height: _size,
                              child: IgnorePointer(
                                child: Icon(
                                  Icons.search_rounded,
                                  size: 26,
                                  color: (widget.searchActive ? AppColors.onPrimary : AppColors.ink)
                                      .withValues(alpha: searchIconFade.clamp(0.0, 1.0)),
                                ),
                              ),
                            ),
                          // The bolt: shakes when it strikes, flickers while open, and fades out as the button
                          // is drawn into the search button.
                          Positioned(
                            left: fabAt.dx - r,
                            top: fabAt.dy - r,
                            width: _size,
                            height: _size,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: (boltFade * flicker).clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(jitter, 0),
                                  child: Transform.rotate(
                                    angle: shake,
                                    child: Transform.scale(
                                      scale: pop * (0.6 + 0.4 * boltFade),
                                      child: Icon(Icons.bolt_rounded, size: 30, color: boltColor),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );

            final fab = Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: widget.visible ? 1 : 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      offset: Offset(0, widget.shrunk ? 0.08 : 0),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 340),
                        curve: Curves.easeOutCubic,
                        scale: widget.shrunk ? 0.93 : 1,
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: box.maxWidth,
                          height: barBox,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 0,
                                top: -extra,
                                width: box.maxWidth,
                                height: barBox + extra,
                                child: liquid,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            // The touch target: only while the button is out, and where it rests.
            final target = Positioned(
              left: center.dx - _size / 2,
              top: center.dy - _size / 2,
              width: _size,
              height: _size,
              child: IgnorePointer(
                ignoring: _wantsDock || !widget.visible,
                child: ExcludeSemantics(
                  excluding: _wantsDock || !widget.visible,
                  child: Semantics(
                    button: true,
                    expanded: _wantOpen,
                    label: 'Actions for this page',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: toggle,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // The dimmed page: tapping it puts the actions away.
                if (live)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_wantOpen,
                      child: Semantics(
                        button: true,
                        label: 'Close the actions',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: close,
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 5 * v, sigmaY: 5 * v),
                              child: ColoredBox(
                                color: Color.lerp(
                                  AppColors.transparent,
                                  AppColors.scrim.withValues(alpha: 0.5),
                                  v,
                                )!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // The flash of the strike over the whole page.
                if (live && flash > 0.002)
                  Positioned.fill(
                    child: IgnorePointer(child: ColoredBox(color: AppColors.onMedia.withValues(alpha: flash))),
                  ),
                // A ring that leaves the button with the strike.
                if (live && ringT < 1)
                  Positioned(
                    left: center.dx - (_size + 150 * ringT) / 2,
                    top: center.dy - (_size + 150 * ringT) / 2,
                    width: _size + 150 * ringT,
                    height: _size + 150 * ringT,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.mediaAccentSoft.withValues(alpha: 0.7 * (1 - ringT)),
                            width: 3 * (1 - ringT) + 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                // The lightning from the button to each action.
                if (live && _wantOpen && !calm)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _BoltsPainter(
                          from: center,
                          to: itemCenters,
                          progress: [for (var i = 0; i < actions.length; i++) _boltProgress(i, v)],
                          fade: [for (var i = 0; i < actions.length; i++) _boltFade(i, v)],
                        ),
                      ),
                    ),
                  ),
                // The actions, flying out of the button.
                if (live)
                  for (var i = 0; i < actions.length; i++)
                    _actionAt(actions[i], itemCenters[i], center, _stagger(i, v)),
                fab,
                target,
              ],
            );
          },
        );
      },
    );
  }

  double _boltProgress(int i, double v) {
    final start = 0.04 + i * 0.1;
    return Interval(start, start + 0.22, curve: Curves.easeOutCubic).transform(v);
  }

  double _boltFade(int i, double v) {
    final start = 0.04 + i * 0.1;
    return 1 - Interval(start + 0.14, start + 0.5, curve: Curves.easeIn).transform(v);
  }

  Widget _actionAt(FabAction action, Offset at, Offset origin, double p) {
    final t = p.clamp(0.0, 1.0);
    return Positioned(
      left: at.dx - 48,
      top: at.dy - _item / 2,
      width: 96,
      child: Transform.translate(
        offset: (origin - at) * (1 - p),
        child: Transform.scale(
          scale: 0.3 + 0.7 * p.clamp(0.0, 1.2),
          alignment: Alignment.topCenter,
          child: Opacity(
            opacity: (t * 1.5).clamp(0.0, 1.0),
            child: IgnorePointer(
              ignoring: !_wantOpen,
              child: ExcludeSemantics(
                excluding: !_wantOpen,
                child: Semantics(
                  button: true,
                  label: action.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      close();
                      action.onTap();
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.canvas,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadow.withValues(alpha: 0.26),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: SizedBox.square(
                            dimension: _item,
                            child: Icon(action.icon, size: 24, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.onMedia,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            shadows: [Shadow(color: AppColors.shadow.withValues(alpha: 0.5), blurRadius: 6)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Jagged lines of lightning from the button to each action, drawn out quickly and then faded.
class _BoltsPainter extends CustomPainter {
  _BoltsPainter({required this.from, required this.to, required this.progress, required this.fade});

  final Offset from;
  final List<Offset> to;
  final List<double> progress;
  final List<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < to.length; i++) {
      final p = progress[i];
      final alpha = fade[i].clamp(0.0, 1.0);
      if (p <= 0 || alpha <= 0.01) continue;
      final path = _zigzag(from, to[i], i);
      final metric = path.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * p);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.mediaAccent.withValues(alpha: 0.35 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.onMedia.withValues(alpha: 0.95 * alpha),
      );
    }
  }

  // A line broken into five pieces, each kicked sideways by a fixed amount (the same every time, so it
  // does not wobble between frames).
  Path _zigzag(Offset a, Offset b, int seed) {
    final d = b - a;
    final length = d.distance;
    final normal = Offset(-d.dy, d.dx) / length;
    final path = Path()..moveTo(a.dx, a.dy);
    const parts = 5;
    for (var k = 1; k < parts; k++) {
      final t = k / parts;
      final kick = (k.isEven ? 1 : -1) * (7 + ((seed * 3 + k * 5) % 6)) * (seed.isEven ? 1 : -1);
      final point = a + d * t + normal * kick.toDouble();
      path.lineTo(point.dx, point.dy);
    }
    path.lineTo(b.dx, b.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant _BoltsPainter old) => true;
}

// Falling into the search button: constant acceleration from rest (gravity) until it hits, then the liquid
// slops past and back, a damped swing that settles. The two halves meet with the same speed, so there is no
// jerk at the moment of impact.
class _LiquidFall extends Curve {
  const _LiquidFall();

  @override
  double transformInternal(double t) {
    const impact = 0.5;
    if (t <= impact) {
      final u = t / impact;
      return u * u;
    }
    final tau = (t - impact) / (1 - impact);
    return 1 + 0.354 * math.sin(5.65 * tau) * math.exp(-4.8 * tau);
  }
}

// Coming out of it: held back at first (the liquid clings and stretches), then faster and faster, and
// once free it overshoots its place a little and drops back, settling.
class _LiquidRise extends Curve {
  const _LiquidRise();

  @override
  double transformInternal(double t) {
    const lift = 0.55;
    if (t <= lift) {
      final u = t / lift;
      return u * u;
    }
    final tau = (t - lift) / (1 - lift);
    return 1 + 0.326 * math.sin(5.03 * tau) * math.exp(-4.2 * tau);
  }
}

// The button's liquid: an ellipse (the button, stretched when it moves fast), the search button's circle
// while they are running into each other, and a waist between them that is thick when they are close and
// thins to nothing - snapping - as they pull apart.
class _BlobGeometry {
  const _BlobGeometry({
    required this.fab,
    required this.rx,
    required this.ry,
    required this.search,
    required this.r,
    required this.withSearch,
  });

  final Offset fab;
  final double rx;
  final double ry;
  final Offset search;
  final double r;
  final bool withSearch;

  Path path() {
    final fabOval = Path()..addOval(Rect.fromCenter(center: fab, width: rx * 2, height: ry * 2));
    if (!withSearch) return fabOval;
    final searchCircle = Path()..addOval(Rect.fromCircle(center: search, radius: r));
    var result = Path.combine(PathOperation.union, fabOval, searchCircle);

    final gap = (search.dy - fab.dy).abs();
    // The waist: none at the distance the button rests at, all the width of the circle once they overlap.
    final far = 2.4 * r, near = 0.9 * r;
    final k = ((far - gap) / (far - near)).clamp(0.0, 1.0);
    final waist = r * k * k * (3 - 2 * k);
    if (waist > 1.5 && gap > 1) {
      final cx = search.dx;
      final mid = (search.dy + fab.dy) / 2;
      final end = r * 0.9;
      final bend = 2 * waist - end;
      final neck = Path()
        ..moveTo(cx - end, fab.dy)
        ..quadraticBezierTo(cx - bend, mid, cx - end, search.dy)
        ..lineTo(cx + end, search.dy)
        ..quadraticBezierTo(cx + bend, mid, cx + end, fab.dy)
        ..close();
      result = Path.combine(PathOperation.union, result, neck);
    }
    return result;
  }
}

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => true;
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.path,
    required this.fab,
    required this.rx,
    required this.ry,
    required this.search,
    required this.fabColor,
    required this.searchColor,
    required this.withSearch,
    required this.merge,
    required this.glow,
    required this.lift,
  });

  final Path path;
  final Offset fab;
  final double rx;
  final double ry;
  final Offset search;
  final Color fabColor;
  final Color searchColor;
  final bool withSearch;

  /// 0 apart, 1 run into each other.
  final double merge;
  final double glow;

  /// 1 while the button floats, 0 once it has run into the search button: its shadow goes with it.
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    // The button's glow and shadow, from the button alone (the search part is glass: nothing may show
    // through it).
    final own = Path()..addOval(Rect.fromCenter(center: fab, width: rx * 2, height: ry * 2));
    canvas.drawPath(
      own.shift(Offset(0, 8 - 5 * glow)),
      Paint()
        ..color = AppColors.primary.withValues(alpha: (0.34 + 0.16 * glow) * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 7 * glow),
    );
    final paint = Paint()..isAntiAlias = true;
    if (withSearch) {
      // The button stays its own colour and the search button its own: they mix only in the stretch between
      // the two (at least a few pixels wide, so a button sitting right on the search button still blends).
      final sign = search.dy >= fab.dy ? 1.0 : -1.0;
      var from = fab.dy + sign * ry * 0.95;
      var to = search.dy - sign * (kFloatingBarHeight / 2) * 0.95;
      // Apart, the blend sits in the gap between the two and the button stays one colour. As they merge the
      // blend widens (up to about 40 px), so there is never a hard line across the liquid.
      final wanted = 6 + 36 * Curves.easeInOut.transform(((merge - 0.25) / 0.45).clamp(0.0, 1.0));
      if ((to - from) * sign < wanted) {
        final mid = (from + to) / 2;
        from = mid - sign * wanted / 2;
        to = mid + sign * wanted / 2;
      }
      // S-shaped, not straight: the colours settle into each end instead of ending in a visible edge.
      const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
      final colors = [
        for (final t in stops) Color.lerp(fabColor, searchColor, t * t * (3 - 2 * t))!,
      ];
      paint.shader = ui.Gradient.linear(Offset(search.dx, from), Offset(search.dx, to), colors, stops);
    } else {
      paint.color = fabColor;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => true;
}
