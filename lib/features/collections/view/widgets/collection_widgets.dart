import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/export/controllers/export_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/features/collections/models/collection_model.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/export/view/export_zip_screen.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_input_field.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/features/collections/view/widgets/new_collection_sheet.dart';
part 'collection_widgets/shared.dart';
part 'collection_widgets/save_collection_sheet.dart';
part 'collection_widgets/show_collection_menu.dart';
part 'collection_widgets/show_on_this_day_menu.dart';

/// One collection in the Collections tab's mosaic: its cover photo filling the tile, the name and item count over a
/// dark fade, and a "New" tag when something from the latest scan is in it.
/// The cover is the collection's photo of the day (see [CollectionsController.coverFor]), loaded when the tile comes
/// on screen: a small picture first if one is at hand, then a sharper one, asked for a third larger than the tile's
/// longer side so it fills the tile either way round. While a collection is computed the picture breathes (still with
/// motion off), and the tile pops once when that ends.
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

  /// The cover loaded for this tile.
  Uint8List? _loaded;

  /// The size asked for so far, 0 for nothing yet.
  int _asked = 0;

  /// The sizes a cover is asked for in. There are few, so the pictures are shared between tiles and chips.
  static const _sizes = [480, 720, 960, 1280, 1600];

  /// Asks for a cover of at least [needed] pixels. The load starts after this frame, because this is called while the
  /// tile is being laid out.
  void _want(int needed) {
    if (widget.coverKey == null) return;
    final size = _sizes.firstWhere((s) => s >= needed, orElse: () => _sizes.last);
    if (size <= _asked) return;
    _asked = size;
    final key = widget.coverKey;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bytes = await widget.loadCover(size);
      if (!mounted || bytes == null || key != widget.coverKey || identical(bytes, _loaded)) return;
      setState(() => _loaded = bytes);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.syncing) loopUnlessCalm(context, _sweep);
  }

  @override
  void didUpdateWidget(covariant CollectionCard old) {
    super.didUpdateWidget(old);
    if (widget.coverKey != old.coverKey) {
      _loaded = null;
      _asked = 0;
    }
    if (widget.syncing && !old.syncing) {
      loopUnlessCalm(context, _sweep);
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
                final big = box.maxWidth > 260 || box.maxHeight > 300;
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

String _countLabel(int count) => count == 1 ? '1 item' : '$count items';
