part of '../library_tab.dart';

/// Shown once after the search model changed. What was indexed with the previous model cannot be searched with the
/// current one, so the index was started again and the photos need to be scanned again. People and their faces are
/// kept, as they are not part of the index.
class _ModelUpdatedBanner extends StatelessWidget {
  const _ModelUpdatedBanner({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Search model updated',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss',
                child: InkWell(
                  onTap: controller.acknowledgeModelReset,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.ink48,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Photos are now found by a smaller, more accurate model. Scan your photos once more so it can read them. People and faces are kept.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                controller.acknowledgeModelReset();
                controller.scanWholePhone
                    ? _startDeviceScan(context, controller)
                    : controller.pickAndScanFolders(isScanEntirePhone: false);
              },
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Scan again',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
