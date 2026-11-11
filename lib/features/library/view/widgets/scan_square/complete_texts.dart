part of '../scan_square.dart';

/// What a finished scan says, under the chip.
class _CompleteTexts extends StatelessWidget {
  const _CompleteTexts({super.key, required this.summary});

  final ScanChipSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text('Scan complete', style: textTheme.titleMedium),
            const SizedBox(height: 2),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: summary.indexed),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '$v indexed and searchable',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.ink80),
              ),
            ),
            if (summary.people > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${summary.people} ${summary.people == 1 ? 'person' : 'people'} found',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.faceAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (summary.failed > 0) ...[
              const SizedBox(height: 2),
              Text(
                "${summary.failed} couldn't be read",
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
