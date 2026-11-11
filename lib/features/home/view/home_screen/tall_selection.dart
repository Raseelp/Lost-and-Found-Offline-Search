part of '../home_screen.dart';

/// Who is chosen on the first row, with their faces, how many and the close button, and the two actions side by side
/// on the second. The right-hand one is the main one and is in white. It is laid out at its full height right away
/// and clipped by the bar while the bar grows.
class _TallSelection extends StatelessWidget {
  const _TallSelection({super.key, required this.selection});

  final _BarSelection selection;

  static const double _face = 30;
  static const double _overlap = 20;

  @override
  Widget build(BuildContext context) {
    final actions = selection.actions;
    final textTheme = Theme.of(context).textTheme;
    final shownFaces = selection.faceIds.take(3).toList();
    final more = selection.faceIds.length - shownFaces.length;
    final summary =
        selection.summaryFor?.call(selection.chosen) ??
        '${selection.chosen} chosen';

    return OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: _tallBarHeight - 2 * _barInset,
      child: SizedBox(
        height: _tallBarHeight - 2 * _barInset,
        child: Column(
          children: [
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: _face + _overlap * (shownFaces.length - 1) +
                        (more > 0 ? _overlap : 0),
                    height: _face,
                    child: Stack(
                      children: [
                        for (var i = 0; i < shownFaces.length; i++)
                          Positioned(
                            left: i * _overlap,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: FaceAvatar(
                                faceId: shownFaces[i],
                                size: _face - 4,
                              ),
                            ),
                          ),
                        if (more > 0)
                          Positioned(
                            left: shownFaces.length * _overlap,
                            child: Container(
                              width: _face,
                              height: _face,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryFocus,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '+$more',
                                style: textTheme.labelSmall?.copyWith(
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Cancel',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selection.onCancel,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.onPrimary.withValues(alpha: 0.18),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: _chipHeight,
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _TallActionButton(
                        action: actions[i],
                        label: actions[i].labelFor(selection.chosen),
                        main: i == actions.length - 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
