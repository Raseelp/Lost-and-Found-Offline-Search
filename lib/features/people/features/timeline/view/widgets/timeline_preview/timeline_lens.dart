part of '../timeline_preview.dart';

/// The photos under the top bar. While the years move: a row of photos in date order, the one at
/// the playhead large (and dragging the row moves the years). When they come to rest on a month,
/// the preview grows and that month opens out into all its photos around the one that was in the
/// middle; moving again folds them back into one.
class TimelineLens extends StatefulWidget {
  const TimelineLens({super.key, required this.preview, required this.window, this.onOpenMonth});

  final TimelinePreview preview;
  final TimelineWindow window;

  /// A photo of the opened-out month was tapped: take the person to that month's photos.
  final void Function(int month, PreviewPhoto photo)? onOpenMonth;

  @override
  State<TimelineLens> createState() => _TimelineLensState();
}

class _TimelineLensState extends State<TimelineLens> with TickerProviderStateMixin {
  /// 0 = the row of photos, 1 = the month opened out.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    reverseDuration: const Duration(milliseconds: 340),
  );

  /// 0 = the row at its size, 1 = shrunk to a slim row (the list is being scrolled).
  late final AnimationController _shrink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 340),
  );

  static const double _slimHeight = 118;

  @override
  void initState() {
    super.initState();
    widget.preview.addListener(_sync);
    widget.window.moving.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_sync);
    widget.window.moving.removeListener(_sync);
    _open.dispose();
    _shrink.dispose();
    super.dispose();
  }

  /// The month the preview opened out for, and the photo that led it: kept while it folds back, even
  /// though the playhead has moved on by then.
  int? _openedMonth;
  PreviewPhoto? _openedHero;

  /// Only a finger on the strips makes the row itself slimmer. A scrolled list does that by scrolling, and the header
  /// collapses with it.
  void _sync() {
    if (!mounted) return;
    final compact = widget.preview.compact;
    if (widget.window.stripActive.value) {
      if (_shrink.status != AnimationStatus.forward && _shrink.status != AnimationStatus.completed) _shrink.forward();
    } else if (_shrink.status != AnimationStatus.reverse && _shrink.status != AnimationStatus.dismissed) {
      _shrink.reverse();
    }
    final media = widget.preview.mediaFor(widget.window.centre.value);
    final want = !compact &&
        !widget.window.moving.value &&
        media != null &&
        media.photos.isNotEmpty &&
        widget.preview.shown.isNotEmpty;
    if (want) {
      if (_open.status != AnimationStatus.forward && _open.status != AnimationStatus.completed) {
        final photos = widget.preview.shown;
        final idx = widget.preview.indexAt(widget.window.centreMonth);
        _openedMonth = widget.window.centre.value;
        _openedHero = photos[idx.round().clamp(0, photos.length - 1)];
        _open.forward();
      }
    } else if (_open.status != AnimationStatus.reverse && _open.status != AnimationStatus.dismissed) {
      _open.reverse();
    }
  }

  /// Frame sizes follow the height the row has.
  static double _frameHeight(double collapsed) => collapsed * 0.705;
  static double _frameWidth(double collapsed) => _frameHeight(collapsed) * 0.71;

  /// The row is slimmer while a finger is on the strips, and opened out it grows from there. The header of the list is
  /// pinned and collapses as the list scrolls, slimming step by step going down and growing step by step going up.
  /// Opened out it keeps the room it needs even when the list is scrolled, because the month was opened on purpose,
  /// while folded it can collapse to the slim row. The row can be dragged too, to move the years.
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final rowHeight = (screen * 0.27).clamp(168.0, 224.0);
    final opened = (screen * 0.43).clamp(250.0, 360.0);
    const gap = AppSpacing.sm;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.window, widget.preview, _open, _shrink]),
      builder: (context, _) {
        final photos = widget.preview.shown;
        if (photos.isEmpty) return const SliverToBoxAdapter(child: SizedBox(width: double.infinity));
        final t = _open.value;
        final base = rowHeight + (_slimHeight - rowHeight) * Curves.easeOutCubic.transform(_shrink.value);
        final full = base + (opened - base) * Curves.easeInOutCubic.transform(t);
        final least = _slimHeight + (opened - _slimHeight) * Curves.easeInOutCubic.transform(t);
        return SliverPersistentHeader(
          pinned: true,
          delegate: _LensDelegate(
            maxHeight: full + gap,
            minHeight: least + gap,
            builder: (context, shrinkOffset) {
              final height = math.max(least, full - shrinkOffset);
              final slim = ((full - height) / math.max(1.0, full - _slimHeight)).clamp(0.0, 1.0);
              final rowNow = base + (_slimHeight - base) * slim;
              return Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.base, 0, AppSpacing.base, gap),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => widget.window.dragStart(),
                  onHorizontalDragUpdate: (d) =>
                      widget.window.dragBy(d.delta.dx * _toStripPixels(_frameWidth(rowNow))),
                  onHorizontalDragEnd: (d) => widget.window.dragEnd(
                    d.velocity.pixelsPerSecond.dx * _toStripPixels(_frameWidth(rowNow)),
                  ),
                  onHorizontalDragCancel: () => widget.window.dragEnd(0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: SizedBox(
                      height: height,
                      width: double.infinity,
                      child: ColoredBox(
                        color: AppColors.parchment,
                        child: LayoutBuilder(
                          builder: (context, box) => _body(context, box.maxWidth, rowNow, opened, t, photos),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Dragging the row by a pixel moves the strips by this many pixels (it is in photos, the strips
  /// in months).
  double _toStripPixels(double frameWidth) =>
      widget.preview.monthsPerLensPixel(frameWidth * 0.9) * widget.window.ppm;

  /// Where frame [i] is in the row (in the preview's top-left corner coordinates).
  Rect _frameRect(int i, double idx, double width, double collapsed) {
    final fw = _frameWidth(collapsed), fh = _frameHeight(collapsed);
    final dist = i - idx;
    final a = dist.abs();
    final scale = math.max(0.5, 1.25 - 0.3 * a);
    final w = fw * scale, h = fh * scale;
    final offset = a < 1 ? a * fw * 0.9 : fw * 0.9 + (a - 1) * fw * 0.62;
    final x = width / 2 + (dist < 0 ? -offset : offset) - w / 2;
    return Rect.fromLTWH(x, (collapsed - h) / 2, w, h);
  }

  /// Opened or folding back, it is the month it was opened for that shows, not where the playhead has got to since.
  /// The row of photos fades out as the month opens.
  Widget _body(
    BuildContext context,
    double width,
    double collapsed,
    double opened,
    double t,
    List<PreviewPhoto> photos,
  ) {
    final preview = widget.preview, window = widget.window;
    final month = window.centre.value;
    final idx = preview.indexAt(window.centreMonth);
    final openMonth = _openedMonth ?? month;
    var heroIndex = idx.round().clamp(0, photos.length - 1);
    final led = _openedHero;
    if (led != null && t > 0) {
      final found = photos.indexWhere((p) => p.key == led.key);
      if (found >= 0) heroIndex = found;
    }

    return Stack(
      children: [
        if (t < 0.6)
          Positioned.fill(
            child: Opacity(
              opacity: (1 - t * 1.8).clamp(0.0, 1.0),
              child: _row(context, width, collapsed, photos, idx, month),
            ),
          ),
        if (t > 0)
          ..._opened(context, width, collapsed, opened, t, photos[heroIndex], _frameRect(heroIndex, idx, width, collapsed), openMonth),
        Positioned(
          left: width / 2 - 3,
          bottom: 0,
          child: Opacity(
            opacity: (1 - t * 2).clamp(0.0, 1.0),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    );
  }

  /// Draws the frames, farthest first so the nearest paint on top. Only the middle few get the sharp version, once the
  /// playhead is still. Frames further out are veiled and not see-through, because they sit behind the next one. A
  /// month with nothing in it makes the row wait and say why.
  Widget _row(BuildContext context, double width, double collapsed, List<PreviewPhoto> photos, double idx, int month) {
    final textTheme = Theme.of(context).textTheme;
    final preview = widget.preview;
    final first = math.max(0, idx.floor() - 5);
    final last = math.min(photos.length - 1, idx.floor() + 6);

    final order = [for (var i = first; i <= last; i++) i]..sort((a, b) => (b - idx).abs().compareTo((a - idx).abs()));
    final children = <Widget>[];
    for (final i in order) {
      final photo = photos[i];
      final dist = i - idx;
      final a = dist.abs();
      final rect = _frameRect(i, idx, width, collapsed);
      final near = a < 1.5;
      children.add(
        Positioned(
          key: ValueKey(photo.cacheKey),
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.canvas, width: 2.5),
              boxShadow: a < 0.8
                  ? [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6))]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7.5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PreviewImage(
                    photo: photo,
                    loader: preview.loader,
                    large: near && preview.settled,
                    sharp: a < 0.8 && preview.settled && PreviewLoader.wantsSharp(rect.size, MediaQuery.devicePixelRatioOf(context)),
                    fill: AppColors.hairline,
                  ),
                  if (near)
                    Positioned(
                      left: dist > 0.4 ? null : 6,
                      right: dist > 0.4 ? 6 : null,
                      bottom: 4,
                      child: Text(
                        _dayLabel(photo.taken),
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.onMedia,
                          fontWeight: FontWeight.w600,
                          shadows: const [Shadow(color: AppColors.scrim54, blurRadius: 4)],
                        ),
                      ),
                    ),
                  if (photo.isVideo)
                    const Positioned(
                      right: 5,
                      top: 5,
                      child: Icon(Icons.play_circle_fill_rounded, size: 18, color: AppColors.onMedia),
                    ),
                  if (a > 0.3)
                    Positioned.fill(
                      child: ColoredBox(
                        color: AppColors.parchment.withValues(alpha: math.min(0.6, 0.17 * a)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ...children,
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              layoutBuilder: switcherStack(),
              child: preview.countIn(month) == 0
                  ? Container(
                      key: const ValueKey('empty'),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.canvas.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'No photos in ${monthLabel(month)}',
                        style: textTheme.labelSmall?.copyWith(color: AppColors.ink80),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('full')),
            ),
          ),
        ),
      ],
    );
  }

  /// The month's photos in a bento: the one that was in the middle of the row grows into the big tile, which starts
  /// where the middle frame was, and the others come out small from behind it, one after another, in the order they
  /// were taken. The big tiles are sharpened once settled and the last one says how many more there are. Chips across
  /// the top show the two moments that matter most, and a first photo together is one chip with both faces.
  List<Widget> _opened(
    BuildContext context,
    double width,
    double collapsed,
    double opened,
    double t,
    PreviewPhoto middle,
    Rect middleRect,
    int month,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final media = widget.preview.mediaFor(month);
    if (media == null || media.photos.isEmpty) return const [];

    final photos = <PreviewPhoto>[
      middle,
      for (final p in media.photos)
        if (p.key != middle.key) p,
    ].take(9).toList();
    const pad = 8.0;
    final area = Size(width - pad * 2, opened - pad * 2);
    final rects = bentoRects(photos.length, area, heroRight: month.isOdd);
    final remaining = media.total - photos.length;

    final out = <Widget>[];
    for (var i = photos.length - 1; i >= 0; i--) {
      final target = rects[i].shift(const Offset(pad, pad));
      final from = i == 0 ? middleRect : Rect.fromCenter(center: middleRect.center, width: middleRect.width * 0.55, height: middleRect.height * 0.55);
      final begin = i == 0 ? 0.0 : math.min(0.55, 0.14 + 0.05 * i);
      final local = Curves.easeOutCubic.transform(((t - begin) / (1 - begin)).clamp(0.0, 1.0));
      final rect = Rect.lerp(from, target, local)!;
      final radius = 10 + 4 * local;
      out.add(
        Positioned(
          key: ValueKey('open${photos[i].cacheKey}'),
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: Opacity(
            opacity: i == 0 ? 1 : local,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: t >= 0.8 && widget.onOpenMonth != null ? () => widget.onOpenMonth!(month, photos[i]) : null,
              child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: i == 0 || local > 0.3
                    ? [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.16 * (i == 0 ? 1 : local)), blurRadius: 12, offset: const Offset(0, 4))]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PreviewImage(
                      photo: photos[i],
                      loader: widget.preview.loader,
                      large: true,
                      sharp: t >= 0.8 && PreviewLoader.wantsSharp(target.size, MediaQuery.devicePixelRatioOf(context)),
                      fill: AppColors.hairline,
                      alignment: const Alignment(0, -0.25),
                    ),
                    if (photos[i].isVideo)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(Icons.play_circle_fill_rounded, size: 20, color: AppColors.onMedia),
                      ),
                    if (i == photos.length - 1 && remaining > 0)
                      Positioned.fill(
                        child: ColoredBox(
                          color: AppColors.scrim.withValues(alpha: 0.45),
                          child: Center(
                            child: Text(
                              '+$remaining',
                              style: textTheme.titleMedium?.copyWith(color: AppColors.onMedia, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      );
    }

    final candidates = <({int importance, _MomentChip chip})>[];
    final pairs = <String>{};
    for (final m in widget.preview.momentsIn(month)) {
      final other = m.milestone.withId;
      IconData icon;
      switch (m.milestone.kind) {
        case MilestoneKind.firstTogether:
          icon = Icons.favorite_rounded;
        case MilestoneKind.comeback:
          icon = Icons.waving_hand_rounded;
        case MilestoneKind.lovelyRun:
          icon = Icons.auto_awesome_rounded;
      }
      if (m.milestone.kind == MilestoneKind.firstTogether && other != null) {
        final a = m.row.person.id;
        if (!pairs.add(a < other ? '$a-$other' : '$other-$a')) continue;
        final friend = widget.preview.personById(other);
        if (friend != null) {
          candidates.add((
            importance: m.milestone.importance,
            chip: _MomentChip(people: [m.row.person, friend], icon: icon, text: 'First photo together'),
          ));
          continue;
        }
      }
      candidates.add((
        importance: m.milestone.importance,
        chip: _MomentChip(people: [m.row.person], icon: icon, text: m.milestone.short),
      ));
    }
    for (final g in widget.preview.groupsIn(month)) {
      candidates.add((
        importance: g.importance,
        chip: _MomentChip(people: g.people.take(3).toList(), icon: groupIcon(g.kind), text: g.short),
      ));
    }
    candidates.sort((a, b) => b.importance.compareTo(a.importance));
    final moments = [for (final c in candidates.take(2)) c.chip];
    if (moments.isNotEmpty) {
      out.add(
        Positioned(
          left: 14,
          right: 14,
          top: 14,
          child: IgnorePointer(
            child: Opacity(
              opacity: ((t - 0.75) / 0.25).clamp(0.0, 1.0),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs + 2,
                children: moments,
              ),
            ),
          ),
        ),
      );
    }

    final hero = rects[0].shift(const Offset(pad, pad));
    out.add(
      Positioned(
        left: hero.left + 8,
        width: hero.width - 16,
        top: hero.bottom - 34,
        child: Opacity(
          opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.scrim.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${monthLabel(month)}  ·  ${media.total == 1 ? '1 photo' : '${media.total} photos'}',
                  style: textTheme.labelMedium?.copyWith(color: AppColors.onMedia, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return out;
  }

  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dayLabel(DateTime t) => '${_short[t.month - 1]} ${t.day}';
}

/// The preview as a header of the list: pinned, as tall as it is at rest at the top, and collapsing to a
/// slim row as the list is scrolled (the way a collapsing app bar does).
class _LensDelegate extends SliverPersistentHeaderDelegate {
  _LensDelegate({required this.maxHeight, required this.minHeight, required this.builder});

  final double maxHeight, minHeight;
  final Widget Function(BuildContext context, double shrinkOffset) builder;

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => builder(context, shrinkOffset);

  @override
  bool shouldRebuild(covariant _LensDelegate old) => true;
}
