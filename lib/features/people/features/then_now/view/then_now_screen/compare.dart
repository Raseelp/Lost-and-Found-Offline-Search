part of '../then_now_screen.dart';

/// The two pictures one over the other: "then" on the left of the divider, "now" on the right.
class _Compare extends StatelessWidget {
  const _Compare({
    required this.then,
    required this.now,
    required this.latestLabel,
    required this.split,
    required this.memories,
    required this.onSet,
  });

  final ThenNowSide then, now;
  final String latestLabel;
  final ValueNotifier<double> split;
  final MemoriesController memories;
  final ValueChanged<double> onSet;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSet(d.localPosition.dx / w),
          onHorizontalDragStart: (d) => onSet(d.localPosition.dx / w),
          onHorizontalDragUpdate: (d) => onSet(d.localPosition.dx / w),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PortraitImage(side: now, memories: memories),
                ValueListenableBuilder<double>(
                  valueListenable: split,
                  builder: (context, s, _) => ClipRect(
                    clipper: _LeftOf(s),
                    child: PortraitImage(side: then, memories: memories),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: split,
                  builder: (context, s, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: s * w - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const ColoredBox(color: AppColors.onMedia),
                      ),
                      Positioned(
                        left: s * w - 20,
                        top: box.maxHeight / 2 - 20,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.onMedia,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadow.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _Tag(
                          label: 'THEN · ${_monthYear(then.taken)}',
                          opacity: ((s - 0.18) / 0.2).clamp(0.0, 1.0),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _Tag(
                          label: '$latestLabel · ${_monthYear(now.taken)}',
                          opacity: ((0.82 - s) / 0.2).clamp(0.0, 1.0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  _LeftOf(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.share != share;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.opacity});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.scrim.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onMedia,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
