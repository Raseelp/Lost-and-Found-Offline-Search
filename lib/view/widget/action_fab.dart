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

/// The round bolt button above the search button, the same 58 dp circle. Tapping it dims the page and the
/// page's actions bud out of the button like drops of the same liquid: each swells out on a neck that thins
/// and pinches off, then wobbles into its place on an arc, while the bolt turns into a close mark. Tapping
/// the button again, the dimmed page or back draws them back in the same way.
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

  // 0 closed, 1 open: the dimming and every action's budding out hang on it.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
    reverseDuration: const Duration(milliseconds: 460),
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
    _open.forward();
    HapticFeedback.lightImpact();
  }

  void close() {
    if (!_wantOpen) return;
    setState(() => _wantOpen = false);
    _open.reverse();
  }

  // Where the fan's circles sit, as angles in degrees (0 right, 90 up, 180 left).
  List<double> _angles(int n) {
    if (n == 1) return const [135];
    const from = 100.0, to = 176.0;
    return [for (var i = 0; i < n; i++) from + (to - from) * i / (n - 1)];
  }

  // How far along its own budding each action is (0 inside the button, 1 settled), one a little after another.
  double _stagger(int i, int n, double v) {
    final start = i * 0.12;
    final end = math.min(1.0, start + 1 - 0.12 * (n - 1));
    return Interval(start, end).transform(v);
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
          animation: Listenable.merge([_open, _dock, _own]),
          builder: (context, _) {
            final v = _open.value;
            final live = _wantOpen || v > 0;

            // The actions as drops of the button's liquid: where each one is on its way out, and how it is
            // shaped (see _Bud).
            final buds = [
              for (var i = 0; i < actions.length; i++)
                _Bud.at(
                  from: center,
                  to: itemCenters[i],
                  buttonRadius: _size / 2,
                  radius: _item / 2,
                  progress: _stagger(i, actions.length, v),
                  calm: calm,
                ),
            ];
            // The button gives a little of itself to each drop as it leaves, and fills back out.
            final give = calm ? 1.0 : 1 - 0.07 * math.sin(math.pi * v);
            // The bolt turns into a close mark as the actions come out.
            final turn = Curves.easeInOut.transform(v.clamp(0.0, 1.0));

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
                        rx: r * squashX * give,
                        ry: r * stretch * give,
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
                                  rx: r * squashX * give,
                                  ry: r * stretch * give,
                                  search: searchAt,
                                  fabColor: fabColor.withValues(alpha: fabColor.a * fabScale),
                                  searchColor: glass.withValues(alpha: copyAlpha),
                                  merge: d.clamp(0.0, 1.0),
                                  withSearch: showSearch,
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
                          // The bolt, turning into a close mark while the actions are out, and fading out as the
                          // button is drawn into the search button.
                          Positioned(
                            left: fabAt.dx - r,
                            top: fabAt.dy - r,
                            width: _size,
                            height: _size,
                            child: IgnorePointer(
                              child: Transform.scale(
                                scale: (0.6 + 0.4 * boltFade) * give,
                                child: Transform.rotate(
                                  angle: turn * math.pi / 2,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // One hands over to the other half way round, never both at once.
                                      Opacity(
                                        opacity: (boltFade * (1 - turn * 2)).clamp(0.0, 1.0),
                                        child: const Icon(Icons.bolt_rounded, size: 30, color: AppColors.onPrimary),
                                      ),
                                      Opacity(
                                        opacity: (boltFade * (turn * 2 - 1)).clamp(0.0, 1.0),
                                        child: const Icon(Icons.close_rounded, size: 28, color: AppColors.onPrimary),
                                      ),
                                    ],
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
                // The drops of liquid the actions bud out as, with their necks back to the button (which is
                // drawn over the necks' roots, so they grow out of it).
                if (live)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _BudsPainter(buttonAt: center, buds: buds)),
                    ),
                  ),
                // What each drop holds: its icon once it has pinched off, and its name as it settles.
                if (live)
                  for (var i = 0; i < actions.length; i++)
                    _actionAt(actions[i], itemCenters[i], buds[i]),
                fab,
                target,
              ],
            );
          },
        );
      },
    );
  }

  // One action: touched where it settles, drawn wherever its drop is on the way. The white circle is the drop
  // itself (see _BudsPainter); this is its icon, which shows once the drop has pinched off, and its name, which
  // comes in as it settles.
  Widget _actionAt(FabAction action, Offset at, _Bud bud) {
    return Positioned(
      left: at.dx - 48,
      top: at.dy - _item / 2,
      width: 96,
      child: Transform.translate(
        offset: bud.centre - at,
        child: Opacity(
          opacity: bud.shows,
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
                      SizedBox.square(
                        dimension: _item,
                        child: Opacity(
                          opacity: bud.free,
                          child: Transform.scale(
                            scale: 0.5 + 0.5 * bud.free,
                            child: Icon(action.icon, size: 24, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: bud.settled,
                        child: Text(
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
  }
}

/// One action on its way out of the button, as a drop of the button's liquid: where it is, how big, how it
/// is stretched, and how it hangs on to the button.
///
/// Its way out: it clings at first (swelling out of the button on a thick neck), then pulls away faster and
/// faster, the neck thinning until it pinches off, and once free it runs a little past its place and wobbles
/// back. Going back in plays the same way backwards: the neck reaches out, catches it and draws it in.
class _Bud {
  const _Bud({
    required this.centre,
    required this.radius,
    required this.angle,
    required this.stretch,
    required this.waist,
    required this.free,
    required this.settled,
    required this.shows,
    required this.buttonRadius,
  });

  factory _Bud.at({
    required Offset from,
    required Offset to,
    required double buttonRadius,
    required double radius,
    required double progress,
    required bool calm,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final angle = (to - from).direction;
    if (calm) {
      // No motion wanted: it simply fades in where it goes.
      return _Bud(
        centre: to, radius: radius, angle: angle, stretch: 1, waist: 0, free: p, settled: p, shows: p,
        buttonRadius: buttonRadius,
      );
    }
    final along = _out(p);
    final centre = Offset.lerp(from, to, along)!;
    final gap = (centre - from).distance;
    // Small while still mostly inside the button, plumping up to full size as it comes out.
    final size = radius * (0.55 + 0.45 * Curves.easeOut.transform((gap / (buttonRadius + radius)).clamp(0.0, 1.0)));
    // The neck: as wide as the drop while they overlap, drawing out thinner and thinner until it pinches off
    // well clear of the button.
    final near = buttonRadius, far = buttonRadius + size * 2.6;
    final k = ((far - gap) / (far - near)).clamp(0.0, 1.0);
    final waist = size * 0.9 * k * k * (3 - 2 * k);
    // Speed along its way (from the curve's slope): fast, it draws out long and thin; running past its place
    // and turning back, it squashes; hanging on the neck, it is pulled long toward the button.
    final slope = (_out(math.min(1, p + 0.01)) - _out(math.max(0, p - 0.01))) / 0.02;
    final stretch = (1 + 0.06 * slope + 0.12 * k * (1 - k) * 4).clamp(0.88, 1.18);
    return _Bud(
      centre: centre,
      radius: size,
      angle: angle,
      stretch: stretch,
      waist: waist,
      free: Curves.easeOut.transform(((1 - k) * 1.25 - 0.25).clamp(0.0, 1.0)),
      settled: const Interval(0.72, 1, curve: Curves.easeOut).transform(p),
      shows: (p * 8).clamp(0.0, 1.0),
      buttonRadius: buttonRadius,
    );
  }

  // Clings (slow, quadratic) for the first part, then springs out, runs about a tenth past and settles.
  static double _out(double t) {
    const cling = 0.34;
    if (t <= cling) {
      final u = t / cling;
      return 0.2 * u * u;
    }
    final tau = (t - cling) / (1 - cling);
    final base = 0.2 + 0.8 * (1 - math.pow(1 - tau, 3));
    return base + 0.11 * math.sin(tau * math.pi * 2) * math.exp(-3.2 * tau) * (1 - tau);
  }

  final Offset centre;
  final double radius;

  /// The way from the button to where it settles.
  final double angle;

  /// Along [angle]: above 1 drawn out long, below 1 squashed (its area kept).
  final double stretch;

  /// The neck back to the button, 0 once it has pinched off.
  final double waist;

  /// 0 while it hangs on the neck, 1 once free (its icon shows).
  final double free;

  /// 1 once it has settled (its name shows).
  final double settled;

  /// The drop shows at all (a quick fade at the very start, so nothing pops into being).
  final double shows;
  final double buttonRadius;
}

/// Draws the drops and their necks, in the button's teal where they leave it, turning white as they come
/// out. The button itself is drawn over the necks' roots, so they grow out of it.
class _BudsPainter extends CustomPainter {
  _BudsPainter({required this.buttonAt, required this.buds});

  final Offset buttonAt;
  final List<_Bud> buds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final bud in buds) {
      if (bud.shows <= 0) continue;
      final gap = (bud.centre - buttonAt).distance;
      canvas.save();
      // In the drop's own frame: the button at the origin, the drop out along the x axis.
      canvas.translate(buttonAt.dx, buttonAt.dy);
      canvas.rotate(bud.angle);
      final rx = bud.radius * bud.stretch;
      final ry = bud.radius / bud.stretch;
      final drop = Path()..addOval(Rect.fromCenter(center: Offset(gap, 0), width: rx * 2, height: ry * 2));
      var shape = drop;
      if (bud.waist > 0.8) {
        // From inside the button to inside the drop, its sides bowed in to the waist half way.
        final x0 = bud.buttonRadius * 0.5;
        final x1 = math.max(x0 + 1, gap - rx * 0.4);
        final e0 = math.min(bud.buttonRadius, bud.radius) * 0.9;
        final e1 = ry * 0.9;
        final mid = (x0 + x1) / 2;
        final bend = 2 * bud.waist - (e0 + e1) / 2;
        final neck = Path()
          ..moveTo(x0, -e0)
          ..quadraticBezierTo(mid, -bend, x1, -e1)
          ..lineTo(x1, e1)
          ..quadraticBezierTo(mid, bend, x0, e0)
          ..close();
        shape = Path.combine(PathOperation.union, drop, neck);
      }
      // Its shadow, from the drop alone, growing in as it comes free (none under the neck).
      final lifted = bud.free * bud.shows;
      if (lifted > 0.01) {
        canvas.save();
        canvas.rotate(-bud.angle);
        final c = Offset(gap * math.cos(bud.angle), gap * math.sin(bud.angle));
        canvas.drawOval(
          Rect.fromCenter(center: c + const Offset(0, 6), width: bud.radius * 2, height: bud.radius * 2),
          Paint()
            ..color = AppColors.shadow.withValues(alpha: 0.26 * lifted)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.restore();
      }
      // Teal at the button's edge, white from the drop on, the change spread over at least a dozen pixels and
      // S-shaped, so there is no line across it.
      var from = bud.buttonRadius * 0.95;
      var to = gap - rx * 0.6;
      if (to - from < 14) {
        final m = (from + to) / 2;
        from = m - 7;
        to = m + 7;
      }
      const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
      final colors = [
        for (final t in stops)
          Color.lerp(AppColors.primary, AppColors.canvas, t * t * (3 - 2 * t))!.withValues(alpha: bud.shows),
      ];
      canvas.drawPath(
        shape,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(Offset(from, 0), Offset(to, 0), colors, stops),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BudsPainter old) => true;
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

  /// 1 while the button floats, 0 once it has run into the search button: its shadow goes with it.
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    // The button's shadow, from the button alone (the search part is glass: nothing may show
    // through it).
    final own = Path()..addOval(Rect.fromCenter(center: fab, width: rx * 2, height: ry * 2));
    canvas.drawPath(
      own.shift(const Offset(0, 8)),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.34 * lift)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
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
