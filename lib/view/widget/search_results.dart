import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/media_view_route.dart';
import 'package:lost_and_found/utils/motion.dart';
import 'package:lost_and_found/view/image_full_screen.dart';
import 'package:lost_and_found/view/video_full_screen.dart';
import 'package:lost_and_found/view/widget/grid_video_layer.dart';
import 'package:lost_and_found/view/widget/moment_badge.dart';
import 'package:lost_and_found/view/widget/new_tag.dart';

/// Higher decode caps requested only for a bento tile big enough to need them (see _bentoUpgradeDimension), instead of
/// raising the cap every tile shares. Three tiers: a 2-cell tile needs a small bump, the 4-cell hero more, the 8 and
/// 16 slot showcases a lot more. They are the "maxDimension" channel argument. MainActivity.kt accepts any value, but
/// its MAX_COMPRESSED_DIMENSION_WIDE, _HERO and _SHOWCASE constants document what to expect, so keep them in sync.
const int _wideThumbnailMaxDimension = 1900;
const int _heroThumbnailMaxDimension = 2200;
const int _showcaseThumbnailMaxDimension = 3200;

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
const List<List<QuiltedGridTile>> _steadyRotation = [
  _movementHeroLeft,
  _movementNoHero,
  _movementHeroRight,
];

/// Rare showcase movements: one full-bleed photo taking up far more room than usual, spliced sparingly into the steady
/// rhythm by _generateBentoPattern rather than appearing on a fixed schedule. In the tall right hero, a filler placed
/// first is strictly ahead and forces the hero onto the right half, and a catch-up filler re-flushes the left side.
const List<QuiltedGridTile> _showcaseHorizontal = [
  QuiltedGridTile(2, 4),
];
const List<QuiltedGridTile> _showcaseVerticalLeft = [
  QuiltedGridTile(4, 2),
  QuiltedGridTile(2, 2),
  QuiltedGridTile(2, 2),
];
const List<QuiltedGridTile> _showcaseVerticalRight = [
  QuiltedGridTile(2, 2),
  QuiltedGridTile(4, 2),
  QuiltedGridTile(2, 2),
];
const List<List<QuiltedGridTile>> _showcaseOptions = [
  _showcaseHorizontal,
  _showcaseVerticalLeft,
  _showcaseVerticalRight,
];
const List<QuiltedGridTile> _showcaseGiant = [
  QuiltedGridTile(4, 4),
];

/// The normal grid-tile thumbnail cap (MainActivity.kt's MAX_COMPRESSED_DIMENSION) is tuned for a small tile, so a
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

/// The 14-tile, 6-row steady cycle, used as it is for the loading skeleton, which has no real result count to gate
/// showcase rarity against (see _SearchSkeletonGrid.build()). Real result grids use the generator below, which is
/// showcase-aware and sized exactly to the result count.
const List<QuiltedGridTile> _bentoPattern = [
  ..._movementHeroLeft,
  ..._movementNoHero,
  ..._movementHeroRight,
];

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

/// A showcase is not considered until the list has enough room left to stay a small minority of the content, which
/// keeps a short result set from being dominated by one giant tile. The giant tile needs an even larger runway and a
/// wider gap from the last showcase, so it reads as rarer than the 8-slot ones. The base chances (0.15 and 0.04) were
/// scaled by 2.5 after testing on a real device.
const int _showcaseMinRemainingItems = 20;
const int _showcaseMinMovementGap = 3;
const double _showcaseChance = 0.375;
const int _giantMinRemainingItems = 40;
const int _giantMinMovementGap = 6;
const double _giantChance = 0.1;

/// Builds a one-off pattern sized to exactly `resultCount` items, or as close as a whole number of movements allows,
/// with the rest finished by the tail in _ResultsSliverGrid.build. It sprinkles rare showcase movements into the
/// steady rotation instead of using one fixed pattern. `seed` must be stable across rebuilds of the same result set,
/// or the mosaic would visibly reshuffle mid-load, so derive it from something that only changes when the results do.
/// A movement that does not fit is left out, because a partial movement cannot be flush.
List<QuiltedGridTile> _generateBentoPattern({
  required int resultCount,
  required int seed,
}) {
  final rng = Random(seed);
  final pattern = <QuiltedGridTile>[];
  var steadyIndex = 0;
  var movementsSinceShowcase = _showcaseMinMovementGap;
  var movementsSinceGiant = _giantMinMovementGap;

  while (true) {
    final remaining = resultCount - pattern.length;
    final giantEligible = remaining >= _giantMinRemainingItems &&
        movementsSinceGiant >= _giantMinMovementGap;
    final showcaseEligible = remaining >= _showcaseMinRemainingItems &&
        movementsSinceShowcase >= _showcaseMinMovementGap;

    List<QuiltedGridTile> next;
    var isShowcase = false;
    var isGiant = false;

    if (giantEligible && rng.nextDouble() < _giantChance) {
      next = _showcaseGiant;
      isShowcase = true;
      isGiant = true;
    } else if (showcaseEligible && rng.nextDouble() < _showcaseChance) {
      next = _showcaseOptions[rng.nextInt(_showcaseOptions.length)];
      isShowcase = true;
    } else {
      next = _steadyRotation[steadyIndex % _steadyRotation.length];
      steadyIndex++;
    }

    if (pattern.length + next.length > resultCount) break;

    pattern.addAll(next);
    movementsSinceShowcase = isShowcase ? 0 : movementsSinceShowcase + 1;
    movementsSinceGiant = isGiant ? 0 : movementsSinceGiant + 1;
  }

  return pattern;
}

/// Returns the results as slivers so SearchTab's CustomScrollView is the one scrollable and the grid can virtualize. A
/// GridView.builder with shrinkWrap inside a SingleChildScrollView loses lazy building and recycling, so with many
/// results it held far more decoded images than are visible, which caused crashes and images flickering while
/// scrolling.
List<Widget> searchResultsSlivers({required NativeController controller}) {
  if (controller.isSearching) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: _SearchSkeletonGrid(layout: controller.resultsLayout),
      ),
    ];
  }

  if (controller.error.isNotEmpty) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: SliverToBoxAdapter(
          child: _CenterNote(
            icon: Icons.error_outline_rounded,
            title: 'Something went wrong',
            subtitle: controller.error,
          ),
        ),
      ),
    ];
  }

  if (controller.searchResults.isEmpty) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: SliverToBoxAdapter(
          child: _CenterNote(
            icon: Icons.search_rounded,
            title: 'Search your media',
            subtitle: controller.totalEmbeddings == 0
                ? 'Index a folder or your phone first, then come back to search.'
                : 'Describe a photo, place, or moment above.',
          ),
        ),
      ),
    ];
  }

  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      sliver: SliverToBoxAdapter(
        child: Builder(
          builder: (context) => Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  '${controller.searchResults.length} results',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.ink48,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              _LayoutPickerButton(controller: controller),
            ],
          ),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: _ResultsSliverGrid(controller: controller),
    ),
  ];
}

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

/// A cache key that has made it through this gate once stays revealed for good. It is kept in memory only, cleared on
/// app restart, because it is purely cosmetic. Scrolling a tile out of view and back, or any later rebuild, never
/// replays the reveal for a photo the user has already been shown.
final Set<String> _revealedTileKeys = <String>{};

/// However fast a photo's bytes arrive, even if already in memory on the first frame, the placeholder stays up for at
/// least this long the first time its cache key is shown, so a load always reads as a deliberate reveal rather than a
/// jarring pop-in. It is paid once per cache key (see _revealedTileKeys).
const Duration _minimumRevealDelay = Duration(milliseconds: 450);

/// Gates the swap from placeholder to real content behind _minimumRevealDelay (first time only) and a plain crossfade
/// (every time). The timer starts at mount, not at data arrival, so slow bytes are never held up any further.
class _RevealGate extends StatefulWidget {
  const _RevealGate({
    required this.cacheKey,
    required this.ready,
    required this.placeholder,
    required this.child,
  });

  final String cacheKey;
  final bool ready;
  final Widget placeholder;
  final Widget child;

  @override
  State<_RevealGate> createState() => _RevealGateState();
}

class _RevealGateState extends State<_RevealGate> {
  bool _delayElapsed = false;

  @override
  void initState() {
    super.initState();
    _startOrSkipDelay();
  }

  /// A different item can land in the same slot, from a fresh search or the bento pattern reshuffling which index gets
  /// which tile. Only a different cache key re-arms the delay.
  @override
  void didUpdateWidget(_RevealGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _delayElapsed = false;
      _startOrSkipDelay();
    }
  }

  void _startOrSkipDelay() {
    if (_revealedTileKeys.contains(widget.cacheKey)) {
      _delayElapsed = true;
      return;
    }
    Future.delayed(_minimumRevealDelay, () {
      if (!mounted) return;
      setState(() => _delayElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reveal = widget.ready && _delayElapsed;
    if (reveal) _revealedTileKeys.add(widget.cacheKey);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(reveal),
        child: reveal ? widget.child : widget.placeholder,
      ),
    );
  }
}

/// The small play mark in the corner of a video's tile.
class _PlayMark extends StatelessWidget {
  const _PlayMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: AppColors.onMedia,
        size: 13,
      ),
    );
  }
}

class _ResultTile extends StatefulWidget {
  const _ResultTile({
    required this.bytes,
    required this.isVideo,
    required this.onTap,
    this.upgradeMaxDimension,
    this.uri,
    this.timestampMs = 0,
    this.isNew = false,
  });

  final Uint8List bytes;
  final bool isVideo;
  final VoidCallback onTap;

  /// Whether the latest scan indexed it, which tags the tile.
  final bool isNew;

  /// Non-null only for a bento hero or showcase tile (see _bentoUpgradeDimension). [bytes] is still the cheap
  /// grid-tile decode and arrives at once so the tile never waits, and this triggers a one-time background fetch of a
  /// sharper version at that cap, crossfaded in when it lands, instead of raising the shared per-tile cap that every
  /// tile would pay for.
  final int? upgradeMaxDimension;
  final String? uri;
  final int timestampMs;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile>
    with SingleTickerProviderStateMixin {
  Uint8List? _upgradedBytes;

  /// Bumped every time _maybeUpgrade is triggered. A result that lands after a later request has started is from a
  /// superseded uri, since the same State can be reused for a different item at this grid index (see didUpdateWidget),
  /// and must be dropped.
  int _upgradeRequestId = 0;

  /// Plays once, the moment a sharper upgrade lands (see _maybeUpgrade). It is never touched for tiles that have no
  /// upgrade, so it costs nothing except on the rare hero or showcase tile. It drives the sheen and scale in build().
  late final AnimationController _focusReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void initState() {
    super.initState();
    _maybeUpgrade();
  }

  @override
  void dispose() {
    _focusReveal.dispose();
    super.dispose();
  }

  /// Uint8List has no structural equality, so this is an identity check. The same cached bytes object coming through
  /// on a rebuild, while thumbnails for other tiles stream in, correctly does nothing, and only a different item
  /// landing in this slot re-triggers the fetch.
  @override
  void didUpdateWidget(_ResultTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes || oldWidget.uri != widget.uri) {
      _upgradedBytes = null;
      _focusReveal.value = 0;
      _maybeUpgrade();
    }
  }

  /// Fetches the sharper version. The normal-res bytes already on screen are a fine fallback, so a missed upgrade
  /// never surfaces an error.
  Future<void> _maybeUpgrade() async {
    final maxDimension = widget.upgradeMaxDimension;
    if (maxDimension == null || widget.uri == null) return;
    final requestId = ++_upgradeRequestId;
    try {
      final upgraded = widget.isVideo
          ? await NativeServices().loadVideoThumbnail(
              uri: widget.uri!,
              timestampMs: widget.timestampMs,
              maxDimension: maxDimension,
            )
          : await NativeServices().loadImageBytes(
              uri: widget.uri!,
              isCompressed: true,
              maxDimension: maxDimension,
            );
      if (!mounted || requestId != _upgradeRequestId) return;
      setState(() => _upgradedBytes = upgraded);
      _focusReveal.forward(from: 0);
    } catch (_) {
    }
  }

  /// Image.memory decodes only to roughly the tile's on-screen size, off the longer tile edge, because the source's
  /// full resolution made scrolling memory-hungry. Only cacheWidth is set, because both cacheWidth and cacheHeight
  /// decode to exactly that box and ignore the photo's aspect ratio, which stretched thumbnails. AnimatedSwitcher's
  /// default layoutBuilder uses StackFit.loose, which let Image.memory fall back to its intrinsic size and leave a
  /// border, so the override uses StackFit.expand. _focusReveal adds a one-shot bell-shaped sheen and a small settling
  /// scale when an upgrade lands, and does nothing for tiles without one.
  @override
  Widget build(BuildContext context) {
    final activeBytes = _upgradedBytes ?? widget.bytes;
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final tileEdge = constraints.maxWidth > constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final cacheWidth = tileEdge.isFinite
                  ? (tileEdge * dpr).round()
                  : null;

              return Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _focusReveal,
                    builder: (context, child) {
                      final t = _focusReveal.value;
                      final eased = Curves.easeOutCubic.transform(t);
                      final scale = 1.02 - 0.02 * eased;
                      final sheenStrength = sin(t * pi).clamp(0.0, 1.0);
                      return Transform.scale(
                        scale: scale,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child!,
                            if (sheenStrength > 0.01)
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-1.6 + 3.2 * t, -1),
                                      end: Alignment(-0.5 + 3.2 * t, 1),
                                      colors: [
                                        AppColors.transparent,
                                        AppColors.primaryFocus.withValues(
                                          alpha: sheenStrength * 0.16,
                                        ),
                                        AppColors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOut,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Image.memory(
                        activeBytes,
                        key: ValueKey(identityHashCode(activeBytes)),
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                      ),
                    ),
                  ),
                  if (widget.isVideo)
                    widget.uri == null
                        ? const Positioned(right: 6, bottom: 6, child: _PlayMark())
                        : GridVideoLayer(uri: widget.uri!, idleBadge: const _PlayMark()),
                  if (widget.isNew)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: NewTag(compact: constraints.maxWidth < 96),
                    ),
                  Positioned(
                    right: 9,
                    top: 0,
                    child: MomentTag(uri: widget.uri, compact: constraints.maxWidth < 96),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The same bordered pill with a chevron as the scan-scope control, and the same sheet-with-options pattern for
/// picking, so pickers look and behave alike.
class _LayoutPickerButton extends StatelessWidget {
  const _LayoutPickerButton({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => _showLayoutPicker(context, controller),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _layoutIcon(controller.resultsLayout),
                size: 14,
                color: AppColors.ink80,
              ),
              const SizedBox(width: AppSpacing.xxs),
              const Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: AppColors.ink48,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showLayoutPicker(BuildContext context, NativeController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (_) => _LayoutSheet(controller: controller),
  );
}

class _LayoutSheet extends StatelessWidget {
  const _LayoutSheet({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  'How should results be laid out?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              for (final layout in ResultsLayout.values) ...[
                if (layout != ResultsLayout.values.first)
                  const Divider(height: 1, color: AppColors.dividerSoft),
                _LayoutOption(
                  layout: layout,
                  selected: controller.resultsLayout == layout,
                  onTap: () {
                    controller.setResultsLayout(layout);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutOption extends StatelessWidget {
  const _LayoutOption({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final ResultsLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              _layoutIcon(layout),
              size: 18,
              color: selected ? AppColors.primary : AppColors.ink48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                _layoutLabel(layout),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

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

String _layoutLabel(ResultsLayout layout) {
  switch (layout) {
    case ResultsLayout.list:
      return 'List - one large preview per row';
    case ResultsLayout.grid2:
      return 'Grid - 2 across';
    case ResultsLayout.grid3:
      return 'Grid - 3 across';
    case ResultsLayout.grid4:
      return 'Grid - 4 across';
    case ResultsLayout.bento:
      return 'Bento - varied tile sizes';
  }
}

class _CenterNote extends StatelessWidget {
  const _CenterNote({
    this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData? icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Column(
        children: [
          if (icon != null) Icon(icon, size: 32, color: AppColors.ink48),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The results grid for something other than the live search, such as a collection or a person: same tiles and
/// viewers, its own list and thumbnails. What the latest scan indexed comes first, and the rest keep their order.
Widget collectionResultsGrid({
  required NativeController controller,
  required List<Map<String, dynamic>> results,
  required Uint8List? Function(Map<String, dynamic> item) bytesFor,
  required String matchQuery,
  bool loading = false,
}) {
  return _ResultsSliverGrid(
    loading: loading,
    controller: controller,
    results: controller.newFirst(results),
    bytesFor: bytesFor,
    matchQuery: matchQuery,
  );
}

/// What a thumbnail that has not arrived yet looks like: a soft band of light drifting across the tile while a small
/// icon that suits the media fades in and out, swapping every moment, so a grid that is still filling in feels like it
/// is being developed rather than broken.
class _LoadingTile extends StatefulWidget {
  const _LoadingTile({required this.index, required this.isVideo});

  final int index;
  final bool isVideo;

  @override
  State<_LoadingTile> createState() => _LoadingTileState();
}

class _LoadingTileState extends State<_LoadingTile>
    with SingleTickerProviderStateMixin {
  static const _imageIcons = [
    Icons.landscape_outlined,
    Icons.wb_sunny_outlined,
    Icons.local_florist_outlined,
    Icons.pets_outlined,
    Icons.photo_outlined,
  ];
  static const _videoIcons = [
    Icons.movie_outlined,
    Icons.play_circle_outline_rounded,
    Icons.videocam_outlined,
  ];

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  Timer? _swap;
  late int _iconIndex = widget.index;

  List<IconData> get _icons => widget.isVideo ? _videoIcons : _imageIcons;

  /// Neighbouring tiles start at different points so the grid does not pulse in lockstep. The value has to be set
  /// before repeat() starts, because the AnimationController.value setter stops the controller, and the other order
  /// cancelled the repeat in the same frame and left the shimmer frozen. With motion off the icon stays as it is,
  /// because changing it with no fade would blink across the grid.
  @override
  void initState() {
    super.initState();
    _sweep.value = (widget.index * 0.137) % 1;
    _swap = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (mounted && !calm(context)) setState(() => _iconIndex++);
    });
  }

  /// With motion off the shimmer rests, each tile where it was.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _sweep, rest: (widget.index * 0.137) % 1);
  }

  @override
  void dispose() {
    _swap?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  /// A grid full of these ticks constantly and independently, so the tile has its own compositing layer. Without it,
  /// every tile's sweep would ask Flutter to reconsider repainting the whole grid each frame.
  @override
  Widget build(BuildContext context) {
    final icon = _icons[_iconIndex % _icons.length];

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) {
          final t = _sweep.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-2 + 4 * t, -1),
                end: Alignment(-1 + 4 * t, 1),
                colors: const [
                  AppColors.parchment,
                  AppColors.pearl,
                  AppColors.parchment,
                ],
              ),
            ),
            child: child,
          );
        },
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              icon,
              key: ValueKey(icon),
              size: 28,
              color: AppColors.ink48.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
