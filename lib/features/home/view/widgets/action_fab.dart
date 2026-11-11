import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/floating_bar.dart';
part 'action_fab/bud.dart';
part 'action_fab/buds_painter.dart';
part 'action_fab/blob_geometry.dart';
part 'action_fab/blob_painter.dart';

/// The round bolt button above the search button, the same 58 dp circle. Tapping it dims the page and the page's
/// actions bud out of it like drops of the same liquid, each on a neck that thins and pinches off before it wobbles
/// into its place on an arc, while the bolt turns into a close mark. Tapping the button again, the dimmed page or back
/// draws them back in. Place it as a [Positioned.fill] over the home screen. It only catches touches on the button
/// and, while open, on the dimmed page and the actions.
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

  /// 0 closed, 1 open: the dimming and every action's budding out hang on it. (Quick to react: the whole motion,
  /// with its cling and its wobble, plays in about two thirds of the time it once did.)
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 300),
  );

  /// 0: the button floats above the search button, 1: it has run into it. Goes past both a little (the
  /// liquid sloshes), hence the room either side.
  late final AnimationController _dock = AnimationController(
    vsync: this,
    lowerBound: -0.6,
    upperBound: 1.6,
    value: _wantsDock ? 1 : 0,
  );

  /// How much the liquid owns of the search circle: fades in as the button starts to fall and out once the
  /// liquid has settled.
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

  /// The real search button steps aside while the liquid is drawing it (moving, or not yet settled).
  /// Tells the search button whether the liquid owns its look. When this runs in the middle of a build, because an
  /// animation was just started, the search button cannot be told then, so it is told right after. Ownership fades in
  /// quickly, because the button is about to move, and out slowly, when the liquid has settled and lets go gently.
  void _syncOwnership() {
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
    _own.animateTo(
      target,
      duration: Duration(milliseconds: owns ? 160 : 300),
      curve: Curves.easeInOut,
    );
  }

  /// Disposes the animations. The search button comes back once the tree has finished coming apart.
  @override
  void dispose() {
    if (ActionFab.ownsSearch.value > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ActionFab.ownsSearch.value = 0);
    }
    _own.dispose();
    _dock.dispose();
    _open.dispose();
    super.dispose();
  }

  /// Reacts to the actions coming and going. The button falls into the search button, where gravity pulls it in and
  /// what it hits slops about, and the search button lets go of it by stretching out slowly, then springing free and
  /// settling. The actions are gone on another tab, when choosing started or when the keyboard came up.
  @override
  void didUpdateWidget(covariant ActionFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasDocked = oldWidget.actions.isEmpty || oldWidget.shrunk;
    final calm = MediaQuery.disableAnimationsOf(context);
    if (_wantsDock && !wasDocked) {
      if (calm) {
        _dock.value = 1;
      } else {
        _dock.animateTo(1, duration: const Duration(milliseconds: 600), curve: const _LiquidFall());
      }
    } else if (!_wantsDock && wasDocked) {
      if (calm) {
        _dock.value = 0;
      } else {
        _dock.animateTo(0, duration: const Duration(milliseconds: 650), curve: const _LiquidRise());
      }
    }
    final gone = !widget.visible || widget.actions.isEmpty;
    final changed = widget.actions.length != oldWidget.actions.length ||
        [for (final a in widget.actions) a.label].join('|') != [for (final a in oldWidget.actions) a.label].join('|');
    if (_wantOpen && (gone || changed || _wantsDock)) close();
  }

  void toggle() => _wantOpen ? close() : open();

  /// Opens the actions, but not while the button is still on its way out of the search button.
  void open() {
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

  /// Where the fan's circles sit, as angles in degrees (0 right, 90 up, 180 left).
  List<double> _angles(int n) {
    if (n == 1) return const [135];
    const from = 100.0, to = 176.0;
    return [for (var i = 0; i < n; i++) from + (to - from) * i / (n - 1)];
  }

  /// How far along its own budding each action is (0 inside the button, 1 settled), one a little after another.
  double _stagger(int i, int n, double v) {
    final start = i * 0.12;
    final end = math.min(1.0, start + 1 - 0.12 * (n - 1));
    return Interval(start, end).transform(v);
  }

  /// Draws the button and everything that comes out of it in the bottom bar's own frame, with the same slide, shrink
  /// and size, so the circles line up with the real search button exactly. The two icons never share a spot: the bolt
  /// fades as the button comes down onto the search button, and the magnifier is out of sight while the button covers
  /// it and comes back as the liquid settles. The search part is frosted glass, and its frost fades with the liquid
  /// because an Opacity around it would blank the frost. The touch target is only there while the button is out.
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
            final give = calm ? 1.0 : 1 - 0.07 * math.sin(math.pi * v);
            final turn = Curves.easeInOut.transform(v.clamp(0.0, 1.0));

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
            final level = _own.value;
            final showSearch = level > 0.002;
            final searchTint = widget.searchActive
                ? AppColors.primary.withValues(alpha: widget.shrunk ? 0.72 : 0.85)
                : AppColors.parchment.withValues(alpha: widget.shrunk ? 0.55 : 0.72);
            final g = 1 - d.clamp(0.0, 1.0);
            final boltFade = const Interval(0.35, 0.72, curve: Curves.easeInOut).transform(g);
            final searchIconFade =
                1 - const Interval(0.06, 0.34, curve: Curves.easeInOut).transform(g) * (1 - const Interval(0.72, 0.95, curve: Curves.easeInOut).transform(g));
            final shadowK = const Interval(0.3, 1, curve: Curves.easeIn).transform(g);

            final liquid = (docked && !showSearch)
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: searchTint),
                    duration: const Duration(milliseconds: 340),
                    builder: (context, tint, _) {
                      final glass = tint ?? searchTint;
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
                if (live)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _BudsPainter(buttonAt: center, buds: buds)),
                    ),
                  ),
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

  /// One action: touched where it settles, drawn wherever its drop is on the way. The white circle is the drop
  /// itself (see _BudsPainter); this is its icon, which shows once the drop has pinched off, and its name, which
  /// comes in as it settles.
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

/// One round button of the fan: what a page offers besides looking at it.
class FabAction {
  const FabAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Falling into the search button: constant acceleration from rest (gravity) until it hits, then the liquid
/// slops past and back, a damped swing that settles. The two halves meet with the same speed, so there is no
/// jerk at the moment of impact.
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

/// Coming out of it: held back at first (the liquid clings and stretches), then faster and faster, and
/// once free it overshoots its place a little and drops back, settling.
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

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => true;
}
