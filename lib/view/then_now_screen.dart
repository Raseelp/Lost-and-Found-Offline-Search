import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/motion.dart';
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
/// both, so the change is what you see. Under it, every photo from each end to choose from (Then or Now, then a
/// row that scrolls like a wheel: the one in the middle is the one compared).
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
              const SizedBox(height: AppSpacing.lg),
              _Picker(
                then: found.thenOptions,
                now: found.nowOptions,
                thenAt: _thenAt.clamp(0, found.thenOptions.length - 1),
                nowAt: _nowAt.clamp(0, found.nowOptions.length - 1),
                latestLabel: latestLabel,
                memories: _memories,
                onPick: (isThen, i) => setState(() => isThen ? _thenAt = i : _nowAt = i),
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

/// Then | Now, and under it that end's photos in a row that scrolls like a wheel: the one in the middle is
/// larger, ringed and compared, the others smaller and fainter toward the edges; its date and who is in it
/// under it. A light tick as each one reaches the middle. A swipe lets the row run on and slow down by itself,
/// landing on the photo nearest to where it would have stopped.
class _Picker extends StatefulWidget {
  const _Picker({
    required this.then,
    required this.now,
    required this.thenAt,
    required this.nowAt,
    required this.latestLabel,
    required this.memories,
    required this.onPick,
  });

  final List<ThenNowSide> then, now;
  final int thenAt, nowAt;
  final String latestLabel;
  final MemoriesController memories;
  final void Function(bool isThen, int index) onPick;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  static const double _item = 64;

  // Then (true) or the latest (false): which end the row is choosing for.
  bool _isThen = true;
  PageController? _row;
  double _fraction = 0.2;

  // The photo in the middle of the row right now. While the row runs on it is only ringed and named: the
  // comparison changes once the row slows (a full picture to load for every photo it passes would stutter).
  int? _centre;
  Timer? _settle;

  void _passing(int i) {
    HapticFeedback.selectionClick();
    setState(() => _centre = i);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 140), _pick);
  }

  void _pick() {
    _settle?.cancel();
    final i = _centre;
    if (i != null && mounted && i != (_isThen ? widget.thenAt : widget.nowAt)) widget.onPick(_isThen, i);
  }

  // A new row for each end, opening on the photo in use there. The old one's controller goes once that row
  // has gone (it is still attached for the rest of this frame).
  void _newRow() {
    final old = _row;
    _settle?.cancel();
    _centre = null;
    _row = PageController(viewportFraction: _fraction, initialPage: _isThen ? widget.thenAt : widget.nowAt);
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Each picture takes the same width whatever the screen's.
    final width = MediaQuery.sizeOf(context).width - AppSpacing.xl * 2;
    final fraction = (_item / width).clamp(0.1, 0.5);
    if (_row == null || fraction != _fraction) {
      _fraction = fraction;
      _newRow();
    }
  }

  @override
  void didUpdateWidget(covariant _Picker old) {
    super.didUpdateWidget(old);
    // Chosen from somewhere else: the row's own choice no longer stands.
    final now = _isThen ? widget.thenAt : widget.nowAt;
    if (now != (_isThen ? old.thenAt : old.nowAt) && now != _centre) {
      _settle?.cancel();
      _centre = null;
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _row?.dispose();
    super.dispose();
  }

  void _choose(bool isThen) {
    if (isThen == _isThen) return;
    // A photo still settling on this end is kept before the row changes to the other.
    _pick();
    HapticFeedback.selectionClick();
    setState(() {
      _isThen = isThen;
      _newRow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sides = _isThen ? widget.then : widget.now;
    final at = (_centre ?? (_isThen ? widget.thenAt : widget.nowAt)).clamp(0, sides.length - 1);
    final row = _row!;
    final shown = sides[at.clamp(0, sides.length - 1)];
    final company = shown.company;
    return Column(
      children: [
        _Segments(
          labels: ['Then', widget.latestLabel == 'NOW' ? 'Now' : 'Latest'],
          counts: [widget.then.length, widget.now.length],
          first: _isThen,
          onChanged: _choose,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _item + 16,
          child: NotificationListener<ScrollEndNotification>(
            // Come to rest: the comparison catches up at once.
            onNotification: (_) {
              _pick();
              return false;
            },
            child: PageView.builder(
              key: ValueKey(_isThen),
              controller: row,
              pageSnapping: false,
              physics: _WheelPhysics(fraction: _fraction),
              // The ring and shadow of the one in the middle are not cut off.
              clipBehavior: Clip.none,
              itemCount: sides.length,
              onPageChanged: _passing,
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: row,
                builder: (context, child) {
                  final page = row.hasClients && row.position.haveDimensions ? (row.page ?? at.toDouble()) : at.toDouble();
                  final d = (i - page).abs().clamp(0.0, 3.0);
                  return Center(
                    child: Opacity(
                      opacity: 1 - d * 0.22,
                      child: Transform.scale(scale: 1 - d * 0.16, child: child),
                    ),
                  );
                },
                child: Semantics(
                  button: true,
                  selected: i == at,
                  label: '${_monthYear(sides[i].taken)}${sides[i].company == null ? '' : ', ${sides[i].company}'}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => calm(context)
                        ? row.jumpToPage(i)
                        : row.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _item - 8,
                      height: _item - 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: i == at
                            ? [
                                const BoxShadow(color: AppColors.canvas, spreadRadius: 2),
                                const BoxShadow(color: AppColors.primary, spreadRadius: 4),
                                BoxShadow(color: AppColors.shadow.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PortraitImage(side: sides[i], memories: widget.memories, small: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Changes at once (a cross-fade could meet itself coming back on a quick Then, Now, Then).
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _monthYear(shown.taken),
                style: textTheme.bodyMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
              ),
              if (company != null) TextSpan(text: ' \u00b7 $company'),
            ],
          ),
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.ink48),
        ),
      ],
    );
  }
}

/// For the row of photos: a swipe runs on and slows by itself, as a list does, but always comes to rest on a
/// photo, the one nearest to where it would have stopped. Let go without a swipe, it settles gently onto the
/// nearest one.
class _WheelPhysics extends ScrollPhysics {
  const _WheelPhysics({required this.fraction, super.parent});

  /// The width of one photo, as a part of the row's.
  final double fraction;

  @override
  _WheelPhysics applyTo(ScrollPhysics? ancestor) => _WheelPhysics(fraction: fraction, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Past an end: the usual way back.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final extent = position.viewportDimension * fraction;
    if (extent <= 0) return super.createBallisticSimulation(position, velocity);
    final tolerance = toleranceFor(position);
    // Where it would come to rest by itself, and the photo nearest to that.
    final glide = super.createBallisticSimulation(position, velocity);
    final natural = glide?.x(double.infinity) ?? position.pixels;
    final target = ((natural / extent).round() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (velocity.abs() < tolerance.velocity && (target - position.pixels).abs() < tolerance.distance) return null;
    // Not enough to leave the photo it is on: a soft spring back onto it.
    if ((position.pixels / extent).round() * extent == target) {
      return _Landing(SpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance), target);
    }
    // Otherwise it glides as it would have, slowed just enough to stop on the photo.
    return _Landing(
      FrictionSimulation.through(position.pixels, target, velocity, tolerance.velocity * velocity.sign),
      target,
    );
  }
}

// A glide or spring that ends exactly on [target]: either stops once it is within a pixel of it.
class _Landing extends Simulation {
  _Landing(this.glide, this.target) : super(tolerance: glide.tolerance);

  final Simulation glide;
  final double target;

  @override
  double x(double time) => glide.isDone(time) ? target : glide.x(time);

  @override
  double dx(double time) => glide.isDone(time) ? 0 : glide.dx(time);

  @override
  bool isDone(double time) => glide.isDone(time);
}

/// Two choices side by side in a soft track, the chosen one on a white pill that slides between them.
class _Segments extends StatelessWidget {
  const _Segments({required this.labels, required this.counts, required this.first, required this.onChanged});

  final List<String> labels;
  final List<int> counts;
  final bool first;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 232,
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: first ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: (i == 0) == first,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i == 0),
                      child: Center(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: labels[i]),
                              TextSpan(
                                text: '  ${counts[i]}',
                                style: TextStyle(color: AppColors.ink48.withValues(alpha: (i == 0) == first ? 1 : 0.7)),
                              ),
                            ],
                          ),
                          style: textTheme.labelLarge?.copyWith(
                            color: (i == 0) == first ? AppColors.ink : AppColors.ink48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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
                        child: const ColoredBox(color: AppColors.onMedia),
                      ),
                      Positioned(
                        left: s * w - 20,
                        top: box.maxHeight / 2 - 20,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.onMedia,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadow.withValues(alpha: 0.25),
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
          color: AppColors.scrim.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onMedia,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
