part of '../then_now_screen.dart';

/// One end's photos in a row that scrolls like a wheel: the one in the middle is larger, ringed and compared, the
/// others smaller and fainter toward the edges, with its date and who is in it under it. A swipe lets the row run on
/// and slow down, landing on the photo nearest to where it would have stopped.
///
/// Each photo's semantics node carries its own tap, because a screen reader reads and presses only that node. The date
/// line changes at once, because a cross-fade could meet itself on a quick Then, Now, Then.
class _Picker extends StatefulWidget {
  const _Picker({
    required this.then,
    required this.now,
    required this.thenAt,
    required this.nowAt,
    required this.latestLabel,
    required this.memories,
    required this.onPick,
  });

  final List<ThenNowSide> then, now;
  final int thenAt, nowAt;
  final String latestLabel;
  final MemoriesController memories;
  final void Function(bool isThen, int index) onPick;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  static const double _item = 64;

  /// Then (true) or the latest (false): which end the row is choosing for.
  bool _isThen = true;
  PageController? _row;
  double _fraction = 0.2;

  /// The photo in the middle of the row. While the row runs on it is only ringed and named. The comparison changes
  /// once the row slows, because a full picture to load for every photo it passes would stutter.
  int? _centre;
  Timer? _settle;

  void _passing(int i) {
    HapticFeedback.selectionClick();
    setState(() => _centre = i);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 140), _pick);
  }

  void _pick() {
    _settle?.cancel();
    final i = _centre;
    if (i != null && mounted && i != (_isThen ? widget.thenAt : widget.nowAt)) widget.onPick(_isThen, i);
  }

  /// Rebuilds the row for each end, opening on the photo in use there. The previous controller goes once that row has
  /// gone, because it is still attached for the rest of this frame.
  void _newRow() {
    final old = _row;
    _settle?.cancel();
    _centre = null;
    _row = PageController(viewportFraction: _fraction, initialPage: _isThen ? widget.thenAt : widget.nowAt);
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Sizes the row so that each picture takes the same width whatever the screen's.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width - AppSpacing.xl * 2;
    final fraction = (_item / width).clamp(0.1, 0.5);
    if (_row == null || fraction != _fraction) {
      _fraction = fraction;
      _newRow();
    }
  }

  /// When the photo is chosen from somewhere else, the row's own choice does not stand any more.
  @override
  void didUpdateWidget(covariant _Picker old) {
    super.didUpdateWidget(old);
    final now = _isThen ? widget.thenAt : widget.nowAt;
    if (now != (_isThen ? old.thenAt : old.nowAt) && now != _centre) {
      _settle?.cancel();
      _centre = null;
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _row?.dispose();
    super.dispose();
  }

  /// The photo tapped comes to the middle: gliding there, or with motion off simply there.
  void _goTo(PageController row, int i) {
    if (calm(context)) {
      row.jumpToPage(i);
    } else {
      row.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  /// Changes the end the row chooses for. A photo still settling on this end is kept before the row changes.
  void _choose(bool isThen) {
    if (isThen == _isThen) return;
    _pick();
    HapticFeedback.selectionClick();
    setState(() {
      _isThen = isThen;
      _newRow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sides = _isThen ? widget.then : widget.now;
    final at = (_centre ?? (_isThen ? widget.thenAt : widget.nowAt)).clamp(0, sides.length - 1);
    final row = _row!;
    final shown = sides[at.clamp(0, sides.length - 1)];
    final company = shown.company;
    return Column(
      children: [
        _Segments(
          labels: ['Then', widget.latestLabel == 'NOW' ? 'Now' : 'Latest'],
          counts: [widget.then.length, widget.now.length],
          first: _isThen,
          onChanged: _choose,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _item + 16,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _pick();
              return false;
            },
            child: PageView.builder(
              key: ValueKey(_isThen),
              controller: row,
              pageSnapping: false,
              physics: _WheelPhysics(fraction: _fraction),
              clipBehavior: Clip.none,
              itemCount: sides.length,
              onPageChanged: _passing,
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: row,
                builder: (context, child) {
                  final page = row.hasClients && row.position.haveDimensions ? (row.page ?? at.toDouble()) : at.toDouble();
                  final d = (i - page).abs().clamp(0.0, 3.0);
                  return Center(
                    child: Opacity(
                      opacity: 1 - d * 0.22,
                      child: Transform.scale(scale: 1 - d * 0.16, child: child),
                    ),
                  );
                },
                child: Semantics(
                  button: true,
                  selected: i == at,
                  label: '${_monthYear(sides[i].taken)}${sides[i].company == null ? '' : ', ${sides[i].company}'}',
                  onTap: () => _goTo(row, i),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _goTo(row, i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _item - 8,
                      height: _item - 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: i == at
                            ? [
                                const BoxShadow(color: AppColors.canvas, spreadRadius: 2),
                                const BoxShadow(color: AppColors.primary, spreadRadius: 4),
                                BoxShadow(color: AppColors.shadow.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PortraitImage(side: sides[i], memories: widget.memories, small: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _monthYear(shown.taken),
                style: textTheme.bodyMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
              ),
              if (company != null) TextSpan(text: ' \u00b7 $company'),
            ],
          ),
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.ink48),
        ),
      ],
    );
  }
}

/// For the row of photos: a swipe runs on and slows by itself, as a list does, but always comes to rest on a
/// photo, the one nearest to where it would have stopped. Let go without a swipe, it settles gently onto the
/// nearest one.
class _WheelPhysics extends ScrollPhysics {
  const _WheelPhysics({required this.fraction, super.parent});

  /// The width of one photo, as a part of the row's.
  final double fraction;

  @override
  _WheelPhysics applyTo(ScrollPhysics? ancestor) => _WheelPhysics(fraction: fraction, parent: buildParent(ancestor));

  /// Past an end the usual way back is used. Otherwise the target is the photo nearest to where the glide would
  /// come to rest by itself. A move too small to leave the photo it is on springs softly back onto it, and any other
  /// glides as it would have, slowed just enough to stop on the photo.
  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final extent = position.viewportDimension * fraction;
    if (extent <= 0) return super.createBallisticSimulation(position, velocity);
    final tolerance = toleranceFor(position);
    final glide = super.createBallisticSimulation(position, velocity);
    final natural = glide?.x(double.infinity) ?? position.pixels;
    final target = ((natural / extent).round() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (velocity.abs() < tolerance.velocity && (target - position.pixels).abs() < tolerance.distance) return null;
    if ((position.pixels / extent).round() * extent == target) {
      return _Landing(SpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance), target);
    }
    return _Landing(
      FrictionSimulation.through(position.pixels, target, velocity, tolerance.velocity * velocity.sign),
      target,
    );
  }
}

/// A glide or spring that ends exactly on [target]: either stops once it is within a pixel of it.
class _Landing extends Simulation {
  _Landing(this.glide, this.target) : super(tolerance: glide.tolerance);

  final Simulation glide;
  final double target;

  @override
  double x(double time) => glide.isDone(time) ? target : glide.x(time);

  @override
  double dx(double time) => glide.isDone(time) ? 0 : glide.dx(time);

  @override
  bool isDone(double time) => glide.isDone(time);
}
