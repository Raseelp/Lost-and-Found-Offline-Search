part of '../home_screen.dart';

/// The three tabs, tapped or dragged across. One teal chip marks the selected tab and does all the moving, on
/// springs. Pressing a tab lifts the chip there at once, with a small pop up. Dragging pulls it along under the
/// finger, stretching with the speed and leaning toward the finger, with a light tick on each tab it reaches. The
/// screen only changes when the finger lets go, on the tab under it. The chip then settles onto that tab and follows
/// it as it widens for its icon. Pulled up or down, the chip stands taller and leans after the finger, the same
/// either way. Pressing harder, on screens that tell, lifts it higher.
class _TabPill extends StatefulWidget {
  const _TabPill({
    super.key,
    required this.index,
    required this.showActivityDot,
    required this.compact,
    required this.onChanged,
  });

  final int index;
  final bool showActivityDot;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  State<_TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<_TabPill> with SingleTickerProviderStateMixin {
  final _keys = [for (final _ in _navTabs) GlobalKey()];

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _still = 0;

  /// The springs of the chip: its centre and width, how far it is lifted (pressed), how far stretched by speed, and
  /// how much it shows. It shows nothing while Search is the screen showing and nothing is pressed.
  final _centre = _Spring(700, 0.82);
  final _width = _Spring(700, 0.82);
  final _lift = _Spring(520, 0.55);
  final _stretch = _Spring(380, 1);
  final _shown = _Spring(500, 1);
  /// Up and down: how far the finger pulls the chip off the row (-1 up to 1 down, eased), wobbling back when let go.
  final _pull = _Spring(420, 0.42);
  /// The springs of the bar under the chip, pulled along when the finger goes hard past its ends or well up or down
  /// (see [_barPull]).
  final _barX = _Spring(300, 0.45);
  final _barY = _Spring(300, 0.45);
  bool _placed = false;

  /// Each tab's place in the row, from the last layout.
  List<Rect> _rects = const [];

  /// The finger, while one is down on the pill.
  int? _pointer;
  double _x = 0;
  double _y = 0;
  int _over = 0;
  /// Pressing harder than at first, on screens that report it, from 0 to 1. The chip lifts higher.
  double _press = 0;
  double _press0 = 0;
  double _speed = 0;
  Duration? _lastMove;

  /// The tab let go on, from then until the screen has changed to it, a frame or so. The chip heads there straight
  /// away instead of back to the tab still marked.
  int? _going;

  int get _selected => _going ?? _navTabs.indexWhere((t) => t.value == widget.index);

  @override
  void initState() {
    super.initState();
    _wake();
  }

  /// The tabs resize as the selected one gains its icon, or the Library tab gains or loses its activity dot, and the
  /// chip follows them. Without waking the springs for the dot, the chip kept its old width, and the dot sat against its
  /// edge until a tap woke them.
  @override
  void didUpdateWidget(covariant _TabPill old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.compact != widget.compact) {
      _going = null;
      _wake();
    } else if (old.showActivityDot != widget.showActivityDot) {
      _wake();
    }
  }

  /// Lets go of the bar too, after this frame, because listeners cannot rebuild while the tree is being taken down.
  @override
  void dispose() {
    _ticker.dispose();
    if (_barPull.value.$1 != 0 || _barPull.value.$2 != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _barPull.value = (0, 0));
    }
    super.dispose();
  }

  void _wake() {
    _still = 0;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  List<Rect>? _measure() {
    final row = context.findRenderObject() as RenderBox?;
    if (row == null || !row.hasSize) return null;
    final rects = <Rect>[];
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      rects.add(row.globalToLocal(box.localToGlobal(Offset.zero)) & box.size);
    }
    return rects;
  }

  /// The nearest tab, so the gaps between the tabs and the ends still count.
  int _tabAt(double x) {
    var best = 0;
    for (var i = 1; i < _rects.length; i++) {
      if ((_rects[i].center.dx - x).abs() < (_rects[best].center.dx - x).abs()) best = i;
    }
    return best;
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _last = elapsed;
    final rects = _measure();
    if (rects == null) return;
    _rects = rects;

    final pressed = _pointer != null;
    final selected = _selected;
    late double centre;
    late double width;
    if (pressed) {
      final under = rects[_over];
      centre = under.center.dx + (_x - under.center.dx) * 0.25;
      width = under.width;
    } else if (selected >= 0) {
      centre = rects[selected].center.dx;
      width = rects[selected].width;
    } else {
      centre = _centre.x;
      width = _width.x;
    }
    final shown = pressed || selected >= 0 ? 1.0 : 0.0;
    if (!_placed || _shown.x < 0.05) {
      _centre.jump(centre);
      _width.jump(width);
      if (!_placed) _shown.jump(shown);
      _placed = true;
    }
    if (_lastMove != null && elapsed - _lastMove! > const Duration(milliseconds: 60)) _speed *= math.exp(-dt * 12);

    final still = calm(context);
    final lift = pressed ? 1.0 + 0.6 * _press : 0.0;
    final stretch = pressed && !still ? (_speed.abs() / 2400).clamp(0.0, 0.22) : 0.0;
    final pull = pressed && !still ? _tanh((_y - rects.first.center.dy) / 48) : 0.0;
    final stiff = pressed ? 1.0 : 1.8;
    if (still) {
      _centre.jump(centre);
      _width.jump(width);
      _lift.jump(lift);
      _stretch.jump(stretch);
      _shown.jump(shown);
      _pull.jump(pull);
    } else {
      _centre.step(centre, dt, stiff: stiff);
      _width.step(width, dt, stiff: stiff);
      _lift.step(lift, dt);
      _stretch.step(stretch, dt);
      _shown.step(shown, dt);
      _pull.step(pull, dt);
    }
    final past = !pressed
        ? 0.0
        : _x < rects.first.left + 20
        ? _x - (rects.first.left + 20)
        : (_x > rects.last.right - 20 ? _x - (rects.last.right - 20) : 0.0);
    final barX = pressed && !still
        ? (_tanh(past / 70) + 0.15 * (_speed / 2400).clamp(-1.0, 1.0)).clamp(-1.0, 1.0)
        : 0.0;
    final barY = pressed && !still ? _tanh((_y - rects.first.center.dy) / 110) : 0.0;
    if (still) {
      _barX.jump(barX);
      _barY.jump(barY);
    } else {
      _barX.step(barX, dt);
      _barY.step(barY, dt);
    }
    _barPull.value = (_barX.x, _barY.x);
    setState(() {});

    final resting = _centre.restsAt(centre) &&
        _width.restsAt(width) &&
        _lift.restsAt(lift) &&
        _stretch.restsAt(stretch) &&
        _shown.restsAt(shown) &&
        _pull.restsAt(pull) &&
        _barX.restsAt(barX) &&
        _barY.restsAt(barY);
    _still = resting && !pressed ? _still + 1 : 0;
    if (_still > 20) {
      for (final (spring, to) in [
        (_centre, centre), (_width, width), (_lift, lift), (_stretch, stretch), (_shown, shown), (_pull, pull),
        (_barX, barX), (_barY, barY),
      ]) {
        spring.jump(to);
      }
      _barPull.value = (0, 0);
      _ticker.stop();
    }
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    final rects = _measure();
    if (rects == null) return;
    _rects = rects;
    _pointer = e.pointer;
    _going = null;
    _x = e.localPosition.dx;
    _y = e.localPosition.dy;
    _over = _tabAt(_x);
    _speed = 0;
    _press = 0;
    _press0 = e.pressure;
    _lastMove = e.timeStamp;
    _wake();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final last = _lastMove;
    final dt = last == null ? 0 : (e.timeStamp - last).inMicroseconds / 1e6;
    if (dt > 0) _speed = _speed * 0.6 + (e.localPosition.dx - _x) / dt * 0.4;
    _lastMove = e.timeStamp;
    _x = e.localPosition.dx;
    _y = e.localPosition.dy;
    final range = e.pressureMax - e.pressureMin;
    if (range > 0) _press = ((e.pressure - _press0) / range * 3).clamp(0.0, 1.0);
    final over = _tabAt(_x);
    if (over != _over) HapticFeedback.selectionClick();
    _over = over;
    _wake();
  }

  /// Tells the screen about the tab let go on, even when it is the tab already showing, so that opening Faces again
  /// refreshes it.
  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _wake();
    final value = _navTabs[_over].value;
    if (value != widget.index) _going = _over;
    widget.onChanged(value);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _wake();
  }

  /// Draws the chip from the springs. Lifted, it grows. Stretched by speed, it gets wider and flatter. Pulled up or
  /// down, it stands taller and slimmer and leans that way, kept inside the row so it never presses into the bar's
  /// rounded ends. The tabs' words are drawn twice, dark, and light clipped to the chip, so they turn light exactly
  /// where the chip covers them. The light copy has the chip's own colour under it so the dark copy does not show
  /// through.
  @override
  Widget build(BuildContext context) {
    final lift = _lift.x;
    final stretch = _stretch.x;
    final shown = _shown.x.clamp(0.0, 1.0);
    final pull = _pull.x;
    final chipWidth = _width.x * (1 + 0.1 * lift + stretch) * (1 - 0.1 * pull.abs());
    final chipHeight = math.min(
      _chipHeight * (1 + 0.1 * lift - 0.35 * stretch) * (1 + 0.18 * pull.abs()),
      _chipHeight + 2 * (_barInset - 3),
    );
    final chip = _placed && _rects.isNotEmpty
        ? Rect.fromCenter(
            center: Offset(
              _centre.x.clamp(
                _rects.first.left + chipWidth / 2,
                math.max(_rects.first.left + chipWidth / 2, _rects.last.right - chipWidth / 2),
              ),
              (_rects.first.center.dy + 7 * pull).clamp(
                _rects.first.center.dy - (_barInset - 3) - (_chipHeight - chipHeight) / 2,
                _rects.first.center.dy + (_barInset - 3) + (_chipHeight - chipHeight) / 2,
              ),
            ),
            width: chipWidth,
            height: chipHeight,
          )
        : null;

    Widget tabs({required bool light}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _navTabs.length; i++)
          _NavItem(
            key: light ? null : _keys[i],
            tab: _navTabs[i],
            selected: widget.index == _navTabs[i].value,
            light: light,
            showDot: _navTabs[i].value == _tabLibrary && widget.showActivityDot,
            compact: widget.compact,
            onTap: () => widget.onChanged(_navTabs[i].value),
          ),
      ],
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (chip != null && shown > 0.01)
            Positioned.fromRect(
              rect: chip,
              child: Opacity(
                opacity: shown,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22 * lift.clamp(0.0, 1.0)),
                        blurRadius: 16,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          tabs(light: false),
          if (chip != null && shown > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: shown,
                    child: ClipPath(
                      clipper: _ChipClip(chip),
                      child: ColoredBox(
                        color: AppColors.primary,
                        child: tabs(light: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _navTabs = [
  _NavTab(
    _tabLibrary,
    'Library',
    Icons.photo_library_outlined,
    Icons.photo_library_rounded,
  ),
  _NavTab(
    _tabCollections,
    'Collections',
    Icons.collections_bookmark_outlined,
    Icons.collections_bookmark_rounded,
  ),
  _NavTab(
    _tabFaces,
    'Faces',
    Icons.face_retouching_natural_outlined,
    Icons.face_retouching_natural,
  ),
];

class _ChipClip extends CustomClipper<Path> {
  const _ChipClip(this.chip);

  final Rect chip;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(RRect.fromRectAndRadius(chip, Radius.circular(chip.height / 2)));

  @override
  bool shouldReclip(_ChipClip old) => old.chip != chip;
}
