import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/memory_widgets.dart';
import 'package:lost_and_found/view/widget/then_now_card.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

const _short = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthYear(DateTime t) => '${_short[t.month - 1]} ${t.year}';

/// A person's start and their latest side by side, with a divider to drag between the two: the same framing in
/// both, so the change is what you see. Under it, up to three photos at each end to choose from: the one picked
/// is the one in the comparison.
class ThenAndNowScreen extends StatefulWidget {
  const ThenAndNowScreen({
    super.key,
    required this.person,
    required this.found,
  });

  final Person person;
  final ThenNow found;

  @override
  State<ThenAndNowScreen> createState() => _ThenAndNowScreenState();
}

class _ThenAndNowScreenState extends State<ThenAndNowScreen>
    with SingleTickerProviderStateMixin {
  final MemoriesController _memories = Get.find<MemoriesController>();
  final PreviewLoader _loader = PreviewLoader();

  // Where the divider is, as a share of the width: it sweeps in from the edge when the screen opens, to
  // show there are two pictures, until a finger takes it.
  final ValueNotifier<double> _split = ValueNotifier(1);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _touched = false;

  // Which of the few photos at each end is shown (the ones picked first are random, the same all day).
  late int _thenAt = widget.found.startThen, _nowAt = widget.found.startNow;

  @override
  void initState() {
    super.initState();
    _intro.addListener(() {
      if (!_touched) {
        _split.value = 1 - 0.5 * Curves.easeInOutCubic.transform(_intro.value);
      }
    });
    // After the pictures have had a moment to arrive.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_touched) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _split.dispose();
    super.dispose();
  }

  void _set(double share) {
    _touched = true;
    _intro.stop();
    final next = share.clamp(0.0, 1.0);
    // A light tick as the divider passes the middle.
    if ((_split.value - 0.5).sign != (next - 0.5).sign) {
      HapticFeedback.selectionClick();
    }
    _split.value = next;
  }

  PreviewPhoto _photo(ThenNowSide s) => PreviewPhoto(
    key: s.key,
    uri: s.uri,
    isVideo: false,
    tsMs: 0,
    takenMs: s.takenMs,
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final found = widget.found;
    final then =
        found.thenOptions[_thenAt.clamp(0, found.thenOptions.length - 1)];
    final now = found.nowOptions[_nowAt.clamp(0, found.nowOptions.length - 1)];
    final today = DateTime.now();
    final latestLabel = found.isNow(today) ? 'NOW' : 'LATEST';
    final width = MediaQuery.sizeOf(context).width - AppSpacing.xl * 2;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            MediaQuery.of(context).padding.bottom + AppSpacing.xxl,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'THEN AND $latestLabel',
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
              widget.person.name ?? 'Then and ${latestLabel.toLowerCase()}',
              style: textTheme.displaySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${found.spanLabel} between these two. Drag the line.',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: width,
              height: width,
              child: _Compare(
                then: then,
                now: now,
                latestLabel: latestLabel,
                split: _split,
                memories: _memories,
                onSet: _set,
              ),
            ),
            if (found.thenOptions.length > 1 ||
                found.nowOptions.length > 1) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Options(
                      sides: found.thenOptions,
                      selected: _thenAt,
                      memories: _memories,
                      onSelect: (i) => setState(() => _thenAt = i),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Options(
                      sides: found.nowOptions,
                      selected: _nowAt,
                      memories: _memories,
                      onSelect: (i) => setState(() => _nowAt = i),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _Caption(
                    title: 'THEN',
                    when: _monthYear(then.taken),
                    company: then.company,
                    onOpen: () =>
                        openMemoryPhoto(context, _loader, _photo(then)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Caption(
                    title: latestLabel,
                    when: _monthYear(now.taken),
                    company: now.company,
                    onOpen: () =>
                        openMemoryPhoto(context, _loader, _photo(now)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A few small pictures to choose from at one end: the one shown is ringed.
class _Options extends StatelessWidget {
  const _Options({
    required this.sides,
    required this.selected,
    required this.memories,
    required this.onSelect,
  });

  final List<ThenNowSide> sides;
  final int selected;
  final MemoriesController memories;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < sides.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label:
                'Photo ${i + 1} of ${sides.length}${sides[i].company == null ? '' : ', ${sides[i].company}'}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == selected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: PortraitImage(side: sides[i], memories: memories),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.title,
    required this.when,
    required this.onOpen,
    this.company,
  });

  final String title, when;

  /// Who is in this picture ("On their own", "With Dev").
  final String? company;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.ink48,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(when, style: textTheme.titleMedium),
              if (company != null)
                Text(
                  company!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'See the photo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two pictures one over the other: "then" on the left of the divider, "now" on the right.
class _Compare extends StatelessWidget {
  const _Compare({
    required this.then,
    required this.now,
    required this.latestLabel,
    required this.split,
    required this.memories,
    required this.onSet,
  });

  final ThenNowSide then, now;
  final String latestLabel;
  final ValueNotifier<double> split;
  final MemoriesController memories;
  final ValueChanged<double> onSet;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSet(d.localPosition.dx / w),
          onHorizontalDragStart: (d) => onSet(d.localPosition.dx / w),
          onHorizontalDragUpdate: (d) => onSet(d.localPosition.dx / w),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Now underneath, then over it up to the divider.
                PortraitImage(side: now, memories: memories),
                ValueListenableBuilder<double>(
                  valueListenable: split,
                  builder: (context, s, _) => ClipRect(
                    clipper: _LeftOf(s),
                    child: PortraitImage(side: then, memories: memories),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: split,
                  builder: (context, s, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: s * w - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const ColoredBox(color: Colors.white),
                      ),
                      Positioned(
                        left: s * w - 20,
                        top: box.maxHeight / 2 - 20,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _Tag(
                          label: 'THEN · ${_monthYear(then.taken)}',
                          opacity: ((s - 0.18) / 0.2).clamp(0.0, 1.0),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _Tag(
                          label: '$latestLabel · ${_monthYear(now.taken)}',
                          opacity: ((0.82 - s) / 0.2).clamp(0.0, 1.0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  _LeftOf(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.share != share;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.opacity});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
