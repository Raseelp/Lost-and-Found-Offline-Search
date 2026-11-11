part of '../search_results.dart';

/// The bento layout is built from small "movements", each a short run of tiles that ends with every column at the same
/// height, checked with a packing simulation copied from flutter_staggered_grid_view's algorithm. Concatenating two
/// flush movements is itself flush, so any sequence of them chains with no gaps or overlaps, which lets the generator
/// splice rare showcase movements into the steady rhythm safely.
const int _bentoCrossAxisCount = 4;

/// Steady rhythm: hero square on the left, a denser row with no hero, hero square on the right. The regular backbone
/// of the mosaic.
const List<QuiltedGridTile> _movementHeroLeft = [
  QuiltedGridTile(2, 2),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 2),
];

const List<QuiltedGridTile> _movementNoHero = [
  QuiltedGridTile(1, 1),
  QuiltedGridTile(2, 1),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 2),
];

const List<QuiltedGridTile> _movementHeroRight = [
  QuiltedGridTile(1, 1),
  QuiltedGridTile(1, 1),
  QuiltedGridTile(2, 2),
  QuiltedGridTile(1, 2),
];

/// The normal grid-tile thumbnail cap (MediaChannel.kt's MAX_COMPRESSED_DIMENSION) is tuned for a small tile, so a
/// bento tile bigger than that needs more source resolution to look sharp, scaling with the tile's size. Returns null
/// for 1 and 2 cell tiles, the hero cap for the 4-cell hero and the showcase cap for the 8 and 16 slot tiles. See
/// _ResultTile.upgradeMaxDimension.
int? _bentoUpgradeDimension(QuiltedGridTile tile) {
  final area = tile.mainAxisCount * tile.crossAxisCount;
  if (area >= 8) return _showcaseThumbnailMaxDimension;
  if (area >= 4) return _heroThumbnailMaxDimension;
  if (area >= 2) return _wideThumbnailMaxDimension;
  return null;
}

/// Higher decode caps requested only for a bento tile big enough to need them (see _bentoUpgradeDimension), instead of
/// raising the cap every tile shares. Three tiers: a 2-cell tile needs a small bump, the 4-cell hero more, the 8 and
/// 16 slot showcases a lot more. They are the "maxDimension" channel argument. MediaChannel.kt accepts any value, but
/// its MAX_COMPRESSED_DIMENSION_WIDE, _HERO and _SHOWCASE constants document what to expect, so keep them in sync.
const int _wideThumbnailMaxDimension = 1900;

const int _heroThumbnailMaxDimension = 2200;

const int _showcaseThumbnailMaxDimension = 3200;

IconData _layoutIcon(ResultsLayout layout) {
  switch (layout) {
    case ResultsLayout.list:
      return Icons.view_agenda_outlined;
    case ResultsLayout.grid2:
      return Icons.grid_view_rounded;
    case ResultsLayout.grid3:
      return Icons.view_module_rounded;
    case ResultsLayout.grid4:
      return Icons.apps_rounded;
    case ResultsLayout.bento:
      return Icons.dashboard_customize_rounded;
  }
}

/// The results grid for something other than the live search, such as a collection or a person: same tiles and
/// viewers, its own list and thumbnails. What the latest scan indexed comes first, and the rest keep their order.
Widget collectionResultsGrid({
  required List<Map<String, dynamic>> results,
  required Uint8List? Function(Map<String, dynamic> item) bytesFor,
  required String matchQuery,
  bool loading = false,
}) {
  return _ResultsSliverGrid(
    loading: loading,
    results: Get.find<LibraryController>().newFirst(results),
    bytesFor: bytesFor,
    matchQuery: matchQuery,
  );
}
