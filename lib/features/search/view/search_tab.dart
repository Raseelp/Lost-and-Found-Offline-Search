import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/widgets/app_search_field.dart';
import 'package:lost_and_found/features/library/view/widgets/nothing_indexed.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/collections/view/widgets/collection_widgets.dart';
import 'package:lost_and_found/features/memories/features/stories/view/widgets/story_rings.dart';
import 'package:lost_and_found/features/collections/view/collections_tab.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/floating_bar.dart';
import 'package:lost_and_found/features/search/view/widgets/auto_indexed_card.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_input_field.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/features/search/view/widgets/search_filter_sheet.dart';
import 'package:lost_and_found/features/search/view/widgets/search_results.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/search/controllers/search_controller.dart';

/// The Search tab: the search bar, the story rings, the card about what was indexed by itself, and the results.
///
/// It is one CustomScrollView and not a SingleChildScrollView with a Column, because the results grid must be a real
/// sliver in the one scrollable to be virtualized (see [searchResultsSlivers]). Everything above it rides along as a
/// plain boxed sliver. The rings are one bar that is large before a search, shrinks into a strip above the results and
/// grows back when "Stories" is tapped.
class SearchTab extends StatelessWidget {
  const SearchTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AppSearchController>(
      builder: (controller) => GetBuilder<LibraryController>(
        builder: (library) => _content(context, controller, library),
      ),
    );
  }

  Widget _content(BuildContext context, AppSearchController controller, LibraryController library) {
    final showResults =
        controller.isSearching ||
        controller.searchResults.isNotEmpty ||
        controller.error.isNotEmpty;

    return CustomScrollView(
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SearchPill(controller: controller),
                if (library.isScanning) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _BackgroundIndexingNote(library: library),
                ] else if (showResults)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: StoryRingsBar(controller: controller, compact: showResults),
          ),
        ),
        if (library.autoIndexed.count > 0 && library.totalEmbeddings > 0)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.base, AppSpacing.xl, showResults ? AppSpacing.base : 0),
            sliver: SliverToBoxAdapter(child: AutoIndexedCard(batch: library.autoIndexed)),
          ),
        if (showResults)
          ...searchResultsSlivers(search: controller, library: library)
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            sliver: SliverToBoxAdapter(child: _SearchIdlePrompt(library: library)),
          ),
        SliverToBoxAdapter(child: SizedBox(height: floatingBarClearance(context))),
      ],
    );
  }
}

/// The search bar, with two input modes: typed text, or an attached photo for a reverse-image search.
/// Picking a photo only attaches it, shown as a chip, and nothing runs until Search is pressed, just as with typed
/// text. The text mode also recognises a named person, typed plainly or picked from an "@" dropdown (see
/// [MentionTextEditingController]). This widget owns the dropdown overlay, anchored to the bar through a LayerLink so
/// it follows the bar when the page scrolls.
class _SearchPill extends StatefulWidget {
  const _SearchPill({required this.controller});

  final AppSearchController controller;

  @override
  State<_SearchPill> createState() => _SearchPillState();
}

/// The gap between the rounded ends of the bar and the switch or arrow button inside them. It is about what is left
/// above and below them, so they sit evenly in the ends.
const double _endGap = 5;

/// The size of the switch and of the arrow button. It is the same for both, so both sit in the ends alike.
const double _endButton = 38;

class _SearchPillState extends State<_SearchPill> {
  final LayerLink _mentionLink = LayerLink();
  OverlayEntry? _mentionEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.searchTextController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.searchTextController.removeListener(_onTextChanged);
    _removeMentionOverlay();
    super.dispose();
  }

  /// Shows the "@" list while a name is being typed, and not in photo mode, where the text box is not there. A
  /// half-typed "@ra" is kept for when the box is back. The list listens to the same controller itself and filters on
  /// every keystroke, so an entry that is already inserted needs no rebuild.
  void _onTextChanged() {
    final c = widget.controller;
    final photoMode = c.searchPhotoMode || c.pickedSearchImageUri != null;
    if (photoMode || c.searchTextController.activeMentionQuery == null) {
      _removeMentionOverlay();
    } else if (_mentionEntry == null) {
      _mentionEntry = OverlayEntry(
        builder: (_) => MentionDropdown(
          link: _mentionLink,
          controller: widget.controller.searchTextController,
          focusNode: widget.controller.searchFocusNode,
        ),
      );
      Overlay.of(context).insert(_mentionEntry!);
    }
  }

  void _removeMentionOverlay() {
    final entry = _mentionEntry;
    if (entry == null) return;
    _mentionEntry = null;
    entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final hasImage = controller.pickedSearchImageUri != null;
    final photoMode = controller.searchPhotoMode || hasImage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onTextChanged();
    });

    return CompositedTransformTarget(
      link: _mentionLink,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: _endGap,
          vertical: AppSpacing.xxs,
        ),
        decoration: AppSearchBox.decoration(),
        child: Row(
          children: [
            _ModeSwitch(
              photoMode: photoMode,
              onChanged: controller.setSearchPhotoMode,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: photoMode
                  ? (hasImage
                        ? _AttachedImageChip(controller: controller)
                        : _PhotoPrompt(onTap: controller.pickSearchImage))
                  : Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        _RotatingHint(
                          controller: controller.searchTextController,
                        ),
                        TextField(
                          controller: controller.searchTextController,
                          focusNode: controller.searchFocusNode,
                          onTapOutside: (_) =>
                              controller.searchFocusNode.unfocus(),
                          onSubmitted: (_) => controller.runSearch(),
                          textInputAction: TextInputAction.search,
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: AppSearchBox.fieldPadding,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _FilterButton(controller: controller),
            _SaveCollectionButton(controller: controller),
            const SizedBox(width: AppSpacing.sm),
            _SearchSubmitButton(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Two small round choices at the left of the bar: describe what you are after, or search with a photo. The one in use
/// is filled.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.photoMode, required this.onChanged});

  final bool photoMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget choice({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? AppColors.onPrimary : AppColors.ink48,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          choice(
            icon: Icons.search_rounded,
            label: 'Describe',
            selected: !photoMode,
            onTap: () => onChanged(false),
          ),
          choice(
            icon: Icons.image_search_rounded,
            label: 'Search with a photo',
            selected: photoMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

/// In photo mode with no photo yet, the whole middle of the bar is the way to pick one, and it says what a photo does.
class _PhotoPrompt extends StatelessWidget {
  const _PhotoPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'Find similar moments instead of describing one',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.ink80,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

/// Cycles through a few example queries while the box is empty.
///
/// It teaches what the search can do without a tooltip or a dialog, and one of the examples is the "@name at the
/// beach" syntax itself. It sits behind the field and shows through it while the field is empty. A real hintText cannot
/// crossfade between examples on its own. The real field draws over it as soon as there is text, so it then only
/// needs to stop claiming the space.
class _RotatingHint extends StatefulWidget {
  const _RotatingHint({required this.controller});

  final MentionTextEditingController controller;

  @override
  State<_RotatingHint> createState() => _RotatingHintState();
}

class _RotatingHintState extends State<_RotatingHint> {
  static const _examples = [
    'Search your photos and videos',
    'Try "sunset over the hills"',
    'Try "@name at the beach"',
    'Try "birthday cake"',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _syncTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onTextChanged() => _syncTimer();

  /// Runs the timer only while the hint is visible, so it does not call setState every 3 seconds for as long as the
  /// search tab exists.
  void _syncTimer() {
    final shouldRun = widget.controller.text.isEmpty;
    if (shouldRun == (_timer != null)) return;
    if (shouldRun) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() => _index = (_index + 1) % _examples.length);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.text.isNotEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _examples[_index],
              key: ValueKey(_index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink48),
            ),
          ),
        );
      },
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.controller});

  final AppSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: () => showSearchFilterSheet(context, controller),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: const Icon(
            Icons.tune_rounded,
            size: 19,
            color: AppColors.ink80,
          ),
        ),
      ),
    );
  }
}

class _AttachedImageChip extends StatelessWidget {
  const _AttachedImageChip({required this.controller});

  final AppSearchController controller;

  @override
  Widget build(BuildContext context) {
    final bytes = controller.pickedSearchImageBytes;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            width: 32,
            height: 32,
            child: bytes == null
                ? const ColoredBox(color: AppColors.hairline)
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 64,
                    cacheHeight: 64,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Matching this photo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.ink80),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: controller.clearPickedSearchImage,
          child: const Padding(
            padding: EdgeInsets.all(AppSpacing.xs),
            child: Icon(Icons.close_rounded, size: 17, color: AppColors.ink48),
          ),
        ),
      ],
    );
  }
}

/// The button that submits the search. It listens to the text field itself and not only to GetX, because typing does
/// not call update() and the enabled state would then refresh only when something unrelated rebuilds the screen. In
/// photo mode it is the photo that counts, and not any text typed earlier.
class _SearchSubmitButton extends StatelessWidget {
  const _SearchSubmitButton({required this.controller});

  final AppSearchController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.searchTextController,
      builder: (context, _) {
        final hasImage = controller.pickedSearchImageUri != null;
        final enabled = (controller.searchPhotoMode || hasImage)
            ? hasImage
            : controller.searchTextController.text.trim().isNotEmpty;

        return Material(
          color: AppColors.transparent,
          child: InkWell(
            onTap: enabled ? controller.runSearch : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              width: _endButton,
              height: _endButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? AppColors.primary : AppColors.hairline,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: enabled ? AppColors.onPrimary : AppColors.ink48,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A note that indexing runs in the background. Tapping it opens the Library, where the progress is.
class _BackgroundIndexingNote extends StatelessWidget {
  const _BackgroundIndexingNote({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => goToLibrary(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Indexing continues in the background - ${library.totalEmbeddings} indexed so far.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.ink48,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the tab shows before a search. With nothing indexed yet it shows example searches and the way to the Library
/// (see [NothingIndexed]).
class _SearchIdlePrompt extends StatelessWidget {
  const _SearchIdlePrompt({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    if (library.totalEmbeddings == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: NothingIndexed(place: NothingIndexedPlace.search),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Describe a photo, place, or moment',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lost & Found searches by meaning, not filenames.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Saves the search as a collection. A mention such as "@Raseel" with no other words leaves the text query empty and
/// is still a search that can be saved, described entirely by who is in it.
class _SaveCollectionButton extends StatelessWidget {
  const _SaveCollectionButton({required this.controller});

  final AppSearchController controller;

  @override
  Widget build(BuildContext context) {
    final query = controller.lastTextQuery;
    final isImageSearch = controller.lastImageSeedUri != null;
    final hasTextSearch = (query != null && query.isNotEmpty) ||
        controller.lastMentionedPersonIds.isNotEmpty;
    if ((!hasTextSearch && !isImageSearch) ||
        controller.searchResults.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: () => isImageSearch
            ? _saveImageSearch(context)
            : _save(context, controller.lastQueryWithMentions),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: const Icon(
            Icons.bookmark_add_outlined,
            size: 19,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  /// Saves an image search (a picked photo, "search with this image" or a video frame) as a photo-seeded collection of
  /// whatever looks like that photo.
  void _saveImageSearch(BuildContext context) {
    final collections = Get.find<CollectionsController>();

    showSaveCollectionSheet(
      context,
      initialName: 'Similar photos',
      initialQuery: 'photos that look like this one',
      onSave: (name, _, __) async {
        final created = await collections.saveImageSearchAsCollection(
          name: name,
        );
        if (created == null) {
          AppToast.show("Couldn't save that collection.");
          return;
        }
        AppToast.show(
          'Saved ${created.name} as a collection.',
          actionLabel: 'View',
          onAction: () {
            if (context.mounted) openCollectionScreen(context, collections, created);
          },
        );
      },
    );
  }

  void _save(BuildContext context, String query) {
    final collections = Get.find<CollectionsController>();

    showSaveCollectionSheet(
      context,
      initialName: query,
      initialQuery: query,
      onSave: (name, _, __) async {
        final created = await collections.saveSearchAsCollection(
          name: name,
          personIds: controller.lastMentionedPersonIds,
        );
        if (created == null) return;
        AppToast.show(
          'Saved ${created.name} as a collection.',
          actionLabel: 'View',
          onAction: () {
            if (context.mounted) openCollectionScreen(context, collections, created);
          },
        );
      },
    );
  }
}
