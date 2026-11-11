part of '../export_zip_screen.dart';

class _BuilderView extends StatelessWidget {
  const _BuilderView({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final collections = c.shownCollections, people = c.shownPeople;
    final rows = <Object>[
      if (collections.isNotEmpty) 'Collections',
      ...collections,
      if (people.isNotEmpty) 'People',
      ...people,
    ];
    final nothingAtAll = c.collections.isEmpty && c.people.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text('Export as zip', style: textTheme.titleLarge),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.base,
                ),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Put albums in a zip to keep, send, or move to another device. Your photos and videos stay where they are: the zip is a copy.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              if (!nothingAtAll)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SearchHeader(
                    query: c.query,
                    chosen: c.selected.length,
                    onChanged: c.setQuery,
                  ),
                ),
              if (rows.isEmpty && nothingAtAll && _nothingIndexed())
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    AppSpacing.xxxl,
                    AppSpacing.xxl,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: NothingIndexed(place: NothingIndexedPlace.export),
                  ),
                )
              else if (rows.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      nothingAtAll
                          ? 'There is nothing to export yet. Collections and people appear once something is indexed.'
                          : 'No collection or person is called "${c.query.trim()}".',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      final heading = Text(
                        row.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.ink48,
                          letterSpacing: .5,
                        ),
                      );
                      final group = row == 'Collections' ? collections : people;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.xs,
                          AppSpacing.md,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: heading),
                            TextButton(
                              onPressed: () => c.toggleAll(group),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                c.allChosen(group) ? 'Clear all' : 'Select all',
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final album = row as ExportAlbum;
                    return _AlbumRow(
                      album: album,
                      selected: c.selected.contains(album.key),
                      onTap: () => c.toggle(album),
                    );
                  },
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.base),
              ),
            ],
          ),
        ),
        _SummaryBar(c: c, settings: false),
      ],
    );
  }
}

/// Whether nothing has been indexed, so there is nothing to export.
bool _nothingIndexed() =>
    !Get.isRegistered<NativeController>() ||
    Get.find<NativeController>().totalEmbeddings == 0;

/// The search box, pinned above the list so it stays in reach while scrolling.
class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({
    required this.query,
    required this.chosen,
    required this.onChanged,
  });

  final String query;
  final int chosen;
  final ValueChanged<String> onChanged;

  static const double _height = 72;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.canvas,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: _SearchField(initial: query, chosen: chosen, onChanged: onChanged),
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) =>
      old.query != query || old.chosen != chosen;
}
