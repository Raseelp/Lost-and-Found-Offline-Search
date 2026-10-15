import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/day_photos_screen.dart';
import 'package:lost_and_found/view/widget/memory_widgets.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

/// "On this day": today's date in the past years of the library - a section for each year, with the
/// photos that stand for it, and a card for every first photo together that has its anniversary today.
/// [focusYear] scrolls to that year (a tapped notification is about one).
class OnThisDayScreen extends StatefulWidget {
  const OnThisDayScreen({super.key, this.focusYear});

  final int? focusYear;

  @override
  State<OnThisDayScreen> createState() => _OnThisDayScreenState();
}

class _OnThisDayScreenState extends State<OnThisDayScreen> {
  final PreviewLoader _loader = PreviewLoader();
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Fresh when opened (a notification can open it before the card has loaded).
    Get.find<MemoriesController>().loadToday();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int year) => _keys.putIfAbsent(year, GlobalKey.new);

  // A tapped notification is about one year: scrolled to once it is on screen.
  void _focusIfNeeded() {
    final year = widget.focusYear;
    if (_focused || year == null) return;
    _focused = true;
    _scrollToYear(year, 12);
  }

  // The list builds only what is near the screen, so a year further down has no widget yet: the list is
  // moved on a screenful at a time until it has.
  void _scrollToYear(int year, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _keys[year]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        );
      } else if (tries > 0 && _scroll.hasClients) {
        final p = _scroll.position;
        if (p.pixels >= p.maxScrollExtent) return;
        _scroll.jumpTo(
          (p.pixels + p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent),
        );
        _scrollToYear(year, tries - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: GetBuilder<MemoriesController>(
          builder: (memories) {
            final today = memories.today;
            if (!today.isEmpty) _focusIfNeeded();
            final years = today.years;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.base,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppColors.ink,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: today.isEmpty
                      ? _Empty(loading: !memories.loaded)
                      : ListView(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            0,
                            AppSpacing.xl,
                            MediaQuery.of(context).padding.bottom +
                                AppSpacing.xxl,
                          ),
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ON THIS DAY',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              today.dateLabel,
                              style: textTheme.displaySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              years.isEmpty
                                  ? 'A first photo together has its anniversary today.'
                                  : today.exact.isEmpty
                                  ? 'Nothing on the day itself. Here is the week round it, in other years.'
                                  : _summary(years.length, today.total),
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.ink48,
                                height: 1.4,
                              ),
                            ),
                            for (final a in today.anniversaries) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _AnniversaryCard(anniversary: a, loader: _loader),
                            ],
                            for (final y in years) ...[
                              const SizedBox(height: AppSpacing.xxl),
                              _YearSection(
                                key: _keyFor(y.year),
                                year: y,
                                today: today,
                                loader: _loader,
                                highlighted: y.year == widget.focusYear,
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _summary(int years, int total) {
    final y = years == 1 ? 'one year' : '$years years';
    return 'Photos and videos from $y: $total in all.';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(
                Icons.auto_awesome_outlined,
                size: 32,
                color: AppColors.ink48,
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              loading
                  ? 'Looking through your years...'
                  : 'No memories from this date yet.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.ink80),
            ),
            if (!loading) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'They appear here as your photos are indexed and dated.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink48,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two people's first photo together, on its anniversary.
class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard({required this.anniversary, required this.loader});

  final MemoryAnniversary anniversary;
  final PreviewLoader loader;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photo = anniversary.photo;
    final years = anniversary.yearsAgo == 1
        ? '1 year'
        : '${anniversary.yearsAgo} years';
    final date = DateTime.fromMillisecondsSinceEpoch(anniversary.firstMs);
    return Material(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: photo == null
            ? null
            : () => openMemoryPhoto(context, loader, photo.preview),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (photo != null)
                SizedBox(
                  width: 84,
                  height: 84,
                  child: MemoryTile(
                    photo: photo.preview,
                    loader: loader,
                    large: true,
                    radius: 14,
                  ),
                ),
              if (photo != null) const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$years together in photos'.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(anniversary.who, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'First photo together: ${dayLabel(date.month, date.day)}, ${date.year}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One past year: how long ago, what there is, and the photos that stand for it in a bento.
class _YearSection extends StatelessWidget {
  const _YearSection({
    super.key,
    required this.year,
    required this.today,
    required this.loader,
    required this.highlighted,
  });

  final MemoryYear year;
  final OnThisDay today;
  final PreviewLoader loader;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photos = year.photos;
    final more = year.total - photos.length;
    final day = dayOf(year, today);
    final width = MediaQuery.sizeOf(context).width - AppSpacing.xl * 2;
    final area = Size(width, width * (photos.length <= 2 ? 0.62 : 0.8));
    final rects = bentoRects(photos.length, area, heroRight: year.year.isOdd);

    void openAll() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DayPhotosScreen(from: day.from, days: day.days, title: day.title),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(yearsAgoLabel(year.yearsAgo), style: textTheme.titleLarge),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${year.year}',
              style: textTheme.titleMedium?.copyWith(color: AppColors.ink48),
            ),
            if (highlighted) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (today.exact.isEmpty && photos.isNotEmpty)
              dayLabel(photos.first.taken.month, photos.first.taken.day),
            year.total == 1
                ? '1 photo or video'
                : '${year.total} photos and videos',
            if (year.names.isNotEmpty) year.names.take(3).join(', '),
          ].join('  ·  '),
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink48,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: width,
          height: area.height,
          child: Stack(
            children: [
              for (var i = 0; i < photos.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: MemoryTile(
                    photo: photos[i].preview,
                    loader: loader,
                    large: rects[i].width > 150,
                    radius: AppRadius.lg,
                    onTap: i == photos.length - 1 && more > 0
                        ? openAll
                        : () => openMemoryPhoto(
                            context,
                            loader,
                            photos[i].preview,
                          ),
                    overlay: i == photos.length - 1 && more > 0
                        ? ColoredBox(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: Text(
                                '+$more',
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: openAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                foregroundColor: AppColors.primary,
              ),
              child: Text('See all ${year.total}'),
            ),
          ),
      ],
    );
  }
}
