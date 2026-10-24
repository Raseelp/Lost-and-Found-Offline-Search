import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/confirm_dialog.dart';

/// A face picture, cut from its photo on demand (see FacesController.crop).
/// Round for avatars, or a rounded square for the review grid.
class FaceAvatar extends StatefulWidget {
  const FaceAvatar({
    super.key,
    required this.faceId,
    required this.size,
    this.square = false,
    this.radius,
  });

  final int faceId;
  final double size;
  final bool square;

  /// Corner radius of a square avatar (a small one by default).
  final double? radius;

  @override
  State<FaceAvatar> createState() => _FaceAvatarState();
}

class _FaceAvatarState extends State<FaceAvatar> {
  final FacesController _controller = Get.find<FacesController>();
  Uint8List? _bytes;
  // The face this widget has asked the controller for and not yet been given.
  int? _holding;

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    final held = _holding;
    if (held != null) {
      _controller.releaseCrop(held);
      _holding = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FaceAvatar old) {
    super.didUpdateWidget(old);
    if (old.faceId != widget.faceId) _load();
  }

  void _load() {
    _release();
    final id = widget.faceId;
    final cached = _controller.cachedCrop(id);
    if (cached != null) {
      _bytes = cached;
      return;
    }

    // Not made yet: the picture already showing (the person's previous one) stays
    // until this one is ready, so a change is a fade, never a blank tile.
    _holding = id;
    _controller.crop(id).then((bytes) {
      if (_holding == id) _release();
      if (mounted && widget.faceId == id && bytes != null) setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final bytes = _bytes;
    final picture = bytes == null
        ? Container(
            key: const ValueKey('placeholder'),
            color: AppColors.parchment,
            alignment: Alignment.center,
            child: Icon(Icons.person_rounded, size: widget.size * 0.45, color: AppColors.hairline),
          )
        : Image.memory(
            bytes,
            key: ValueKey(bytes),
            fit: BoxFit.cover,
            cacheWidth: (widget.size * dpr).round(),
            gaplessPlayback: true,
          );
    // Cross-fades when the picture is swapped (stack that fills the tile, so
    // the pictures aren't left loose in it).
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: picture,
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: widget.square
          ? ClipRRect(borderRadius: BorderRadius.circular(widget.radius ?? AppRadius.md), child: child)
          : ClipOval(child: child),
    );
  }
}

/// One person in the people grid: a small tilted stack of their faces (the cover on top, two
/// more of their clearest behind it), with the name and the number of photos under it. Each
/// stack leans its own way (from the person's id, so it is always the same), fans out when the
/// tile first shows, and straightens a little when pressed - the same idea as the stacks on the
/// Collections tab.
class PersonTile extends StatefulWidget {
  const PersonTile({
    super.key,
    required this.person,
    required this.onTap,
    this.onLongPress,
    this.onAddName,
    this.selecting = false,
    this.selected = false,
    this.index = 0,
  });

  final Person person;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// For a person without a name: tapping the words under the faces asks for one (instead of opening the
  /// person). Not while choosing.
  final VoidCallback? onAddName;

  // While picking several people: every tile shows a tick circle; ticked ones
  // get a ring around the stack.
  final bool selecting;
  final bool selected;

  /// Where the tile is in the grid: the stacks open one after another.
  final int index;

  @override
  State<PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<PersonTile> with TickerProviderStateMixin {
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void initState() {
    super.initState();
    // The first screenful opens one after another; a tile that scrolls in later just opens.
    final delay = Duration(milliseconds: widget.index < 8 ? widget.index * 45 : 0);
    Future<void>.delayed(delay, () {
      if (mounted) _fan.forward();
    });
  }

  @override
  void dispose() {
    _fan.dispose();
    _press.dispose();
    super.dispose();
  }

  // One face in the stack: a white-bordered rounded square (blank, if the person has too few
  // faces to fill it).
  Widget _card(int? faceId, double size, {required bool top}) {
    final radius = size * 0.24;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          top
              ? BoxShadow(color: AppColors.shadow.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 5))
              : BoxShadow(color: AppColors.shadow.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: faceId == null
            ? SizedBox(
                width: size - 6,
                height: size - 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(radius - 3),
                  ),
                ),
              )
            : FaceAvatar(faceId: faceId, size: size - 6, square: true, radius: radius - 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final person = widget.person;
    final named = person.name != null;
    final selected = widget.selected;

    // The lean of the top face is from -6.6 to 6.6 degrees, never flat; the two behind lean the
    // other way and the same way, a different amount each, and peek out to the sides.
    final h = person.id * 2654435761 & 0x7fffffff;
    final steps = (h % 7) - 3;
    var lean = steps * 2.2;
    if (lean.abs() < 2.2) lean = h.isEven ? 3.0 : -3.0;
    final dir = lean < 0 ? 1.0 : -1.0;
    final angles = [lean, lean + dir * (9 + (h >> 3) % 5), lean - dir * (6 + (h >> 5) % 4)];
    final faces = <int?>[person.coverFaceId, for (final id in person.stackFaceIds.take(2)) id];

    final addName = !named && widget.onAddName != null && !widget.selecting;
    final label = Column(
      children: [
        if (addName)
          // Looks like something to tap: the app's colour and a pencil.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Add name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          )
        else
          Text(
            named ? person.name! : 'Add name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(color: named ? AppColors.ink : AppColors.ink48),
          ),
        const SizedBox(height: 1),
        Text(
          person.photoCount == 1 ? '1 photo' : '${person.photoCount} photos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
        ),
      ],
    );

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, box) {
                // The room for the stack: the faces tilt, so they are a little smaller than
                // the space they sit in, and the ring (when chosen) goes round all of it.
                final area = (box.maxWidth - 24).clamp(60.0, 112.0);
                final card = area * 0.84;
                final shifts = [Offset.zero, Offset(dir * area * 0.07, -area * 0.03), Offset(-dir * area * 0.06, -area * 0.04)];
                return SizedBox(
                  width: area + 8,
                  height: area + 8,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: area + 8,
                        height: area + 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(area * 0.3),
                          border: Border.all(
                            color: selected ? AppColors.primary : AppColors.transparent,
                            width: 3,
                          ),
                          color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.transparent,
                        ),
                      ),
                      AnimatedScale(
                        duration: const Duration(milliseconds: 160),
                        scale: selected ? 0.94 : 1,
                        child: SizedBox(
                          width: area,
                          height: area,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Furthest back first.
                              for (final layer in const [2, 1, 0])
                                AnimatedBuilder(
                                  animation: Listenable.merge([_fan, _press]),
                                  builder: (context, child) {
                                    final open = Curves.easeOutBack.transform(_fan.value) * (1 - 0.65 * _press.value);
                                    return Transform.translate(
                                      offset: shifts[layer] * open,
                                      child: Transform.rotate(angle: angles[layer] * math.pi / 180 * open, child: child),
                                    );
                                  },
                                  child: _card(layer < faces.length ? faces[layer] : null, card, top: layer == 0),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.selecting)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? AppColors.primary : AppColors.canvas,
                              border: Border.all(
                                color: selected ? AppColors.primary : AppColors.hairline,
                                width: 1.5,
                              ),
                            ),
                            child: selected
                                ? const Icon(Icons.check_rounded, size: 16, color: AppColors.onPrimary)
                                : null,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            if (addName)
              // The name and the count together are what is tapped (the faces still open the person), so the
              // target is the full width and both lines tall without making the tile any taller. A tap that
              // lands here by mistake only opens the name box, which closes without a change.
              Semantics(
                button: true,
                label: 'Add a name, ${person.photoCount == 1 ? '1 photo' : '${person.photoCount} photos'}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: widget.onAddName,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(width: double.infinity, child: label),
                ),
              )
            else
              label,
          ],
        ),
      ),
    );
  }
}

/// Where the face scan is, as a small pill that takes the place of the "Update people"
/// button while it runs: a progress ring, what it is doing, and a pause button. Pausing puts
/// the "Update people" button back (tapping it carries on).
class FaceSyncPill extends StatelessWidget {
  const FaceSyncPill({
    super.key,
    required this.status,
    required this.onPause,
  });

  final FaceStatus status;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final waiting = status.paused;
    final tuning = status.phase == 'tune';
    final label = waiting
        ? 'Waiting for indexing'
        : tuning
            ? 'Getting ready'
            : status.phase == 'refine'
                ? 'Matching the last faces'
                : status.phase == 'videos'
                    ? 'Checking videos'
                    : 'Finding faces';
    final showCount = !waiting && !tuning && status.total > 0;
    final text = showCount ? '$label  ${status.processed}/${status.total}' : label;

    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: (waiting || tuning) ? null : status.fraction,
              color: AppColors.primary,
              backgroundColor: AppColors.hairline,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.ink80),
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Pause',
              color: AppColors.ink48,
              icon: const Icon(Icons.pause_rounded, size: 18),
              onPressed: onPause,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- sheets and dialogs ----

class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.danger = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = danger ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: textTheme.bodyMedium?.copyWith(color: color)),
                    if (subtitle != null)
                      Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: AppColors.ink48)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet in the app's style: a rounded canvas card with a title.
Future<T?> showFacesSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
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
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                Flexible(child: builder(sheetContext)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Confirms and performs a merge; the person with a name (else the one in more
/// photos) is the one that stays.
void confirmMerge(BuildContext context, FacesController faces, {required Person keep, required Person other}) {
  final keepIsA = keep.name != null || (other.name == null && keep.photoCount >= other.photoCount);
  final winner = keepIsA ? keep : other;
  final loser = keepIsA ? other : keep;
  showConfirmDialog(
    context,
    title: 'Merge these two?',
    message: '${loser.name ?? 'This person'} will be treated as the same person as '
        '${winner.name ?? 'the other'}, and their photos combined.',
    confirmLabel: 'Merge',
    onConfirm: () => faces.merge(keep: winner, other: loser),
  );
}

/// What the person asked for in [showNamePersonDialog]: a name, or to skip this person.
typedef NamePersonResult = ({String? name, bool skip});

/// One step of naming people one after another: the person's face, "Who is this?", and a place
/// for the name. Returns the name (or skip), or null if the person closed it (which ends the
/// run). [position] and [total] say how far along it is.
Future<NamePersonResult?> showNamePersonDialog(
  BuildContext context,
  Person person, {
  required int position,
  required int total,
}) {
  final field = TextEditingController();
  return showDialog<NamePersonResult>(
    context: context,
    barrierColor: AppColors.scrim.withValues(alpha: 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: FaceAvatar(faceId: person.coverFaceId, size: 96)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Who is this?',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '${person.photoCount} ${person.photoCount == 1 ? 'photo' : 'photos'}'
              '${total > 1 ? '  ·  $position of $total' : ''}',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: field,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.of(ctx).pop((name: v.trim(), skip: v.trim().isEmpty)),
              decoration: InputDecoration(
                hintText: 'Name',
                filled: true,
                fillColor: AppColors.parchment,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Stop'),
                ),
                const Spacer(),
                if (total > 1)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop((name: null, skip: true)),
                    child: const Text('Skip'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop((name: field.text.trim(), skip: field.text.trim().isEmpty)),
                  child: Text(position < total ? 'Next' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Asks for a name. Returns the text (empty means "remove the name"), or null if cancelled.
Future<String?> showRenamePersonDialog(BuildContext context, String? current) {
  final field = TextEditingController(text: current ?? '');
  return showDialog<String>(
    context: context,
    barrierColor: AppColors.scrim.withValues(alpha: 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current == null ? 'Who is this?' : 'Rename',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: field,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              decoration: InputDecoration(
                hintText: 'Name',
                filled: true,
                fillColor: AppColors.parchment,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(field.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
