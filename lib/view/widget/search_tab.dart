import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/view/widget/app_search_field.dart';
import 'package:lost_and_found/view/widget/nothing_indexed.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/view/widget/collection_widgets.dart';
import 'package:lost_and_found/view/widget/story_rings.dart';
import 'package:lost_and_found/view/widget/collections_tab.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/view/widget/mention_input_field.dart';
import 'package:lost_and_found/view/widget/mention_text_controller.dart';
import 'package:lost_and_found/view/widget/search_filter_sheet.dart';
import 'package:lost_and_found/view/widget/search_results.dart';

class SearchTab extends StatelessWidget {
  const SearchTab({super.key, required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final showResults =
        controller.isSearching ||
        controller.searchResults.isNotEmpty ||
        controller.error.isNotEmpty;

    // CustomScrollView, not SingleChildScrollView(child: Column(...)) -
    // the results grid needs to be a real sliver participating in this
    // one true scrollable to actually virtualize (see searchResultsSlivers'
    // doc); everything above it just rides along as a plain boxed sliver.
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
                const SizedBox(height: AppSpacing.lg),
                if (controller.isScanning)
                  _BackgroundIndexingNote(controller: controller),
              ],
            ),
          ),
        ),
        // The rings are one bar that is large before a search and shrinks into a strip above the
        // results (and grows back when "Stories" is tapped).
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: StoryRingsBar(controller: controller, compact: showResults),
          ),
        ),
        if (showResults)
          ...searchResultsSlivers(controller: controller)
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            sliver: SliverToBoxAdapter(child: _SearchIdlePrompt(controller: controller)),
          ),
        SliverToBoxAdapter(child: SizedBox(height: floatingBarClearance(context))),
      ],
    );
  }
}

// The search bar has two input modes - typed text, or an attached photo for
// a reverse-image search - and one explicit way to submit either. Picking a
// photo only attaches it (shown as a chip, same idea as an attachment
// preview above a chat message) - nothing runs until Search is pressed,
// exactly like typing text doesn't search until then either.
//
// The text mode also recognises one named person inside it - typed plainly, or picked from an
// "@" dropdown - see MentionTextEditingController. This widget owns the dropdown's overlay
// (anchored to the pill itself via a LayerLink, so it tracks it regardless of scrolling).
class _SearchPill extends StatefulWidget {
  const _SearchPill({required this.controller});

  final NativeController controller;

  @override
  State<_SearchPill> createState() => _SearchPillState();
}

// The gap between the bar's rounded ends and the switch / arrow button inside them (about what is
// left above and below them, so they sit evenly in the ends).
const double _endGap = 5;

// The size of the switch and of the arrow button: the same, so both sit in the ends alike.
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

  // The "@" list shows while a name is being typed - not in photo mode, where the text box is
  // not there (a half-typed "@ra" is kept for when it is back).
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
    // No explicit rebuild of an already-inserted entry needed: _MentionDropdown listens to the
    // same controller itself and refilters on every keystroke on its own.
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
    // A photo that is attached counts as photo mode.
    final photoMode = controller.searchPhotoMode || hasImage;
    // A change of mode puts the "@" list away, or brings it back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onTextChanged();
    });

    return CompositedTransformTarget(
      link: _mentionLink,
      child: Container(
        // The two ends of the bar are its own round ends: the switch and the arrow button sit
        // snug in them, the same gap on every side, instead of a wide margin at the sides.
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
                        // Behind the field, only visible through it while it's empty - a real
                        // hintText can't crossfade between examples on its own, and one of those
                        // examples is the whole point: showing "@name at the beach" is how someone
                        // discovers this exists at all, without a tooltip or a dialog for it.
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

// Two small round choices at the left of the bar: describe what you are after, or search with a
// photo. The one in use is filled.
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

// In photo mode with no photo yet: the whole middle of the bar is the way to pick one, and
// says what a photo does.
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

/// Cycles through a few example queries while the box is empty - the search bar's own quiet
/// way of teaching what's possible, one of them being the "@name at the beach" syntax itself.
/// No tooltip, no dialog, no badge to dismiss - just something true sitting where a hint
/// normally would, that happens to change every few seconds.
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

  // Only ticks while the hint is actually visible - without this, it kept cycling (and calling
  // setState every 3s) for as long as the search tab existed, whether or not there was
  // anything typed for it to matter to.
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
        // The real field draws right over this the moment there's anything typed - nothing
        // needs to fade out for that, it just needs to not still be claiming this space.
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

  final NativeController controller;

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

  final NativeController controller;

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

// A live listener on the text field, not just a GetX rebuild - typing
// doesn't call update(), so without this the button's enabled state would
// only refresh whenever something unrelated happened to rebuild the screen.
class _SearchSubmitButton extends StatelessWidget {
  const _SearchSubmitButton({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.searchTextController,
      builder: (context, _) {
        final hasImage = controller.pickedSearchImageUri != null;
        // In photo mode it is the photo that counts, not any text typed earlier.
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

class _BackgroundIndexingNote extends StatelessWidget {
  const _BackgroundIndexingNote({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    // Tapping it opens the Library, where the progress is.
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
                  'Indexing continues in the background - ${controller.totalEmbeddings} indexed so far.',
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

class _SearchIdlePrompt extends StatelessWidget {
  const _SearchIdlePrompt({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    // Nothing to search yet: the same block every screen shows, with the way to the Library.
    if (controller.totalEmbeddings == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: NothingIndexed(icon: Icons.search_rounded),
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

class _SaveCollectionButton extends StatelessWidget {
  const _SaveCollectionButton({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    final query = controller.lastTextQuery;
    final isImageSearch = controller.lastImageSeedUri != null;
    // A pure "@Raseel" mention with no other words strips down to an empty
    // lastTextQuery - still a real, saveable search, just one described
    // entirely by who's in it rather than by any text.
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

  // An image search (a picked photo, "search with this image", a video frame)
  // saves as a photo-seeded collection: whatever looks like that photo.
  void _saveImageSearch(BuildContext context) {
    final collections = Get.find<CollectionsController>();
    final messenger = ScaffoldMessenger.of(context);

    showSaveCollectionSheet(
      context,
      initialName: 'Similar photos',
      initialQuery: 'photos that look like this one',
      onSave: (name, _, __) async {
        final created = await collections.saveImageSearchAsCollection(
          name: name,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              created == null
                  ? "Couldn't save that collection"
                  : 'Saved · ${created.name}',
            ),
            action: created == null
                ? null
                : SnackBarAction(
                    label: 'View',
                    onPressed: () {
                      if (context.mounted) {
                        openCollectionScreen(context, collections, created);
                        }
                    },
                  ),
          ),
        );
      },
    );
  }

  void _save(BuildContext context, String query) {
    final collections = Get.find<CollectionsController>();
    final messenger = ScaffoldMessenger.of(context);

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
        messenger.showSnackBar(
          SnackBar(
            content: Text('Saved · ${created.name}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                if (context.mounted) {
                  openCollectionScreen(context, collections, created);
                  }
              },
            ),
          ),
        );
      },
    );
  }
}
