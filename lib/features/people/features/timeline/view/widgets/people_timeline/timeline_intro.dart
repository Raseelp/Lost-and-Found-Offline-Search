part of '../people_timeline.dart';

/// Above the list, while the dates are still being read: how far it is (nothing once done).
class TimelineIntro extends StatelessWidget {
  const TimelineIntro({
    super.key,
    required this.layout,
    required this.data,
    required this.now,
    this.finished = false,
  });

  final TimelineLayout layout;
  final TimelineData data;

  /// Nothing more is coming in (the dates that could not be found out are left).
  final bool finished;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: data.done || finished || data.total == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _Reading(done: data.total - data.pending, total: data.total),
            ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.done, required this.total});

  final int done, total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading dates  ·  ${_grouped(done)} of ${_grouped(total)}',
          style: textTheme.labelMedium?.copyWith(color: AppColors.ink80),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : done / total),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppColors.hairline,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

String _grouped(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
