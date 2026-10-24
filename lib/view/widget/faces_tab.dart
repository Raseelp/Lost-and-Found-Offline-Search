import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/view/merge_suggestions_screen.dart';
import 'package:lost_and_found/view/person_screen.dart';
import 'package:lost_and_found/view/widget/app_search_field.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/nothing_indexed.dart';
import 'package:lost_and_found/view/widget/person_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the grid of people is ordered (once there are enough people to want that).
enum _PeopleSort { mostPhotos, namedFirst, az }

/// The Faces tab: the people found in your photos. The face scan runs by
/// itself (no button) - a progress pill shows how far it is, and people appear
/// in the grid as soon as they are found. The header matches the Collections tab: a line of
/// description and a row of small buttons.
class FacesTab extends StatefulWidget {
  const FacesTab({super.key});

  @override
  State<FacesTab> createState() => _FacesTabState();
}

class _FacesTabState extends State<FacesTab> {
  static const _bannerDismissedKey = 'faces_name_banner_dismissed';

  /// Search and sorting appear once there are more people than this.
  static const int _searchFrom = 12;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  _PeopleSort _sort = _PeopleSort.mostPhotos;

  // The "name your people" banner can be closed for good. Treated as closed until the saved
  // choice has been read, so it does not flash up and go away.
  bool _bannerDismissed = true;

  @override
  void initState() {
    super.initState();
    _loadBannerChoice();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadBannerChoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_bannerDismissedKey) ?? false;
      if (mounted) setState(() => _bannerDismissed = dismissed);
    } catch (_) {
      if (mounted) setState(() => _bannerDismissed = false);
    }
  }

  Future<void> _dismissBanner() async {
    setState(() => _bannerDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_bannerDismissedKey, true);
    } catch (_) {
      // Closed for this visit at least.
    }
  }

  // The people to show: the search applied, then the order chosen. (Only once there are enough
  // people to need either; the plain list otherwise.)
  List<Person> _shown(FacesController faces) {
    final all = faces.people;
    if (all.length <= _searchFrom) return all;
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : [
            for (final p in all)
              if ((p.name ?? '').toLowerCase().contains(q)) p,
          ];
    switch (_sort) {
      case _PeopleSort.mostPhotos:
        return list;
      case _PeopleSort.namedFirst:
        return [
          for (final p in list)
            if (p.name != null) p,
          for (final p in list)
            if (p.name == null) p,
        ];
      case _PeopleSort.az:
        final named =
            [
              for (final p in list)
                if (p.name != null) p,
            ]..sort(
              (a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()),
            );
        return [
          ...named,
          for (final p in list)
            if (p.name == null) p,
        ];
    }
  }

  String _sortLabel(_PeopleSort sort) {
    switch (sort) {
      case _PeopleSort.mostPhotos:
        return 'Most photos';
      case _PeopleSort.namedFirst:
        return 'Named first';
      case _PeopleSort.az:
        return 'A to Z';
    }
  }

  void _pickSort(BuildContext context) {
    showFacesSheet<void>(
      context,
      title: 'Sort people',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _PeopleSort.values.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.dividerSoft),
            SheetRow(
              icon: switch (_PeopleSort.values[i]) {
                _PeopleSort.mostPhotos => Icons.photo_library_outlined,
                _PeopleSort.namedFirst => Icons.badge_outlined,
                _PeopleSort.az => Icons.sort_by_alpha_rounded,
              },
              label: _sortLabel(_PeopleSort.values[i]),
              trailing: _sort == _PeopleSort.values[i]
                  ? const Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: AppColors.primary,
                    )
                  : null,
              onTap: () {
                setState(() => _sort = _PeopleSort.values[i]);
                Navigator.of(sheet).pop();
              },
            ),
          ],
        ],
      ),
    );
  }

  // Names the people who have none, one after another, the most photographed first.
  Future<void> _nameThem(FacesController faces) async {
    final queue = [
      for (final p in faces.people)
        if (p.name == null) p,
    ];
    for (var i = 0; i < queue.length; i++) {
      if (!mounted) return;
      final result = await showNamePersonDialog(
        context,
        queue[i],
        position: i + 1,
        total: queue.length,
      );
      if (result == null) return; // closed: that is the end of it
      if (result.skip || result.name == null || result.name!.isEmpty) continue;
      await faces.rename(queue[i], result.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FacesController>(
      builder: (faces) {
        final status = faces.status;
        final textTheme = Theme.of(context).textTheme;
        final noModel = !status.ready || status.error == 'no_model';

        final selecting = faces.selecting;
        // Only people still in the list (one may have been hidden or merged since).
        final chosen = faces.selectedPeople.length;
        final count = faces.people.length;
        final shown = _shown(faces);
        final searchable = count > _searchFrom;
        final unnamed = faces.people.where((p) => p.name == null).length;

        // Faces are found along with indexing, so this is only a quiet way to catch up on
        // anything that was missed. Pressing it turns the button into a small progress pill,
        // and back when the scan is over. Pausing also puts the button back: tapping it
        // carries on from where it stopped.
        final progressPill =
            faces.syncing && !status.userPaused && status.error == null
            ? FaceSyncPill(
                key: const ValueKey('pill'),
                status: status,
                onPause: faces.pauseScan,
              )
            : null;
        final syncArea = noModel
            ? null
            : AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: progressPill == null
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : Padding(
                          key: const ValueKey('padded'),
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: progressPill,
                        ),
                ),
              );

        final scroll = CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selecting) ...[
                      Text(
                        chosen == 0 ? 'Choose people' : '$chosen chosen',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Pick people, then choose below: see the photos they are in together, or export them as a zip.',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                          height: 1.4,
                        ),
                      ),
                      if (syncArea != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: syncArea,
                        ),
                    ] else ...[
                      if (count > 0)
                        Text(
                          '${count == 1 ? '1 person' : '$count people'} found. '
                          'Tap one to open them, long-press for more.',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.ink48,
                            height: 1.4,
                          ),
                        ),
                      if (syncArea != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: syncArea,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (!selecting && unnamed > 0 && !_bannerDismissed)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _NameBanner(
                    unnamed: unnamed,
                    onStart: () => _nameThem(faces),
                    onDismiss: _dismissBanner,
                  ),
                ),
              ),
            if (faces.suggestions.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _SuggestionsBanner(
                    count: faces.suggestions.length,
                    first: faces.suggestions.first,
                  ),
                ),
              ),
            if (searchable)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _SearchRow(
                    controller: _search,
                    sorted: _sort != _PeopleSort.mostPhotos,
                    onChanged: (v) => setState(() => _query = v),
                    onSort: () => _pickSort(context),
                  ),
                ),
              ),
            if (faces.people.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyState(
                  status: status,
                  loading: faces.isLoadingPeople,
                ),
              )
            else if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'No one is called "${_query.trim()}".',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.base,
                  AppSpacing.lg,
                  0,
                ),
                sliver: _PeopleGrid(
                  childCount: shown.length,
                  itemBuilder: (context, i) {
                    final person = shown[i];
                    return PersonTile(
                      key: ValueKey(person.id),
                      person: person,
                      index: i,
                      selecting: selecting,
                      selected: faces.selectedIds.contains(person.id),
                      onTap: selecting
                          ? () => faces.toggleSelected(person)
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PersonScreen(person: person),
                              ),
                            ),
                      onLongPress: selecting
                          ? null
                          : () => showPersonMenu(context, faces, person),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                // The bar is taller while two or more are chosen; otherwise the action button floats above
                // it.
                height: selecting ? floatingBarClearance(context) + 56 : actionFabClearance(context),
              ),
            ),
          ],
        );

        return scroll;
      },
    );
  }
}

/// The people, three across. A tile is as tall as its picture plus the two lines of text under it,
/// so bigger text (a larger font size in the phone's settings) makes the tiles taller instead of
/// overflowing.
class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.childCount, required this.itemBuilder});

  final int childCount;
  final IndexedWidgetBuilder itemBuilder;

  static const double _across = 3;
  static const double _gap = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.crossAxisExtent - _gap * (_across - 1)) / _across;
        // Same as PersonTile: the stack's room, then the name (14 on 20) and the count (12 on 16).
        final room = (cell - 24).clamp(60.0, 112.0);
        final extent = AppSpacing.xs * 2 + (room + 8) + AppSpacing.sm + 1 + 36 * scale + 2;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: _gap,
            mainAxisExtent: extent,
          ),
          delegate: SliverChildBuilderDelegate(itemBuilder, childCount: childCount),
        );
      },
    );
  }
}

/// The search box and the sort button, for a long list of people.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.sorted,
    required this.onChanged,
    required this.onSort,
  });

  final TextEditingController controller;
  final bool sorted;
  final ValueChanged<String> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppSearchField(
            controller: controller,
            hint: 'Search people',
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          tooltip: 'Sort',
          icon: Icon(
            Icons.sort_rounded,
            size: 22,
            color: sorted ? AppColors.primary : AppColors.ink,
          ),
          onPressed: onSort,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.status,
    required this.loading,
  });

  final FaceStatus status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Nothing indexed yet: the same block every screen shows, with the way to the Library.
    if (!loading && Get.find<NativeController>().totalEmbeddings == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxxl,
          AppSpacing.xxl,
          0,
        ),
        child: NothingIndexed(icon: Icons.face_retouching_natural),
      );
    }

    final String message;
    if (loading) {
      message = '';
    } else if (!status.ready) {
      message = '';
    } else if (status.running && status.following) {
      message =
          'Finding people as your photos are indexed. They appear here as soon as the same face turns up in two photos.';
    } else if (status.running) {
      message =
          'Nobody yet. People appear here as soon as the same face turns up in two photos.';
    } else {
      message =
          'No people found yet. A person shows up once their face appears in at least two photos.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxxl,
        AppSpacing.xxl,
        0,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.face_retouching_natural,
            size: 40,
            color: AppColors.ink48,
          ),
          const SizedBox(height: AppSpacing.md),
          if (message.isNotEmpty)
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }
}

/// A nudge to name the people who have no name yet: names are what let Search find a person
/// with an @.
class _NameBanner extends StatelessWidget {
  const _NameBanner({
    required this.unnamed,
    required this.onStart,
    required this.onDismiss,
  });

  final int unnamed;
  final VoidCallback onStart;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onStart,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.base,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
            right: AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.alternate_email_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Name your people to search by them, e.g. @Anna',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unnamed == 1
                            ? '1 person has no name yet'
                            : '$unnamed people have no name yet',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Not now',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.ink48,
                ),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A nudge when some people may be the same person (see MergeSuggestionsScreen), with the
/// faces of the most likely pair so it is clear who it is about.
class _SuggestionsBanner extends StatelessWidget {
  const _SuggestionsBanner({required this.count, required this.first});

  final int count;
  final ({Person a, Person b, double score}) first;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const face = 32.0;
    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MergeSuggestionsScreen())),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            // The two faces, the second overlapping the first.
            SizedBox(
              width: face + 22,
              height: face,
              child: Stack(
                children: [
                  FaceAvatar(faceId: first.a.coverFaceId, size: face),
                  Positioned(
                    left: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.parchment,
                          width: 2,
                        ),
                      ),
                      child: FaceAvatar(
                        faceId: first.b.coverFaceId,
                        size: face,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                count == 1
                    ? '1 pair may be the same person'
                    : '$count pairs may be the same person',
                style: textTheme.bodyMedium,
              ),
            ),
            Text(
              'Review',
              style: textTheme.titleSmall?.copyWith(color: AppColors.primary),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
