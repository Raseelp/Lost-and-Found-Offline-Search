import 'package:flutter/material.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/view/collection_screen.dart';
import 'package:lost_and_found/view/widget/collection_widgets.dart';
import 'package:lost_and_found/view/widget/collections_bento.dart';
import 'package:lost_and_found/view/widget/header_action.dart';
import 'package:lost_and_found/view/widget/nothing_indexed.dart';

/// Opens [collection] - shared by the tab's cards and the Search tab's chips.
void openCollectionScreen(
  BuildContext context,
  CollectionsController controller,
  SmartCollection collection,
) {
  controller.openCollection(collection);
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CollectionScreen()));
}

// The full grid: the user's own collections first, then the built-ins that
// aren't hidden. Long-press a card to edit/hide/delete.
class CollectionsTab extends StatelessWidget {
  const CollectionsTab({
    super.key,
    required this.controller,
    required this.native,
  });

  final CollectionsController controller;
  final NativeController native;

  Widget _tile(BuildContext context, SmartCollection collection, int slot) {
    return CollectionCard(
      key: ValueKey(collection.id),
      collection: collection,
      stats: controller.statsFor(collection.id),
      stack: controller.stackBytes(collection.id),
      glow: controller.glowFor(collection.id),
      isNew: controller.hasNewCover(collection.id, native.isInLatestScan),
      index: slot,
      syncing: controller.syncing.contains(collection.id),
      selecting: controller.selecting,
      selected: controller.selectedIds.contains(collection.id),
      onTap: () => controller.selecting
          ? controller.toggleSelected(collection.id)
          : openCollectionScreen(context, controller, collection),
      onLongPress: () => controller.selecting
          ? controller.toggleSelected(collection.id)
          : showCollectionMenu(context, collection, controller),
    );
  }

  // A run of tiles in the grid, [list] in the order given on [shapes].
  Widget _grid(
    BuildContext context,
    List<SmartCollection> list,
    List<BentoShape> shapes,
    List<int> order,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: SliverGrid(
        gridDelegate: bentoDelegate(shapes),
        delegate: SliverChildBuilderDelegate(
          (context, slot) => _tile(context, list[order[slot]], slot),
          childCount: list.length,
        ),
      ),
    );
  }

  // Plain squares, two across, the same size as the mosaic's squares (an odd number of them
  // cannot be laid out as a mosaic: it would leave a hole in the last row).
  Widget _squares(BuildContext context, List<SmartCollection> list) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1 / kBentoTallness,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, slot) => _tile(context, list[slot], slot),
          childCount: list.length,
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String subtitle) {
    final textTheme = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.ink48,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The tiles, in three runs: the collections worth looking at in a bento mosaic (the biggest
  // get the biggest tiles), then the everyday ones (documents, screenshots ...) in plain squares,
  // then, tucked away, the built-ins that have nothing in them yet.
  List<Widget> _mosaicSlivers(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final all = controller.visible;
    int count(SmartCollection c) => controller.statsFor(c.id).count;

    // Only once everything has been scored; a collection you made, or one being worked out
    // right now, is never put away.
    bool noMatches(SmartCollection c) =>
        controller.hasScored &&
        c.isBuiltIn &&
        !controller.syncing.contains(c.id) &&
        count(c) == 0;

    final main = [
      for (final c in all)
        if (!noMatches(c) && !c.isEveryday) c,
    ];
    final everyday = [
      for (final c in all)
        if (!noMatches(c) && c.isEveryday) c,
    ]..sort((a, b) => count(b).compareTo(count(a)));
    final none = [
      for (final c in all)
        if (noMatches(c)) c,
    ];

    final shapes = bentoShapesFor(main.length);
    final order = bentoAssignment(shapes, [for (final c in main) count(c)]);

    return [
      if (main.isNotEmpty) _grid(context, main, shapes, order),
      if (everyday.isNotEmpty) ...[
        _heading(
          context,
          'Everyday',
          'Documents, screenshots, tickets and the like.',
        ),
        _squares(context, everyday),
      ],
      if (none.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              0,
            ),
            child: InkWell(
              onTap: controller.toggleShowEmpty,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        none.length == 1
                            ? '1 collection has no matches yet'
                            : '${none.length} collections have no matches yet',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                        ),
                      ),
                    ),
                    Text(
                      controller.showEmpty ? 'Hide' : 'Show',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (controller.showEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          _squares(context, none),
        ],
      ],
    ];
  }

  // Nothing is indexed yet: no tiles to show, just where to start.
  Widget _nothingYet(BuildContext context) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxxl,
          AppSpacing.xxl,
          0,
        ),
        child: NothingIndexed(icon: Icons.collections_bookmark_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nothingIndexed = native.totalEmbeddings == 0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.base,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.selecting
                      ? (controller.selectedIds.isEmpty
                            ? 'Choose collections to export'
                            : '${controller.selectedIds.length} chosen')
                      : nothingIndexed
                      ? 'Collections fill in once something is indexed.'
                      : 'Saved searches that stay up to date as you scan. Long-press one to edit it.',
                  style: controller.selecting
                      ? textTheme.titleMedium
                      : textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                          height: 1.4,
                        ),
                ),
                if (!controller.selecting) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      HeaderActionPill(
                        icon: Icons.add_rounded,
                        label: 'New collection',
                        onTap: () => _createNew(context),
                      ),
                      if (!nothingIndexed && controller.visible.isNotEmpty)
                        HeaderActionPill(
                          icon: Icons.collections_bookmark_outlined,
                          label: 'Select collections',
                          onTap: controller.startSelecting,
                        ),
                    ],
                  ),
                ],
                if (controller.isScoring) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ScoringProgress(controller: controller),
                ],
              ],
            ),
          ),
        ),
        // The featured collection, a different one now and then. Out of the way while choosing.
        if (!controller.selecting && !nothingIndexed)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: CollectionsHero(
                controller: controller,
                native: native,
                onOpen: (c) => openCollectionScreen(context, controller, c),
                onMenu: (c) => showCollectionMenu(context, c, controller),
              ),
            ),
          ),
        if (nothingIndexed) _nothingYet(context) else ..._mosaicSlivers(context),
        if (controller.hiddenCollections.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '${controller.hiddenCollections.length} hidden',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  InkWell(
                    onTap: controller.unhideAll,
                    child: Text(
                      'Restore',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: floatingBarClearance(context)),
        ),
      ],
    );
  }

  void _createNew(BuildContext context) {
    showSaveCollectionSheet(
      context,
      title: 'New collection',
      showQuery: true,
      // Stays on the tab: the new card appears at the top and plays its own
      // "finding matches" animation - opening it straight away would hide that.
      onSave: (name, query, personIds) => controller.createCollection(
        name: name,
        query: query,
        personIds: personIds,
      ),
    );
  }
}

// Shown while collections are being (re)scored. The first pass also has to
// embed every collection's prompts, which is the slow part - that gets a
// real "x of y"; after that it's just a quick refresh.
class _ScoringProgress extends StatelessWidget {
  const _ScoringProgress({required this.controller});

  final CollectionsController controller;

  @override
  Widget build(BuildContext context) {
    final settingUp = controller.setupTotal > 0;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settingUp
                ? 'Getting collections ready  ·  ${controller.setupDone} of ${controller.setupTotal}'
                : 'Updating collections',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            settingUp
                ? 'A one-time setup - it only takes a moment and you can keep using the app.'
                : 'Counting what matches each one.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: settingUp
                  ? controller.setupDone / controller.setupTotal
                  : null,
              backgroundColor: AppColors.hairline,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
