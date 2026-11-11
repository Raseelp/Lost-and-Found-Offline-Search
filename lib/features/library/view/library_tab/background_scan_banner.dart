part of '../library_tab.dart';

/// Asks for the permission that keeps a scan going in the background. It sets expectations rather than
/// overpromising, because background scanning can get cut short on some phones, so a big library is more reliably
/// finished with the app open.
class _BackgroundScanBanner extends StatelessWidget {
  const _BackgroundScanBanner({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 17,
                color: AppColors.ink48,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Keep this going in the background',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink80,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: controller.requestBackgroundScanPermission,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                child: const Text('Enable'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              'Big libraries index fastest with the app open - background '
              'scanning works best in short stretches.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
