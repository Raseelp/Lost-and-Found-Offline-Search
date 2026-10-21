import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/media_view_route.dart';
import 'package:lost_and_found/view/image_full_screen.dart';
import 'package:lost_and_found/view/video_full_screen.dart';
import 'package:lost_and_found/view/widget/moment_badge.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

/// Every photo and video with people in it from one month of the timeline, day by day. Tapping one
/// opens it. [focusKey] is the photo that was tapped in the timeline's preview: the list scrolls to
/// it and it shows for a moment.
class MonthPhotosScreen extends StatefulWidget {
  const MonthPhotosScreen({super.key, required this.month, this.focusKey});

  /// The month, as year * 12 + 0-based month.
  final int month;
  final int? focusKey;

  @override
  State<MonthPhotosScreen> createState() => _MonthPhotosScreenState();
}

class _MonthPhotosScreenState extends State<MonthPhotosScreen> {
  static const int _columns = 3;
  static const double _gap = 4;

  final PreviewLoader _loader = PreviewLoader();
  final ScrollController _scroll = ScrollController();

  List<PreviewPhoto> _photos = const [];
  int _total = 0;
  bool _loading = true;
  bool _failed = false;

  // The photo that was tapped in the preview: ringed for a moment.
  int? _flashKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final from = DateTime(widget.month ~/ 12, widget.month % 12 + 1);
      final to = DateTime(widget.month ~/ 12, widget.month % 12 + 2);
      // Everything, bursts included: this is the whole month.
      final found = await NativeServices().timelineMonthMedia(from, to, limit: 2000, burstMs: 0);
      if (!mounted) return;
      setState(() {
        _photos = found.photos;
        _total = found.total;
        _loading = false;
      });
      _showFocus();
    } catch (e) {
      debugPrint('month photos failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  // Scrolls to the photo that was tapped and rings it.
  void _showFocus() {
    final key = widget.focusKey;
    if (key == null) return;
    final index = _photos.indexWhere((p) => p.key == key);
    if (index < 0) return;
    setState(() => _flashKey = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final width = MediaQuery.sizeOf(context).width - AppSpacing.base * 2;
      final tile = (width - _gap * (_columns - 1)) / _columns;
      // The photos before it by day: a header and rows for each day.
      var offset = 0.0;
      for (final day in _days()) {
        final inDay = day.photos.indexWhere((p) => p.key == key);
        offset += _headerHeight;
        if (inDay >= 0) {
          offset += (inDay ~/ _columns) * (tile + _gap);
          break;
        }
        offset += (day.photos.length / _columns).ceil() * (tile + _gap);
      }
      _scroll.animateTo(
        (offset - 24).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _flashKey = null);
    });
  }

  static const double _headerHeight = 40;

  // The photos grouped by the day they were taken.
  List<({DateTime day, List<PreviewPhoto> photos})> _days() {
    final out = <({DateTime day, List<PreviewPhoto> photos})>[];
    for (final p in _photos) {
      final t = p.taken;
      final day = DateTime(t.year, t.month, t.day);
      if (out.isNotEmpty && out.last.day == day) {
        out.last.photos.add(p);
      } else {
        out.add((day: day, photos: [p]));
      }
    }
    return out;
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Future<void> _open(PreviewPhoto photo) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final native = Get.find<NativeController>();
    final bytes = _loader.peek(photo, large: true, sharp: true) ??
        _loader.peek(photo, large: true) ??
        _loader.peek(photo, large: false) ??
        await _loader.get(photo, large: false);
    if (bytes == null || !mounted) return;
    unawaited(native.loadMetaDataByUri(uri: photo.uri, isVideo: photo.isVideo));
    if (photo.isVideo) {
      Navigator.of(context).push(
        mediaViewRoute(
          (_) => VideoViewScreen(videoUri: photo.uri, timestampMs: photo.tsMs, thumbnailBytes: bytes),
        ),
      );
    } else {
      Navigator.of(context).push(
        mediaViewRoute((_) => ImageViewScreen(imageBytes: bytes, uri: photo.uri, loadFullRes: true)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final days = _days();
    final count = math.max(_total, _photos.length);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.base, AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(monthLabel(widget.month), style: textTheme.titleLarge),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _loading ? ' ' : (count == 1 ? '1 photo or video' : '$count photos and videos'),
                            key: ValueKey(_loading),
                            style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _failed
                  ? Center(
                      child: Text(
                        "Couldn't load this month.",
                        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                      ),
                    )
                  : (!_loading && _photos.isEmpty)
                  ? Center(
                      child: Text(
                        'Nothing from this month.',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                      ),
                    )
                  : CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        if (_loading)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                            sliver: SliverGrid.count(
                              crossAxisCount: _columns,
                              mainAxisSpacing: _gap,
                              crossAxisSpacing: _gap,
                              children: [
                                for (var i = 0; i < 12; i++)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.parchment,
                                      borderRadius: BorderRadius.circular(AppRadius.md),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        for (final day in days) ...[
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: _headerHeight,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.base, AppSpacing.xs),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text('${day.day.day}', style: textTheme.titleMedium),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      _weekdays[day.day.weekday - 1],
                                      style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _columns,
                                mainAxisSpacing: _gap,
                                crossAxisSpacing: _gap,
                              ),
                              delegate: SliverChildBuilderDelegate((context, i) {
                                final photo = day.photos[i];
                                final flash = photo.key == _flashKey;
                                return GestureDetector(
                                  onTap: () => _open(photo),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(AppRadius.md),
                                      border: Border.all(
                                        color: flash ? AppColors.primary : AppColors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(AppRadius.md - (flash ? 2 : 0)),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          PreviewImage(
                                            photo: photo,
                                            loader: _loader,
                                            large: true,
                                            fill: AppColors.parchment,
                                            alignment: const Alignment(0, -0.25),
                                          ),
                                          if (photo.isVideo)
                                            const Positioned(
                                              right: 6,
                                              top: 6,
                                              child: Icon(Icons.play_circle_fill_rounded, size: 20, color: AppColors.onMedia),
                                            ),
                                          Positioned(left: 9, top: 0, child: MomentTag(uri: photo.uri)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }, childCount: day.photos.length),
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                          child: SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.xxl),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

