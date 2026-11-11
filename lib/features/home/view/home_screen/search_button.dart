part of '../home_screen.dart';

/// Search as its own round button. Inactive it is a plain tonal circle. When Search is the screen showing, it fills
/// teal, the magnifier tilts and bounces, and a ring ripples out once, so it reads as a switched-on control rather
/// than a shortcut.
class _SearchButton extends StatefulWidget {
  const _SearchButton({
    required this.active,
    required this.shrunk,
    required this.onTap,
  });

  final bool active;
  final bool shrunk;
  final VoidCallback onTap;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton>
    with TickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// Held, it gives under the finger (squeezes in, and leans and stretches toward the finger); let go, it
  /// springs back past its size and settles, so even a quick tap shows a little bounce.
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _press = _Spring(650, 0.4);
  final _leanX = _Spring(420, 0.5);
  final _leanY = _Spring(420, 0.5);
  int? _pointer;
  Offset _finger = Offset.zero;

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _last = elapsed;
    final held = _pointer != null;
    final press = held ? 1.0 : 0.0;
    final leanX = held ? _tanh((_finger.dx - _barHeight / 2) / 40) : 0.0;
    final leanY = held ? _tanh((_finger.dy - _barHeight / 2) / 40) : 0.0;
    if (calm(context)) {
      _press.jump(press);
      _leanX.jump(0);
      _leanY.jump(0);
    } else {
      _press.step(press, dt);
      _leanX.step(leanX, dt);
      _leanY.step(leanY, dt);
    }
    setState(() {});
    if (!held && _press.restsAt(press) && _leanX.restsAt(leanX) && _leanY.restsAt(leanY)) {
      _ticker.stop();
    }
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// A quick tap is over before the spring gets far, so the press gets a push to start it and the bounce always shows.
  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _finger = e.localPosition;
    _press.v += 6;
    _wake();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _finger = e.localPosition;
    _wake();
  }

  void _lift(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _wake();
  }

  /// Already on when the app opens, because it launches on Search, so it is shown settled rather than playing the
  /// ripple on every launch.
  @override
  void initState() {
    super.initState();
    if (widget.active) _burst.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SearchButton old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _burst.forward(from: 0);
    } else if (!widget.active && old.active) {
      _burst.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _burst.dispose();
    super.dispose();
  }

  /// While the bolt button's liquid runs into this button it draws this circle itself (see ActionFab). The circle,
  /// frost, border and icon fade out meanwhile and back in when it lets go, and the press is held still so the two
  /// stay lined up. The tilt overshoots and settles.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: 'Search',
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _lift,
        onPointerCancel: _lift,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ValueListenableBuilder<double>(
          valueListenable: ActionFab.ownsSearch,
          builder: (context, level, _) => AnimatedBuilder(
          animation: _burst,
          builder: (context, _) {
            final fade = 1 - level;
            final t = _burst.value;
            final tilt = widget.active
                ? math.sin(t * math.pi * 2) * 0.35 * (1 - t)
                : 0.0;
            final pop = widget.active ? 1 + 0.18 * math.sin(t * math.pi) : 1.0;
            final give = 1 - 0.12 * _press.x * fade;
            final lx = _leanX.x * fade;
            final ly = _leanY.x * fade;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(5 * lx, 5 * ly)
                ..scale(
                  give * (1 + 0.06 * lx.abs() - 0.03 * ly.abs()),
                  give * (1 + 0.06 * ly.abs() - 0.03 * lx.abs()),
                ),
              child: SizedBox(
              width: _barHeight,
              height: _barHeight,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (widget.active && t > 0 && t < 1)
                    Container(
                      width: _barHeight + 26 * t,
                      height: _barHeight + 26 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(
                            alpha: 0.45 * (1 - t),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14 * fade, sigmaY: 14 * fade),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 340),
                        curve: Curves.easeOutCubic,
                        width: _barHeight,
                        height: _barHeight,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.active
                              ? AppColors.primary.withValues(
                                  alpha: (widget.shrunk ? 0.72 : 0.85) * fade,
                                )
                              : AppColors.parchment.withValues(
                                  alpha: (widget.shrunk ? 0.55 : 0.72) * fade,
                                ),
                          border: Border.all(
                            color: (widget.active
                                    ? AppColors.primary
                                    : AppColors.hairline)
                                .withValues(alpha: fade),
                          ),
                        ),
                        child: Transform.rotate(
                          angle: tilt,
                          child: Transform.scale(
                            scale: pop,
                            child: Icon(
                              Icons.search_rounded,
                              color: (widget.active
                                      ? AppColors.onPrimary
                                      : AppColors.ink)
                                  .withValues(alpha: fade),
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            );
          },
        ),
        ),
        ),
      ),
    );
  }
}
