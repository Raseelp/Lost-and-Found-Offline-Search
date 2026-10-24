import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/export_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/export_zip_screen.dart';
import 'package:lost_and_found/view/widget/confirm_dialog.dart';
import 'package:lost_and_found/view/widget/mention_input_field.dart';
import 'package:lost_and_found/view/widget/mention_text_controller.dart';

String _countLabel(int count) => count == 1 ? '1 item' : '$count items';

// One collection in the Collections tab's mosaic: its cover photo filling the whole tile, the name and the
// number of items over a dark fade at the bottom, and a "New" tag when something from the latest scan is in
// it. The cover is the collection's photo of the day (see CollectionsController.coverFor), loaded when the
// tile comes on screen and at the size that fits the tile: a small picture first if one is at hand, then a
// sharper one for a big tile. While a collection is being (re)computed its picture breathes; when that ends
// the tile pops once. Pressing it shrinks it a little.
class CollectionCard extends StatefulWidget {
  const CollectionCard({
    super.key,
    required this.collection,
    required this.stats,
    required this.cover,
    required this.coverKey,
    required this.loadCover,
    required this.syncing,
    required this.onTap,
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.isNew = false,
  });

  /// While choosing several collections: every tile shows a tick circle, ticked ones a ring.
  final bool selecting;
  final bool selected;

  /// Something in the collection came in with the latest scan.
  final bool isNew;

  final SmartCollection collection;
  final CollectionStats stats;

  /// The cover picture as far as it is in memory, of whatever size (null: not loaded yet, or the collection
  /// is empty).
  final Uint8List? cover;

  /// Which picture is the cover now (null: none); a new one is loaded when it changes.
  final String? coverKey;

  /// Loads the cover at about this many pixels on the long side (see CollectionsController.loadCover).
  final Future<Uint8List?> Function(int size) loadCover;
  final bool syncing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<CollectionCard> with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  // The cover loaded for this tile, and the size asked for so far (0: nothing yet).
  Uint8List? _loaded;
  int _asked = 0;

  // The sizes a cover is asked for in: few, so the pictures are shared between tiles and chips.
  static const _sizes = [480, 720, 960, 1280, 1600];

  void _want(int needed) {
    if (widget.coverKey == null) return;
    final size = _sizes.firstWhere((s) => s >= needed, orElse: () => _sizes.last);
    if (size <= _asked) return;
    _asked = size;
    final key = widget.coverKey;
    // After this frame: it is asked for while the tile is being laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bytes = await widget.loadCover(size);
      if (!mounted || bytes == null || key != widget.coverKey || identical(bytes, _loaded)) return;
      setState(() => _loaded = bytes);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant CollectionCard old) {
    super.didUpdateWidget(old);
    if (widget.coverKey != old.coverKey) {
      // Another picture is the cover now (the photo of the day changed).
      _loaded = null;
      _asked = 0;
    }
    if (widget.syncing && !old.syncing) {
      _sweep.repeat();
    } else if (!widget.syncing && old.syncing) {
      _sweep.stop();
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pop.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.xl);

    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

    return ScaleTransition(
      scale: scale,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: widget.selecting && widget.selected ? 0.95 : 1,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) => Transform.scale(scale: 1 - 0.03 * _press.value, child: child),
          child: ClipRRect(
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, box) {
                // The big tiles of the mosaic (the tall and the wide ones) get a bigger name.
                final big = box.maxWidth > 260 || box.maxHeight > 300;
                // The picture must fill the tile whichever way round it is, so it is asked for a third larger
                // than the longer side of the tile, in device pixels.
                final needed = (math.max(box.maxWidth, box.maxHeight) * MediaQuery.devicePixelRatioOf(context) * 1.33)
                    .ceil();
                _want(needed);
                final bytes = _loaded ?? widget.cover;

                final text = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.collection.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (big ? textTheme.titleMedium : textTheme.titleSmall)?.copyWith(color: AppColors.onMedia),
                    ),
                    const SizedBox(height: 1),
                    widget.syncing
                        ? Text('Finding matches...', style: textTheme.bodySmall?.copyWith(color: AppColors.onMedia70))
                        : TweenAnimationBuilder<int>(
                            tween: IntTween(begin: 0, end: widget.stats.count),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => Text(
                              _countLabel(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(color: AppColors.onMedia70),
                            ),
                          ),
                  ],
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // The picture, which breathes while the collection is being worked out.
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, child) => Opacity(
                          opacity: widget.syncing ? 0.7 + 0.3 * (0.5 + 0.5 * math.sin(_sweep.value * 2 * math.pi)) : 1,
                          child: child,
                        ),
                        child: bytes != null
                            ? Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                cacheWidth: math.min(needed, _sizes.last),
                                filterQuality: FilterQuality.medium,
                                gaplessPlayback: true,
                              )
                            : ColoredBox(
                                color: AppColors.parchment,
                                child: Center(child: Icon(widget.collection.icon, size: 34, color: AppColors.ink48)),
                              ),
                      ),
                    ),
                    // A dark fade at the bottom, so the name reads on any photo.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.5, 1],
                              colors: [AppColors.scrim.withValues(alpha: 0), AppColors.scrim.withValues(alpha: 0.64)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: 14, right: 14, bottom: 12, child: text),
                    if (widget.isNew)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            'New',
                            style: textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (widget.selecting)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border.all(
                                color: widget.selected ? AppColors.primary : AppColors.transparent,
                                width: 3,
                              ),
                              color: widget.selected
                                  ? AppColors.primary.withValues(alpha: 0.10)
                                  : AppColors.transparent,
                            ),
                          ),
                        ),
                      ),
                    if (widget.selecting)
                      Positioned(
                        top: AppSpacing.sm + 2,
                        right: AppSpacing.sm + 2,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.selected ? AppColors.primary : AppColors.canvas.withValues(alpha: 0.9),
                            border: Border.all(
                              color: widget.selected ? AppColors.primary : AppColors.hairline,
                              width: 1.5,
                            ),
                          ),
                          child: widget.selected
                              ? const Icon(Icons.check_rounded, size: 18, color: AppColors.onPrimary)
                              : null,
                        ),
                      ),
                    // The touch target, above everything else.
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: widget.onTap,
                          onLongPress: widget.onLongPress,
                          onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// The Search tab's quick-access row - a pill with the collection's cover
// photo as a small round avatar (its icon until one exists), its name, and
// how many things are in it.
class CollectionChip extends StatelessWidget {
  const CollectionChip({
    super.key,
    required this.collection,
    required this.count,
    required this.coverBytes,
    required this.onTap,
  });

  final SmartCollection collection;
  final int count;
  final Uint8List? coverBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs + 2,
            AppSpacing.xs + 2,
            AppSpacing.md,
            AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChipAvatar(bytes: coverBytes, icon: collection.icon),
              const SizedBox(width: AppSpacing.sm),
              Text(
                collection.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name (+ the phrase to search, when it isn't already known) for a new or
/// edited collection. [onSave] gets the finished values - [query] already
/// has any "@name" mentions stripped out (same as search's own
/// queryWithoutMention), with those names broken out separately into
/// [onSave]'s third argument.
Future<void> showSaveCollectionSheet(
  BuildContext context, {
  String? title,
  String initialName = '',
  String? initialQuery,
  bool showQuery = false,
  required Future<void> Function(String name, String query, List<int> personIds) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _SaveCollectionSheet(
      title: title ?? 'Save as collection',
      initialName: initialName,
      initialQuery: initialQuery,
      showQuery: showQuery,
      onSave: onSave,
    ),
  );
}

class _SaveCollectionSheet extends StatefulWidget {
  const _SaveCollectionSheet({
    required this.title,
    required this.initialName,
    required this.initialQuery,
    required this.showQuery,
    required this.onSave,
  });

  final String title;
  final String initialName;
  final String? initialQuery;
  final bool showQuery;
  final Future<void> Function(String name, String query, List<int> personIds) onSave;

  @override
  State<_SaveCollectionSheet> createState() => _SaveCollectionSheetState();
}

class _SaveCollectionSheetState extends State<_SaveCollectionSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  // Same "@name" recognition the search box uses - lets a collection made
  // from the Collections page (not just one saved from an existing search)
  // filter by person too. peopleProvider mirrors NativeController's own
  // construction of its searchTextController.
  late final MentionTextEditingController _query = MentionTextEditingController(
    peopleProvider: () =>
        Get.isRegistered<FacesController>() ? Get.find<FacesController>().people : const [],
  )..text = widget.initialQuery ?? '';

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  bool get _canSave =>
      widget.showQuery ? _query.text.trim().isNotEmpty : _name.text.trim().isNotEmpty;

  // Closes right away and does the work behind it - the new card appears in
  // the list and plays its own "finding matches" animation, so there's
  // nothing to wait on here.
  void _save() {
    final query = widget.showQuery ? _query.queryWithoutMention : (widget.initialQuery ?? '');
    final personIds = widget.showQuery
        ? _query.recognizedPeople.map((p) => p.id).toList()
        : const <int>[];
    final name = _name.text.trim();
    final onSave = widget.onSave;
    Navigator.of(context).pop();
    unawaited(onSave(name, query, personIds));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.base,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: SafeArea(
          top: false,
          // A tall keyboard (or a long "@name and @name2..." query) can
          // otherwise push this sheet's own content taller than the space
          // actually left above it - scrollable rather than clipped/
          // overflowing keeps the Save button reachable either way.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(widget.title, style: textTheme.titleMedium),
              if (!widget.showQuery &&
                  (widget.initialQuery ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Finds: ${widget.initialQuery}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              if (widget.showQuery) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: MentionInputField(
                    controller: _query,
                    autofocus: widget.initialQuery == null,
                    onChanged: () => setState(() {}),
                    style: textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'What to look for, e.g. "dog" or "@name at the beach"',
                      hintStyle: const TextStyle(color: AppColors.ink48),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _Field(
                controller: _name,
                hint: widget.showQuery
                    ? 'Name (optional), e.g. "Mittu"'
                    : 'Name, e.g. "Mittu"',
                autofocus: !widget.showQuery,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: _canSave ? AppColors.primary : AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    onTap: _canSave ? _save : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Center(
                        child: Text(
                          'Save',
                          style: textTheme.titleSmall?.copyWith(
                            color: _canSave
                                ? AppColors.onPrimary
                                : AppColors.ink48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: (_) => onChanged(),
        textCapitalization: TextCapitalization.sentences,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.ink48),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    );
  }
}

/// Long-press menu for a collection card. Every collection can be edited,
/// hidden or deleted; a built-in that's been edited can also be reset.
void showCollectionMenu(
  BuildContext context,
  SmartCollection collection,
  CollectionsController controller,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
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
                child: Text(collection.name, style: Theme.of(context).textTheme.titleSmall),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              _MenuRow(
                icon: Icons.edit_outlined,
                label: 'Rename or change',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showEditCollectionSheet(context, collection, controller);
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.folder_zip_outlined,
                label: 'Export as zip',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openExportZip(context, select: {ExportController.collectionKey(collection.id)});
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.visibility_off_outlined,
                label: 'Hide',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.hideCollection(collection.id);
                },
              ),
              if (collection.isBuiltIn && controller.isEdited(collection.id)) ...[
                const Divider(height: 1, color: AppColors.dividerSoft),
                _MenuRow(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset to default',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.resetBuiltIn(collection.id);
                  },
                ),
              ],
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showConfirmDialog(
                    context,
                    title: 'Delete this collection?',
                    message: collection.isBuiltIn
                        ? 'It comes off your list. You can bring it back any time from Settings, under "Restore default collections".'
                        : 'Only the collection goes - your photos and videos are untouched.',
                    confirmLabel: 'Delete',
                    onConfirm: () => controller.deleteCollection(collection.id),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Long-press menu for the "On this day" card: it is not a saved search, so there is nothing to
/// rename or change - it can be exported, or taken off the tab (and brought back from there).
/// [onHidden] runs after it is hidden (the memories screen closes itself).
void showOnThisDayMenu(
  BuildContext context,
  MemoriesController memories, {
  VoidCallback? onHidden,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (sheetContext) => SafeArea(
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
                  'On this day  ·  ${memories.today.dateLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              _MenuRow(
                icon: Icons.folder_zip_outlined,
                label: 'Export as zip',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openExportZip(
                    context,
                    select: {ExportController.memoryKey},
                  );
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.visibility_off_outlined,
                label: 'Hide',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  memories.setHidden(true);
                  onHidden?.call();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showEditCollectionSheet(
  BuildContext context,
  SmartCollection collection,
  CollectionsController controller,
) {
  // A photo collection has no phrase to edit - just its name.
  if (collection.isPhotos) {
    return showSaveCollectionSheet(
      context,
      title: 'Rename collection',
      initialName: collection.name,
      initialQuery: 'photos that look like the one you saved',
      onSave: (name, _, __) => controller.updateCollection(
        collection.copyWith(name: name.isEmpty ? collection.name : name),
      ),
    );
  }

  // Shows the short phrase (a built-in's several prompts are an
  // implementation detail); leaving it alone keeps the built-in's own. Any
  // already-mentioned people are put back in front of it, the same way
  // search's own lastQueryWithMentions does - so the field's own name
  // recognition picks them up again as soon as it opens, rather than
  // silently starting from a collection that looks like it has no person
  // filter at all.
  final currentQuery = collection.queryText;
  final currentPersonNames = collection.personIds.isEmpty || !Get.isRegistered<FacesController>()
      ? const <String>[]
      : Get.find<FacesController>().people
          .where((p) => collection.personIds.contains(p.id))
          .map((p) => p.name)
          .whereType<String>()
          .toList();
  final initialQueryWithMentions = currentPersonNames.isEmpty
      ? currentQuery
      : '${currentPersonNames.join(' and ')} $currentQuery';

  return showSaveCollectionSheet(
    context,
    title: 'Edit collection',
    initialName: collection.name,
    initialQuery: initialQueryWithMentions,
    showQuery: true,
    onSave: (name, query, personIds) => controller.updateCollection(
      collection.copyWith(
        name: name.isEmpty ? query : name,
        prompts: query == currentQuery ? null : [query],
        personIds: personIds,
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipAvatar extends StatelessWidget {
  const _ChipAvatar({required this.bytes, required this.icon});

  final Uint8List? bytes;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 24,
        height: 24,
        child: bytes == null
            ? ColoredBox(
                color: AppColors.hairline,
                child: Icon(icon, size: 14, color: AppColors.ink48),
              )
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: 72,
                cacheHeight: 72,
              ),
      ),
    );
  }
}
