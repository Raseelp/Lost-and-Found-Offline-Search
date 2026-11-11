import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/viewer/view/widgets/media_tray.dart';

/// The strip opened from the "search with this" button, in place of a full results screen.
///
/// It shows up to ten photos and videos whose CLIP embedding is closest to the one just tapped, using the search already
/// computed for it. A button of its own runs the full search, for when ten is not enough. It lives in a [MediaTray], the
/// same shell the people strip uses.
class SimilarItemsBar extends StatelessWidget {
  const SimilarItemsBar({
    super.key,
    required this.items,
    required this.bytesFor,
    required this.loading,
    required this.onTapItem,
    required this.onSearchFull,
    this.label = 'Similar to this',
  });

  final List<Map<String, dynamic>> items;
  final Uint8List? Function(Map<String, dynamic> item) bytesFor;
  final bool loading;
  final void Function(Map<String, dynamic> item, Uint8List? bytes) onTapItem;
  final VoidCallback onSearchFull;
  final String label;

  /// A horizontal ListView gives its items a tight height, which would stretch the 72x72 tile, so each tile is centred
  /// to loosen it.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MediaTray(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(color: AppColors.onMedia.withValues(alpha: 0.75)),
                  ),
                ),
                _TrayActionPill(label: 'Search with this', onTap: onSearchFull),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 92,
            child: items.isEmpty
                ? (loading
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++) ...[
                              if (i > 0) const SizedBox(width: AppSpacing.sm),
                              _ShimmerTile(index: i),
                            ],
                          ],
                        ),
                      )
                    : Center(
                        child: Text(
                          'Nothing similar found',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.onMedia.withValues(alpha: 0.6)),
                        ),
                      ))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final bytes = bytesFor(item);
                      return Center(
                        child: _SimilarTile(
                          index: i,
                          isVideo: item['isVideo'] as bool? ?? false,
                          bytes: bytes,
                          onTap: bytes == null ? null : () => onTapItem(item, bytes),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A solid pill button in the app's primary teal with white text, as the app's other pill buttons are.
///
/// It is lifted off the glass with a soft shadow and a thin bright line along its top edge. The shadow sits on the outer
/// box, which is not clipped, because the clip of the Material inside (it keeps the ink ripple within the rounded
/// corners) would cut off a shadow set on the Ink.
class _TrayActionPill extends StatelessWidget {
  const _TrayActionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.primaryGlow, AppColors.primary],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 10,
                  right: 10,
                  top: 1.5,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.transparent, AppColors.onMedia.withValues(alpha: 0.55), AppColors.transparent]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.north_east_rounded, size: 13, color: AppColors.onPrimary),
                    ],
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

class _SimilarTile extends StatelessWidget {
  const _SimilarTile({
    required this.index,
    required this.isVideo,
    required this.bytes,
    required this.onTap,
  });

  final int index;
  final bool isVideo;
  final Uint8List? bytes;
  final VoidCallback? onTap;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    if (bytes == null) return _ShimmerTile(index: index);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes!, fit: BoxFit.cover, cacheWidth: (_size * 2).round()),
              if (isVideo)
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(Icons.play_circle_fill_rounded, color: AppColors.onMedia, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm, endlessly sweeping placeholder for a tile whose thumbnail has not arrived yet.
///
/// It is a band of white light on dark glass, to suit this tray. It follows the same idea as the loading tiles of the
/// search grid (see _LoadingTile in search_results.dart). Neighbouring tiles start at different points of the sweep, so
/// the row does not pulse in lockstep. With motion off the shimmer rests, each tile where it was. Each tile has its own compositing layer, so
/// several ticking at once do not repaint the glass tray around them.
class _ShimmerTile extends StatefulWidget {
  const _ShimmerTile({this.index = 0});

  final int index;

  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  /// Sets the sweep value before repeat() starts, because setting it afterwards stops the controller and the shimmer
  /// sticks.
  @override
  void initState() {
    super.initState();
    _sweep.value = (widget.index * 0.137) % 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _sweep, rest: (widget.index * 0.137) % 1);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: _SimilarTile._size,
          height: _SimilarTile._size,
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, _) {
              final t = _sweep.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-2 + 4 * t, -1),
                    end: Alignment(-1 + 4 * t, 1),
                    colors: [
                      AppColors.onMedia.withValues(alpha: 0.05),
                      AppColors.onMedia.withValues(alpha: 0.17),
                      AppColors.onMedia.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
