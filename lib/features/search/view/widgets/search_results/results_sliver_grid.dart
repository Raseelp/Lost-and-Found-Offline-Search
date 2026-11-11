part of '../search_results.dart';

/// A real SliverGrid, not GridView.builder(shrinkWrap: true), as explained in searchResultsSlivers.
/// SliverChildBuilderDelegate keeps its default addAutomaticKeepAlives and addRepaintBoundaries on, which stops an
/// offscreen tile's decoded image from being discarded and redecoded every time it scrolls back into view.
class _ResultsSliverGrid extends StatelessWidget {
  const _ResultsSliverGrid({
    required this.controller,
    this.results,
    this.bytesFor,
    this.matchQuery,
    this.loading = false,
  });

  final NativeController controller;

  /// Defaults to the live search. A collection passes its own list, its own thumbnail cache, and the phrase to explain
  /// matches by.
  final List<Map<String, dynamic>>? results;
  final Uint8List? Function(Map<String, dynamic> item)? bytesFor;
  final String? matchQuery;

  /// True while thumbnails are still arriving (a collection's progressive
  /// loading): a missing one then shows an animated placeholder instead of
  /// the "couldn't load" icon, which is only for one that really failed.
  final bool loading;

  List<Map<String, dynamic>> get _results =>
      results ?? controller.searchResults;

  /// Unused for bento, which builds its own SliverQuiltedGridDelegate instead of the fixed cross-axis count this
  /// getter feeds.
  int get _crossAxisCount {
    switch (controller.resultsLayout) {
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

  /// Builds the tile at [index]. [upgradeMaxDimension] is non-null only for a bento hero or showcase tile (see
  /// _bentoUpgradeDimension) and makes _ResultTile chase a sharper thumbnail. A permanent failure fades in as it is,
  /// because the reveal pacing is about a photo loading. A rapid double tap would push the viewer twice, so a tap is
  /// ignored once this tile's route is not on top any more. The match explanation is fetched without waiting. Collection
  /// grids hold small thumbnails, so the viewer loads the sharp photo itself.
  Widget _buildTile(BuildContext context, int index, {int? upgradeMaxDimension}) {
    final item = _results[index];
    final uri = item['path'] as String;
    final isVideo = item['isVideo'] as bool? ?? false;
    final timestampMs = (item['timestampMs'] as num?)?.toInt() ?? 0;
    final cacheKey = controller.cacheKeyForResult(item);
    final bytes = bytesFor != null
        ? bytesFor!(item)
        : controller.imageCache[cacheKey];

    if (bytes == null && !loading) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: const ValueKey('missing'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ColoredBox(
              color: AppColors.parchment,
              child: const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.ink48,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _RevealGate(
      cacheKey: cacheKey,
      ready: bytes != null,
      placeholder: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: _LoadingTile(index: index, isVideo: isVideo),
      ),
      child: bytes == null
          ? const SizedBox.shrink()
          : _ResultTile(
              bytes: bytes,
              isVideo: isVideo,
              upgradeMaxDimension: upgradeMaxDimension,
              uri: uri,
              timestampMs: timestampMs,
              isNew: controller.isInLatestScan(uri),
              onTap: () {
                if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
                controller.loadMatchExplanation(
                  path: uri,
                  isVideo: isVideo,
                  timestampMs: timestampMs,
                  query: matchQuery,
                );
                controller.loadMetaDataByUri(uri: uri, isVideo: isVideo);
                if (isVideo) {
                  Navigator.of(context).push(
                    mediaViewRoute(
                      (_) => VideoViewScreen(
                        videoUri: uri,
                        timestampMs: timestampMs,
                        thumbnailBytes: bytes,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    mediaViewRoute(
                      (_) => ImageViewScreen(imageBytes: bytes, uri: uri, loadFullRes: bytesFor != null),
                    ),
                  );
                }
              },
            ),
    );
  }

  /// Builds the grid from a one-off pattern generated for exactly this list (see _generateBentoPattern), not a fixed
  /// block repeating forever, so showcase placement stays irregular. The seed comes from data that is stable across
  /// this list's rebuilds, since progressive thumbnail loading changes neither the result count nor its first item,
  /// but changes for a different search or collection. Whatever the generator could not fit finishes as plain uniform
  /// rows. SliverMainAxisGroup adds no gap of its own, so the gap between the bento block and the tail is added by
  /// hand.
  @override
  Widget build(BuildContext context) {
    final isList = controller.resultsLayout == ResultsLayout.list;
    final isBento = controller.resultsLayout == ResultsLayout.bento;

    if (!isBento) {
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: isList ? 1.7 : 0.86,
        ),
        delegate: SliverChildBuilderDelegate(
          _buildTile,
          childCount: _results.length,
        ),
      );
    }

    final seed = Object.hash(
      _results.length,
      _results.isNotEmpty ? _results.first['path'] : null,
    );
    final pattern = _generateBentoPattern(
      resultCount: _results.length,
      seed: seed,
    );
    final bentoCount = pattern.length;
    final tailCount = _results.length - bentoCount;

    final slivers = <Widget>[
      if (bentoCount > 0)
        SliverGrid(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: _bentoCrossAxisCount,
            pattern: pattern,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildTile(
              context,
              index,
              upgradeMaxDimension: _bentoUpgradeDimension(pattern[index]),
            ),
            childCount: bentoCount,
          ),
        ),
      if (bentoCount > 0 && tailCount > 0)
        SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      if (tailCount > 0)
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _bentoCrossAxisCount,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.86,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, tailIndex) => _buildTile(context, bentoCount + tailIndex),
            childCount: tailCount,
          ),
        ),
    ];
    return SliverMainAxisGroup(slivers: slivers);
  }
}
