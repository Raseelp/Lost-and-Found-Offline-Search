import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

/// The "On this day" card on the Library tab: today's date, how much there is from past years, a little
/// stack of its best photos. Not there at all while there is nothing for the date (or while a scan runs:
/// the chip above shows that). Opens the "On this day" screen.
class OnThisDaySection extends StatefulWidget {
  const OnThisDaySection({
    super.key,
    required this.visible,
    required this.indexed,
  });

  /// Whether the Library tab is showing the card at all (something is indexed and no scan is running).
  final bool visible;

  /// How many things are indexed: when it changes the memories are looked up again.
  final int indexed;

  @override
  State<OnThisDaySection> createState() => _OnThisDaySectionState();
}

class _OnThisDaySectionState extends State<OnThisDaySection> {
  final PreviewLoader _loader = PreviewLoader();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final memories = Get.find<MemoriesController>();
      memories.onIndexChanged(widget.indexed);
      // Not while a scan runs (or nothing is indexed): dating the library would compete with it.
      if (widget.visible) unawaited(memories.loadToday());
    });
  }

  @override
  void didUpdateWidget(covariant OnThisDaySection old) {
    super.didUpdateWidget(old);
    // Compared with what the controller last saw, not with the last build: a scan changes the number all
    // the way through while the card is hidden, and what matters is that it differs when the card comes back.
    if (widget.visible) {
      final memories = Get.find<MemoriesController>();
      memories.onIndexChanged(widget.indexed);
      // The card is back (a scan ended, something got indexed): look today up if it has not been.
      if (!old.visible) unawaited(memories.loadToday());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MemoriesController>(
      builder: (memories) {
        final today = memories.today;
        final show = widget.visible && memories.loaded && !today.isEmpty;
        return AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: show
                ? Padding(
                    key: const ValueKey('card'),
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: _Card(
                      today: today,
                      loader: _loader,
                      onTap: memories.openOnThisDay,
                    ),
                  )
                : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.today, required this.loader, required this.onTap});

  final OnThisDay today;
  final PreviewLoader loader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final covers = today.coverPhotos();
    final years = today.years.length;
    final anniversary = today.anniversaries.isEmpty
        ? null
        : today.anniversaries.first;
    return Semantics(
      button: true,
      label:
          'On this day, ${today.dateLabel}. ${today.total} photos and videos from $years years. Opens the memories.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'ON THIS DAY',
                                style: textTheme.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                  letterSpacing: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(today.dateLabel, style: textTheme.headlineSmall),
                          const SizedBox(height: 2),
                          Text(
                            years == 0
                                ? 'A first photo together, today'
                                : today.exact.isEmpty
                                ? 'This week, in other years'
                                : (years == 1
                                      ? 'From 1 year  ·  ${today.total} photos'
                                      : 'From $years years  ·  ${today.total} photos'),
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.ink48,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _CoverStack(photos: covers, loader: loader),
                  ],
                ),
                if (anniversary != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${anniversary.yearsAgo == 1 ? '1 year' : '${anniversary.yearsAgo} years'} of ${anniversary.who} in photos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A few photos stacked and tilted, the best one on top - the way the Collections tab stacks theirs.
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.photos, required this.loader});

  final List<MemoryPhoto> photos;
  final PreviewLoader loader;

  static const double _w = 76, _h = 96;
  static const _tilts = [-7.0, 5.0, -2.0];

  @override
  Widget build(BuildContext context) {
    final shown = photos.take(3).toList();
    if (shown.isEmpty) return const SizedBox(width: 20);
    final width = _w + (shown.length - 1) * 26.0;
    return SizedBox(
      width: width + 8,
      height: _h + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The last is at the back, the first (the best) on top.
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: (shown.length - 1 - i) * 26.0,
              top: 7 + (i.isOdd ? 4.0 : 0.0),
              child: Transform.rotate(
                angle: _tilts[i % _tilts.length] * math.pi / 180,
                child: Container(
                  width: _w,
                  height: _h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: PreviewImage(
                      photo: shown[i].preview,
                      loader: loader,
                      large: true,
                      fill: AppColors.hairline,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
