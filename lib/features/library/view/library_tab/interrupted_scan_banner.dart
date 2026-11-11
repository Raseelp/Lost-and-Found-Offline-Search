part of '../library_tab.dart';

/// Shown in place of the usual scan buttons when a scan was still going the last time the app process existed but
/// is not any more. See NativeController._checkForInterruptedScan for how that is detected. Resuming picks up where
/// it left off, because embedImages skips whatever it already finished, by hash, so this is a one-tap fix rather
/// than a full rescan.
class _InterruptedScanBanner extends StatelessWidget {
  const _InterruptedScanBanner({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_outline_rounded,
            size: 17,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Indexing was interrupted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.ink80,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Pick up right where it left off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: controller.dismissInterruptedScan,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.ink48,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          InkWell(
            onTap: controller.resumeInterruptedScan,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Resume',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
