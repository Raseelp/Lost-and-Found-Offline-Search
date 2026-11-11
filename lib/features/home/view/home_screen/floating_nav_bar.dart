part of '../home_screen.dart';

/// A pill holding the three tabs, with Search as its own round button next to it. Only the selected tab shows its icon
/// and sits in a teal chip, and the others are just a label. Search selects the body the same way a tab does, so
/// while it is active the pill has nothing selected and the button takes over the highlight. It is tonal like the
/// rest of the app, with parchment on canvas and the primary colour for "on".
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onChanged,
    required this.showActivityDot,
    required this.shrunk,
    this.selection,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool showActivityDot;
  final bool shrunk;

  /// Not null while choosing people or collections, when the bar turns into the buttons that go on from the choice.
  final _BarSelection? selection;

  /// Margins are kept modest so the pill has room for the selected tab's icon and label at full size. Scrolling down
  /// shrinks the bar toward its bottom edge so it recedes from the content, and scrolling up restores it. Scale and
  /// slide are transforms, so nothing relayouts mid-scroll. The pill is translucent frosted glass and turns into the
  /// teal button while choosing. The widgets around the tabs stay the same and only numbers change, so they keep their
  /// state and the touch on them. The Search button stays mounted, folded to zero width while choosing, and is clipped
  /// only at its right edge so it can squeeze and lean without being cut.
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final margin = width >= 400 ? 20.0 : 16.0;
    final compact = width < 380;
    final selection = this.selection;
    final choosing = selection != null;
    final ready = choosing && selection.chosen > 0;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      offset: Offset(0, shrunk ? 0.08 : 0),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        scale: shrunk ? 0.93 : 1,
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            AppSpacing.sm,
            margin,
            kFloatingBarBottomGap + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<Offset>(
                  tween: Tween<Offset>(end: Offset(ready ? 1 : 0, shrunk ? 1 : 0)),
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  builder: (context, look, content) =>
                      ValueListenableBuilder<(double, double)>(
                        valueListenable: _barPull,
                        builder: (context, pull, content) {
                          final shape = _BarShape(pull.$1, pull.$2);
                          return ClipPath(
                            clipper: _BarClip(shape),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: CustomPaint(
                                painter: _BarPainter(
                                  shape,
                                  Color.lerp(
                                    AppColors.parchment.withValues(alpha: 0.72 - 0.17 * look.dy),
                                    AppColors.primary,
                                    look.dx,
                                  )!,
                                  Color.lerp(AppColors.hairline, AppColors.primary, look.dx)!,
                                ),
                                child: content,
                              ),
                            ),
                          );
                        },
                        child: content,
                      ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    height: choosing && selection.tall
                        ? _tallBarHeight
                        : _barHeight,
                    padding: const EdgeInsets.all(_barInset),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, if (current != null) current],
                      ),
                      child: choosing
                          ? _SelectionContent(
                              key: const ValueKey('choose'),
                              selection: selection,
                            )
                          : _TabPill(
                              key: const ValueKey('tabs'),
                              index: index,
                              showActivityDot: showActivityDot,
                              compact: compact,
                              onChanged: onChanged,
                            ),
                    ),
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: choosing ? 0 : 1),
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => ClipRect(
                  clipper: _FoldClip(t),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                  ),
                ),
                child: IgnorePointer(
                  ignoring: choosing,
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.sm),
                      ValueListenableBuilder<(double, double)>(
                        valueListenable: _barPull,
                        builder: (context, pull, button) => Transform.translate(
                          offset: Offset(12 * math.max(pull.$1, 0.0), 0),
                          child: button,
                        ),
                        child: _SearchButton(
                          active: index == _tabSearch,
                          shrunk: shrunk,
                          onTap: () => onChanged(_tabSearch),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoldClip extends CustomClipper<Rect> {
  const _FoldClip(this.open);

  final double open;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-40, -40, size.width + (open >= 1 ? 40 : 0), size.height + 40);

  @override
  bool shouldReclip(_FoldClip old) => old.open != open;
}

/// What the pill shows while choosing people or collections: a close button on the left, and the action or actions
/// across the rest. These are the words "Choose ..." until something is ticked, then the buttons. Two actions share
/// the width with a thin line between them.
class _SelectionContent extends StatelessWidget {
  const _SelectionContent({super.key, required this.selection});

  final _BarSelection selection;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: selection.tall
          ? _TallSelection(key: const ValueKey('tall'), selection: selection)
          : _SingleRowSelection(
              key: const ValueKey('row'),
              selection: selection,
            ),
    );
  }
}

class _BarClip extends CustomClipper<Path> {
  const _BarClip(this.shape);

  final _BarShape shape;

  @override
  Path getClip(Size size) => shape.path(size);

  @override
  bool shouldReclip(_BarClip old) =>
      old.shape.side != shape.side || old.shape.lift != shape.lift;
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.shape, this.fill, this.border);

  final _BarShape shape;
  final Color fill;
  final Color border;

  /// Paints the fill and a border that sits just inside the outline, as a box's border does.
  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.path(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.shape.side != shape.side ||
      old.shape.lift != shape.lift;
}
