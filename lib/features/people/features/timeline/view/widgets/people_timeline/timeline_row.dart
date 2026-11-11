part of '../people_timeline.dart';

class TimelineRow extends StatefulWidget {
  const TimelineRow({
    super.key,
    required this.row,
    required this.layout,
    required this.window,
    required this.now,
    required this.datesDone,
    required this.memory,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.compact = false,
    this.preview,
  });

  /// The collapsed list: names and thin lines only, no faces.
  final bool compact;

  /// Where the person's photo of the month under the playhead comes from (their face is shown
  /// without it).
  final TimelinePreview? preview;

  final TimelineRowData row;
  final TimelineLayout layout;
  final TimelineWindow window;
  final DateTime now;

  /// Whether every date has been looked up (before that, what is missing is not "undated" yet).
  final bool datesDone;
  final TimelineMemory memory;

  /// Place in the list: the first rows come in one after another.
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  State<TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<TimelineRow> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _develop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void initState() {
    super.initState();
    final id = widget.row.person.id;
    if (widget.memory.entered.contains(id)) {
      _enter.value = 1;
    } else {
      widget.memory.entered.add(id);
      Future<void>.delayed(Duration(milliseconds: widget.index < 8 ? widget.index * 70 : 0), () {
        if (mounted) _enter.forward();
      });
    }
    if (widget.memory.developed.contains(id)) {
      _develop.value = 1;
    } else {
      _developWhenReady();
    }
  }

  @override
  void didUpdateWidget(covariant TimelineRow old) {
    super.didUpdateWidget(old);
    if (!_develop.isAnimating && _develop.value == 0) _developWhenReady();
  }

  /// The strip develops once there is something on it, a moment after the row has come in.
  void _developWhenReady() {
    final id = widget.row.person.id;
    if (!widget.row.hasDates || widget.memory.developed.contains(id)) return;
    widget.memory.developed.add(id);
    final delay = Duration(milliseconds: 260 + (widget.index < 8 ? widget.index * 70 : 0));
    Future<void>.delayed(delay, () {
      if (mounted) _develop.forward();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _develop.dispose();
    _press.dispose();
    super.dispose();
  }

  /// Leans a little, the same way every time (the way their tile on the grid does).
  double get _lean {
    final h = widget.row.person.id * 2654435761 & 0x7fffffff;
    var lean = ((h % 7) - 3) * 1.6;
    if (lean.abs() < 1.6) lean = h.isEven ? 2.2 : -2.2;
    return lean;
  }

  /// The collapsed row: the name (dimmed while the playhead is on a month they are not in) and
  /// one line along the years.
  Widget _compactContent(BuildContext context, Color tone) {
    final textTheme = Theme.of(context).textTheme;
    final row = widget.row;
    final person = row.person;
    final named = person.name != null;
    return Row(
      children: [
        SizedBox(
          width: _compactColumn,
          child: ValueListenableBuilder<int>(
            valueListenable: widget.window.centre,
            builder: (context, month, child) => AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: !row.hasDates || row.countAt(month - widget.layout.startMonth) > 0 ? 1 : 0.38,
              child: child,
            ),
            child: Row(
              children: [
                if (widget.selecting) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected ? AppColors.primary : AppColors.canvas,
                      border: Border.all(
                        color: widget.selected ? AppColors.primary : AppColors.hairline,
                        width: 1.5,
                      ),
                    ),
                    child: widget.selected
                        ? const Icon(Icons.check_rounded, size: 11, color: AppColors.onPrimary)
                        : null,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    named ? person.name! : 'Add name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: named ? AppColors.ink : AppColors.ink48,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: _columnGap),
        Expanded(
          child: _Strip(
            row: row,
            layout: widget.layout,
            window: widget.window,
            tone: tone,
            develop: _develop,
            onTap: widget.onTap,
            compact: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final row = widget.row;
    final person = row.person;
    final tone = _toneFor(person.id);
    final nowMonth = monthIndex(widget.now);
    final named = person.name != null;
    final caption = row.hasDates
        ? row.rangeLabel(nowMonth)
        : (widget.datesDone ? 'No dates found' : 'Looking up dates...');

    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: fade,
      builder: (context, child) => Opacity(
        opacity: fade.value,
        child: Transform.translate(offset: Offset(0, (1 - fade.value) * 14), child: child),
      ),
      child: Semantics(
        button: true,
        label: '${named ? person.name : 'Unnamed person'}, ${row.rangeLabel(nowMonth)}, ${row.photoCount} photos',
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: _pad - AppSpacing.sm),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: widget.compact ? AppSpacing.xs + 1 : AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: widget.selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.transparent,
            ),
            child: widget.compact ? _compactContent(context, tone) : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _leftColumn,
                  child: ValueListenableBuilder<int>(
                    valueListenable: widget.window.centre,
                    builder: (context, month, child) => AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: !row.hasDates || row.countAt(month - widget.layout.startMonth) > 0 ? 1 : 0.38,
                      child: child,
                    ),
                    child: Column(
                      children: [
                        _Avatar(
                          personId: person.id,
                          preview: widget.preview,
                          faceId: person.coverFaceId,
                          lean: _lean,
                          press: _press,
                          selecting: widget.selecting,
                          selected: widget.selected,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          named ? person.name! : 'Add name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
                            color: named ? AppColors.ink : AppColors.ink48,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: _columnGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Strip(
                        row: row,
                        layout: widget.layout,
                        window: widget.window,
                        tone: tone,
                        develop: _develop,
                        onTap: widget.onTap,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs + 1),
                        child: ValueListenableBuilder<int>(
                          valueListenable: widget.window.centre,
                          builder: (context, month, _) {
                            final count = row.countAt(month - widget.layout.startMonth);
                            final moments = [
                              for (final m in row.milestones)
                                if (m.month == month) m,
                            ];
                            final moment = moments.isEmpty ? null : moments.first;
                            final here = count > 0 || moment != null;
                            final text = moment != null
                                ? moment.long
                                : (count > 0
                                      ? '${count == 1 ? '1 photo' : '$count photos'} in ${monthLabel(month)}'
                                      : caption);
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 120),
                                    layoutBuilder: switcherStack(alignment: Alignment.centerLeft),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          if (moment != null)
                                            WidgetSpan(
                                              alignment: PlaceholderAlignment.middle,
                                              child: Padding(
                                                padding: const EdgeInsets.only(right: 5),
                                                child: Icon(_momentIcon(moment.kind), size: 14, color: tone),
                                              ),
                                            ),
                                          TextSpan(text: text),
                                        ],
                                      ),
                                      key: ValueKey(text),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: here ? tone : AppColors.ink48,
                                        fontWeight: here ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                                if (widget.datesDone && row.undated > 0 && !here) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      row.undated == 1 ? '1 without a date' : '${row.undated} without a date',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: AppColors.ink48,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
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

IconData _momentIcon(MilestoneKind kind) {
  switch (kind) {
    case MilestoneKind.firstTogether:
      return Icons.favorite_rounded;
    case MilestoneKind.comeback:
      return Icons.waving_hand_rounded;
    case MilestoneKind.lovelyRun:
      return Icons.auto_awesome_rounded;
  }
}

Color _toneFor(int personId) => _tones[((personId * 2654435761) & 0x7fffffff) % _tones.length];

/// A person's colour on the timeline: soft, a little dusty, and the same every time.
const List<Color> _tones = [
  PeoplePalette.red450,
  AppColors.honey,
  PeoplePalette.red400,
  PeoplePalette.green450,
  AppColors.primary,
  PeoplePalette.sky450,
  PeoplePalette.indigo450,
  PeoplePalette.gold550,
];

/// Which rows have already come in and which strips have already developed, so they do not play
/// again on a scroll back or a change of order.
class TimelineMemory {
  final Set<int> entered = {};
  final Set<int> developed = {};
}
