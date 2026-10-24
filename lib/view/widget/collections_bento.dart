import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

// The Collections tab's mosaic: the same bento idea as the search results, with fewer, bigger
// tiles (a collection is a place to go to, not a thumbnail). Three shapes on a four-cell grid:
// a square (2x2 cells), a tall tile (4 rows x 2 columns) and a wide one (2 rows x 4 columns).
// The biggest collections get the tall and wide tiles.

enum BentoShape { square, tall, wide }

QuiltedGridTile bentoTile(BentoShape shape) {
  switch (shape) {
    case BentoShape.square:
      return const QuiltedGridTile(2, 2);
    case BentoShape.tall:
      return const QuiltedGridTile(4, 2);
    case BentoShape.wide:
      return const QuiltedGridTile(2, 4);
  }
}

int _area(BentoShape shape) => shape == BentoShape.square ? 4 : 8;

// Each block fills whole rows on its own (the grid places tiles one after another, never
// going back), so any run of blocks leaves no gaps. B is A mirrored: its tall tile is on the
// right.
const List<BentoShape> _blockA = [
  BentoShape.tall,
  BentoShape.square,
  BentoShape.square,
  BentoShape.wide,
  BentoShape.square,
  BentoShape.square,
];
const List<BentoShape> _blockB = [
  BentoShape.square,
  BentoShape.tall,
  BentoShape.square,
  BentoShape.wide,
  BentoShape.square,
  BentoShape.square,
];

/// The shapes for [count] tiles, in the order the grid places them.
List<BentoShape> bentoShapesFor(int count) {
  final out = <BentoShape>[];
  var mirrored = false;
  while (count - out.length >= 6) {
    out.addAll(mirrored ? _blockB : _blockA);
    mirrored = !mirrored;
  }
  const s = BentoShape.square;
  switch (count - out.length) {
    case 1:
      out.add(BentoShape.wide);
    case 2:
      out.addAll(const [s, s]);
    case 3:
      out.addAll(mirrored ? const [s, BentoShape.tall, s] : const [BentoShape.tall, s, s]);
    case 4:
      out.addAll(const [s, s, s, s]);
    case 5:
      out.addAll(
        mirrored ? const [s, BentoShape.tall, s, s, s] : const [BentoShape.tall, s, s, s, s],
      );
  }
  return out;
}

/// For each slot of [shapes], which item goes there: the item with the highest count takes the
/// first of the biggest slots, and so on down. Ties keep their order.
List<int> bentoAssignment(List<BentoShape> shapes, List<int> counts) {
  assert(shapes.length == counts.length);
  final slots = List<int>.generate(shapes.length, (i) => i)
    ..sort((a, b) {
      final byArea = _area(shapes[b]).compareTo(_area(shapes[a]));
      return byArea != 0 ? byArea : a.compareTo(b);
    });
  final items = List<int>.generate(counts.length, (i) => i)
    ..sort((a, b) {
      final byCount = counts[b].compareTo(counts[a]);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  final result = List<int>.filled(shapes.length, 0);
  for (var k = 0; k < slots.length; k++) {
    result[slots[k]] = items[k];
  }
  return result;
}

/// How much taller than wide a tile is: the mosaic's cells are stretched up by this much (the
/// widths, and the gaps between tiles, stay as they were).
const double kBentoTallness = 1.2;

SliverGridDelegate bentoDelegate(List<BentoShape> shapes) {
  return _TallerQuiltDelegate(
    SliverQuiltedGridDelegate(
      crossAxisCount: 4,
      pattern: [for (final shape in shapes) bentoTile(shape)],
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
    ),
    crossAxisCount: 4,
    spacing: AppSpacing.sm,
    tallness: kBentoTallness,
  );
}

// The quilted grid always makes square cells. This lays the tiles out the same way and then
// stretches every row by [tallness], keeping the gaps as they are, so tiles come out a bit
// taller than wide and everything still lines up.
class _TallerQuiltDelegate extends SliverGridDelegate {
  _TallerQuiltDelegate(
    this.inner, {
    required this.crossAxisCount,
    required this.spacing,
    required this.tallness,
  });

  final SliverQuiltedGridDelegate inner;
  final int crossAxisCount;
  final double spacing;
  final double tallness;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final cell = (constraints.crossAxisExtent + spacing) / crossAxisCount - spacing;
    return _TallerQuiltLayout(
      inner.getLayout(constraints),
      stride: cell + spacing,
      newStride: cell * tallness + spacing,
      spacing: spacing,
    );
  }

  @override
  bool shouldRelayout(covariant _TallerQuiltDelegate oldDelegate) =>
      oldDelegate.tallness != tallness ||
      oldDelegate.spacing != spacing ||
      oldDelegate.crossAxisCount != crossAxisCount ||
      inner.shouldRelayout(oldDelegate.inner);
}

class _TallerQuiltLayout extends SliverGridLayout {
  const _TallerQuiltLayout(
    this.inner, {
    required this.stride,
    required this.newStride,
    required this.spacing,
  });

  final SliverGridLayout inner;
  final double stride;
  final double newStride;
  final double spacing;

  // Rows are whole numbers of strides, so a position is worked out in rows and put back in the
  // taller scale.
  double _scale(double value) => (((value + spacing) / stride) * newStride) - spacing;

  @override
  double computeMaxScrollOffset(int childCount) =>
      childCount == 0 ? 0 : _scale(inner.computeMaxScrollOffset(childCount));

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final g = inner.getGeometryForChildIndex(index);
    return SliverGridGeometry(
      scrollOffset: (g.scrollOffset / stride) * newStride,
      crossAxisOffset: g.crossAxisOffset,
      mainAxisExtent: _scale(g.mainAxisExtent),
      crossAxisExtent: g.crossAxisExtent,
    );
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      inner.getMinChildIndexForScrollOffset((scrollOffset / newStride) * stride);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      inner.getMaxChildIndexForScrollOffset((scrollOffset / newStride) * stride);
}

// ------------------------------------------------------------------------------- the hero

/// One featured collection at the top of the tab, a different one every few seconds (and a
/// different set each day, with the ones that just got new photos first). Swipe to move on
/// yourself; it holds still while a finger is on it. The cover drifts slowly while it is up.
class CollectionsHero extends StatefulWidget {
  const CollectionsHero({
    super.key,
    required this.controller,
    required this.native,
    required this.onOpen,
    required this.onMenu,
  });

  final CollectionsController controller;
  final NativeController native;
  final ValueChanged<SmartCollection> onOpen;
  final ValueChanged<SmartCollection> onMenu;

  @override
  State<CollectionsHero> createState() => _CollectionsHeroState();
}

class _CollectionsHeroState extends State<CollectionsHero> with SingleTickerProviderStateMixin {
  // How long one collection stays up before the next slides in.
  static const double _pageSeconds = 6.5;

  final PageController _pages = PageController();
  final ValueNotifier<double> _drift = ValueNotifier(0);
  // The page showing (the pages that are built while sliding in read it too).
  final ValueNotifier<int> _showing = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _elapsed = 0;
  bool _held = false;
  int _page = 0;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    // A ticker stops by itself while this tab is not on screen (the tabs are kept alive but
    // told to stop their tickers), so nothing runs for a tab nobody is looking at.
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pages.dispose();
    _drift.dispose();
    _showing.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    if (_held || _count < 2 || !_pages.hasClients) return;
    _elapsed += dt;
    _drift.value = (_elapsed / _pageSeconds).clamp(0.0, 1.0);
    if (_elapsed >= _pageSeconds) {
      _elapsed = 0;
      final next = (_page + 1) % _count;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(next);
      } else {
        _pages.animateToPage(
          next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final list = controller.heroCandidates(isNew: widget.native.isInLatestScan);
    if (list.isEmpty) return const SizedBox.shrink();
    _count = list.length;
    if (_page >= list.length) _page = 0;

    return Listener(
      onPointerDown: (_) => _held = true,
      onPointerUp: (_) => _held = false,
      onPointerCancel: (_) => _held = false,
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: list.length,
              onPageChanged: (i) {
                _page = i;
                _showing.value = i;
                _elapsed = 0;
                _drift.value = 0;
              },
              itemBuilder: (context, i) {
                final c = list[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _HeroPage(
                    collection: c,
                    count: controller.statsFor(c.id).count,
                    bytes: controller.heroBytesFor(c.id),
                    fresh: controller.hasNewCover(c.id, widget.native.isInLatestScan),
                    drift: _drift,
                    showing: _showing,
                    index: i,
                    onTap: () => widget.onOpen(c),
                    onLongPress: () => widget.onMenu(c),
                  ),
                );
              },
            ),
            if (list.length > 1)
              Positioned(
                right: AppSpacing.base + 2,
                bottom: AppSpacing.base,
                child: IgnorePointer(
                  child: _HeroDots(pages: _pages, count: list.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({
    required this.collection,
    required this.count,
    required this.bytes,
    required this.fresh,
    required this.drift,
    required this.showing,
    required this.index,
    required this.onTap,
    required this.onLongPress,
  });

  final SmartCollection collection;
  final int count;
  final Uint8List? bytes;
  final bool fresh;
  final ValueNotifier<double> drift;
  final ValueNotifier<int> showing;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([drift, showing]),
                  builder: (context, child) => Transform.scale(
                    scale: showing.value == index ? 1 + 0.07 * drift.value : 1,
                    child: child,
                  ),
                  child: Image.memory(
                    bytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 900,
                    gaplessPlayback: true,
                  ),
                ),
              )
            else
              Center(
                child: Icon(collection.icon, size: 44, color: AppColors.ink48),
              ),
            if (bytes != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.transparent,
                      AppColors.scrim.withValues(alpha: 0.66),
                    ],
                    stops: const [0.4, 1],
                  ),
                ),
              ),
            Positioned(
              left: AppSpacing.base + 2,
              right: AppSpacing.xxxl,
              bottom: AppSpacing.base,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fresh ? 'NEW PHOTOS' : 'FEATURED',
                    style: textTheme.labelSmall?.copyWith(
                      color: bytes != null ? AppColors.onMedia70 : AppColors.ink48,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      color: bytes != null ? AppColors.onMedia : AppColors.ink,
                    ),
                  ),
                  Text(
                    count == 1 ? '1 item' : '$count items',
                    style: textTheme.bodySmall?.copyWith(
                      color: bytes != null ? AppColors.onMedia70 : AppColors.ink48,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One small pill per featured collection; the one showing is wider and solid.
class _HeroDots extends StatelessWidget {
  const _HeroDots({required this.pages, required this.count});

  final PageController pages;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pages,
      builder: (context, _) {
        final page = pages.hasClients && pages.page != null ? pages.page! : 0.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(left: 4),
                width: 6 + 10 * (1 - (page - i).abs().clamp(0.0, 1.0)),
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.onMedia.withValues(
                    alpha: 0.45 + 0.5 * (1 - (page - i).abs().clamp(0.0, 1.0)),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        );
      },
    );
  }
}
