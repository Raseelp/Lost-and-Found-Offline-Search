import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/features/memories/models/memories.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/memories/view/widgets/memory_widgets.dart';
import 'package:lost_and_found/features/people/features/then_now/view/widgets/then_now_card.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_preview.dart';
import 'package:lost_and_found/features/people/models/person.dart';
part 'then_now_screen/month_year.dart';
part 'then_now_screen/picker.dart';
part 'then_now_screen/segments.dart';
part 'then_now_screen/caption.dart';
part 'then_now_screen/compare.dart';

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

  /// Where the divider is, as a share of the width. It sweeps in from the edge when the screen opens, to show there
  /// are two pictures, until a finger takes it.
  final ValueNotifier<double> _split = ValueNotifier(1);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _touched = false;

  /// Which of the few photos at each end is shown. The ones picked first are random, the same all day.
  late int _thenAt = widget.found.startThen, _nowAt = widget.found.startNow;

  /// The divider sweeps in once the pictures have had a moment to arrive.
  @override
  void initState() {
    super.initState();
    _intro.addListener(() {
      if (!_touched) {
        _split.value = 1 - 0.5 * Curves.easeInOutCubic.transform(_intro.value);
      }
    });
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

  /// Moves the divider to [share] of the width, with a light tick as it passes the middle.
  void _set(double share) {
    _touched = true;
    _intro.stop();
    final next = share.clamp(0.0, 1.0);
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
