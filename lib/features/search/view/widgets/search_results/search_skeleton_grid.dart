part of '../search_results.dart';

/// A placeholder grid shaped like the real results grid, shown while a search is in flight -
/// the same shimmering _LoadingTile the real grid falls back to for a thumbnail that hasn't
/// arrived yet, just filling the whole space rather than waiting for a spinner to clear before
/// anything about the coming layout is visible.
class _SearchSkeletonGrid extends StatelessWidget {
  const _SearchSkeletonGrid({required this.layout});

  final ResultsLayout layout;

  /// Unused for bento, which builds its own SliverQuiltedGridDelegate instead of the fixed cross-axis count this
  /// getter feeds.
  int get _crossAxisCount {
    switch (layout) {
      case ResultsLayout.list:
        return 1;
      case ResultsLayout.grid2:
        return 2;
      case ResultsLayout.grid3:
        return 3;
      case ResultsLayout.grid4:
        return 4;
      case ResultsLayout.bento:
        return _bentoCrossAxisCount;
    }
  }

  /// Bento tiles are far from uniform in height, so a flat count would fall short of a screen's worth once cut off
  /// mid-pattern. A skeleton has no data to size itself against, so it renders several full pattern cycles. That is
  /// cheap, since SliverChildBuilderDelegate only builds the ones that scroll into view.
  @override
  Widget build(BuildContext context) {
    final isList = layout == ResultsLayout.list;
    final isBento = layout == ResultsLayout.bento;
    final childCount = isBento
        ? _bentoPattern.length * _bentoSkeletonCycles
        : (isList ? 6 : 12);
    return SliverGrid(
      gridDelegate: isBento
          ? _bentoGridDelegate()
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _crossAxisCount,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: isList ? 1.7 : 0.86,
            ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: _LoadingTile(index: index, isVideo: index % 3 == 2),
        ),
        childCount: childCount,
      ),
    );
  }
}

/// How many full pattern cycles the loading skeleton renders, to comfortably overshoot any real screen height (see
/// _SearchSkeletonGrid.build()).
const int _bentoSkeletonCycles = 4;

SliverQuiltedGridDelegate _bentoGridDelegate() {
  return SliverQuiltedGridDelegate(
    crossAxisCount: _bentoCrossAxisCount,
    pattern: _bentoPattern,
    repeatPattern: QuiltedGridRepeatPattern.inverted,
    mainAxisSpacing: AppSpacing.sm,
    crossAxisSpacing: AppSpacing.sm,
  );
}

/// The 14-tile, 6-row steady cycle, used as it is for the loading skeleton, which has no real result count to gate
/// showcase rarity against (see _SearchSkeletonGrid.build()). Real result grids use the generator below, which is
/// showcase-aware and sized exactly to the result count.
const List<QuiltedGridTile> _bentoPattern = [
  ..._movementHeroLeft,
  ..._movementNoHero,
  ..._movementHeroRight,
];
