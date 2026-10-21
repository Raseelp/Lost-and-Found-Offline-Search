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

int _idHash(String id) => id.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);

// One collection in the Collections tab's mosaic: a stack of its best photos, with no box
// around it - just a soft light in the main colour of the top photo behind it, and the same
// colour in the shadow under it. Each photo is tilted its own way (the tilt comes from the
// collection's id, so every stack leans differently and always the same). The stack fans out
// when the tile first shows, straightens a little when pressed, and the cover on top rotates
// through the collection's best matches (see CollectionsController.stackCovers). While a
// collection is being (re)computed its light breathes.
class CollectionCard extends StatefulWidget {
  const CollectionCard({
    super.key,
    required this.collection,
    required this.stats,
    required this.stack,
    required this.syncing,
    required this.onTap,
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.isNew = false,
    this.index = 0,
    this.glow,
  });

  /// The colour of the light behind the stack (taken from the top photo); a colour of the
  /// collection's own until that is known.
  final Color? glow;

  /// While choosing several collections: every tile shows a tick circle, ticked ones a ring.
  final bool selecting;
  final bool selected;

  /// Some of the photos on the stack came in with the latest scan.
  final bool isNew;

  /// Where the tile is in the mosaic: the fan-out of the stacks starts one after another.
  final int index;

  final SmartCollection collection;
  final CollectionStats stats;

  /// The picture on top, then the two behind it (null: not arrived yet).
  final List<Uint8List?> stack;
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
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _sweep.repeat();
    // The first screenful opens one after another, in the order it is laid out; a tile that
    // scrolls in later just opens.
    final delay = Duration(milliseconds: widget.index < 8 ? widget.index * 60 : 0);
    Future<void>.delayed(delay, () {
      if (mounted) _fan.forward();
    });
  }

  @override
  void didUpdateWidget(covariant CollectionCard old) {
    super.didUpdateWidget(old);
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
    _fan.dispose();
    _press.dispose();
    super.dispose();
  }

  // One photo of the stack: a white-bordered print with a soft shadow.
  Widget _print(Uint8List? bytes, {required bool top, required Color glow}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          // The top photo throws a coloured shadow; the ones behind a plain soft one.
          top
              ? BoxShadow(color: glow.withValues(alpha: 0.5), blurRadius: 26, spreadRadius: -6, offset: const Offset(0, 18))
              : BoxShadow(color: AppColors.shadow.withValues(alpha: 0.13), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true)
              : ColoredBox(
                  color: AppColors.parchment,
                  child: top ? Center(child: Icon(widget.collection.icon, size: 30, color: AppColors.ink48)) : null,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final id = widget.collection.id;
    final h = _idHash(id);
    // Until the top photo's colour is known, a colour of the collection's own.
    final glow = widget.glow ?? HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.55).toColor();

    // The lean of the top photo is from -6.6 to 6.6 degrees, never flat; the two behind lean
    // the other way and the same way, a different amount each, and peek out to the sides.
    final steps = (h % 7) - 3;
    var lean = steps * 2.2;
    if (lean.abs() < 2.2) lean = h.isEven ? 3.0 : -3.0;
    final dir = lean < 0 ? 1.0 : -1.0;
    final angles = [lean, lean + dir * (8 + (h >> 3) % 5), lean - dir * (5 + (h >> 5) % 4)];
    final shifts = [Offset.zero, Offset(dir * 9, -3), Offset(-dir * 7, -5)];

    final stack = widget.stack;

    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

    return ScaleTransition(
      scale: scale,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: widget.selecting && widget.selected ? 0.95 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final height = box.maxHeight;
                final wide = w > height * 1.6;
                const pad = 14.0;
                final area = wide
                    ? Rect.fromLTWH(w * 0.46, pad, w * 0.48, height - 2 * pad)
                    : Rect.fromLTWH(pad + 4, pad, w - 2 * (pad + 4), height - pad - 52);
                final card = area.deflate(wide ? 8 : 12);

                final text = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.collection.name,
                      maxLines: wide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: (wide ? textTheme.titleMedium : textTheme.titleSmall)?.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 1),
                    widget.syncing
                        ? Text('Finding matches...', style: textTheme.bodySmall?.copyWith(color: AppColors.ink48))
                        : TweenAnimationBuilder<int>(
                            tween: IntTween(begin: 0, end: widget.stats.count),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isNew) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.isNew ? 'New  ·  ${_countLabel(value)}' : _countLabel(value),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ],
                );

                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    // The light behind the stack: a soft ellipse in the colour of the top photo, strongest
                    // in the middle and gone at its edge (a round gradient stretched to the stack's shape).
                    Positioned.fromRect(
                      rect: card.inflate(wide ? 26 : 32),
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _sweep,
                          builder: (context, _) {
                            // Breathes while the collection is being worked out.
                            final strength = widget.syncing
                                ? 0.3 + 0.3 * (0.5 + 0.5 * math.sin(_sweep.value * 2 * math.pi))
                                : 0.5;
                            return FittedBox(
                              fit: BoxFit.fill,
                              child: SizedBox.square(
                                dimension: 100,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      radius: 0.5,
                                      colors: [glow.withValues(alpha: strength), glow.withValues(alpha: 0)],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Furthest back first.
                    for (final layer in const [2, 1, 0])
                      Positioned.fromRect(
                        rect: card,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_fan, _press]),
                          builder: (context, child) {
                            final open = Curves.easeOutBack.transform(_fan.value) * (1 - 0.65 * _press.value);
                            return Transform.translate(
                              offset: shifts[layer] * open,
                              child: Transform.rotate(angle: angles[layer] * math.pi / 180 * open, child: child),
                            );
                          },
                          child: _print(layer < stack.length ? stack[layer] : null, top: layer == 0, glow: glow),
                        ),
                      ),
                    if (widget.selecting)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.xl),
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
                    wide
                        ? Positioned(left: 16, top: 0, bottom: 0, width: w * 0.40, child: Center(child: text))
                        : Positioned(left: 14, right: 14, bottom: 12, child: text),
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
