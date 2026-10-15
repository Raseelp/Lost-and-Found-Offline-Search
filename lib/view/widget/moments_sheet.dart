import 'package:flutter/material.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

/// "Your story": the good moments of the people on the timeline, year by year, the ones that matter
/// most of each year. Tapping one goes there. By default it is the inner circle (the named people
/// who are photographed the most); the switch at the top widens it to everyone.
Future<void> showMomentsSheet(
  BuildContext context, {
  required TimelineLayout Function(bool everyone) layoutFor,
  required bool everyone,
  required ValueChanged<bool> onEveryoneChanged,
  required ValueChanged<int> onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => _MomentsSheet(
      layoutFor: layoutFor,
      initialEveryone: everyone,
      onEveryoneChanged: onEveryoneChanged,
      onJump: (month) {
        Navigator.of(sheet).pop();
        onJump(month);
      },
    ),
  );
}

// The line of the sheet's timeline: where it is across, and how far the content starts from the edge.
const double _railX = 9;
const double _railGutter = 30;

class _MomentsSheet extends StatefulWidget {
  const _MomentsSheet({
    required this.layoutFor,
    required this.initialEveryone,
    required this.onEveryoneChanged,
    required this.onJump,
  });

  final TimelineLayout Function(bool everyone) layoutFor;
  final bool initialEveryone;
  final ValueChanged<bool> onEveryoneChanged;
  final ValueChanged<int> onJump;

  @override
  State<_MomentsSheet> createState() => _MomentsSheetState();
}

class _MomentsSheetState extends State<_MomentsSheet> {
  late bool _everyone = widget.initialEveryone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final story = widget.layoutFor(_everyone).story();

    // By year, oldest first: a story reads from the start.
    final years = <int, List<StoryEntry>>{};
    for (final e in story) {
      years.putIfAbsent(e.month ~/ 12, () => []).add(e);
    }
    final order = years.keys.toList()..sort();
    // The most important of each year is starred.
    final starred = <StoryEntry>{
      for (final list in years.values)
        (list.toList()..sort((a, b) => b.importance.compareTo(a.importance)))
            .first,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            MediaQuery.of(context).padding.bottom + AppSpacing.xxl,
          ),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Your story', style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The good moments, year by year. Tap one to go there.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            _WhoSwitch(
              everyone: _everyone,
              onChanged: (value) {
                setState(() => _everyone = value);
                widget.onEveryoneChanged(value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                _everyone
                    ? 'Everyone on the timeline.'
                    : 'The people you have named who are photographed the most. Name more people to see theirs.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink48,
                  height: 1.4,
                ),
              ),
            ),
            if (order.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Column(
                  children: [
                    const Icon(
                      Icons.auto_awesome_outlined,
                      size: 32,
                      color: AppColors.ink48,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Moments show up as your photos fill in.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink80,
                      ),
                    ),
                  ],
                ),
              ),
            if (order.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                // A timeline of its own: a line down the side, a dot for each year and each moment.
                child: Stack(
                  children: [
                    Positioned(
                      left: _railX - 1,
                      top: 8,
                      bottom: 8,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: AppColors.hairline,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: _railGutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < order.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.lg),
                            _YearHeader(year: order[i]),
                            const SizedBox(height: AppSpacing.sm),
                            for (final e in years[order[i]]!) ...[
                              _StoryRow(
                                entry: e,
                                starred: starred.contains(e),
                                onTap: () => widget.onJump(e.month),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        ],
                      ),
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

/// Inner circle or everyone.
class _WhoSwitch extends StatelessWidget {
  const _WhoSwitch({required this.everyone, required this.onChanged});

  final bool everyone;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget option(String label, bool value) {
      final selected = everyone == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.canvas : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? AppColors.hairline : Colors.transparent,
                ),
              ),
              child: Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: selected ? AppColors.primary : AppColors.ink80,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [option('Inner circle', false), option('Everyone', true)],
      ),
    );
  }
}

/// A year of the timeline, with its big dot on the line.
class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: _railX - _railGutter - 7,
          top: 6,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.canvas, width: 3),
            ),
          ),
        ),
        Text(
          '$year',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.entry,
    required this.starred,
    required this.onTap,
  });

  final StoryEntry entry;
  final bool starred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final faces = entry.people.take(3).toList();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Its dot on the line: gold for the one that matters most of its year.
        Positioned(
          left: _railX - _railGutter - 5,
          top: 22,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: starred ? const Color(0xFFD59A3E) : AppColors.canvas,
              shape: BoxShape.circle,
              border: Border.all(
                color: starred ? AppColors.canvas : AppColors.primary,
                width: starred ? 2 : 2,
              ),
            ),
          ),
        ),
        _card(context, textTheme, faces),
      ],
    );
  }

  Widget _card(BuildContext context, TextTheme textTheme, List<Person> faces) {
    return Material(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              // Their faces, overlapping a little.
              SizedBox(
                width: 36.0 + (faces.length - 1) * 22,
                height: 36,
                child: Stack(
                  children: [
                    for (var i = 0; i < faces.length; i++)
                      Positioned(
                        left: i * 22.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.parchment,
                              width: 2,
                            ),
                          ),
                          child: FaceAvatar(
                            faceId: faces[i].coverFaceId,
                            size: 36,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(entry.icon, size: 14, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Text(
                          monthLabel(entry.month),
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (starred) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFD59A3E),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _names(entry.people, entry.line),
                      style: textTheme.bodyMedium?.copyWith(height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.ink48),
            ],
          ),
        ),
      ),
    );
  }

  // "Anna and Dev: first photo together" for a pair, the line itself for one person or a group
  // (which already says who).
  static String _names(List<Person> people, String line) {
    if (people.length == 2 &&
        line == 'First photo together' &&
        people.every((p) => p.name != null)) {
      return '${people[0].name} and ${people[1].name}  ·  first photo together';
    }
    if (people.length == 1 && people[0].name != null) {
      return '${people[0].name}  ·  $line';
    }
    return line;
  }
}
