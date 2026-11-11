part of '../settings_screen.dart';

/// A one-line banner at the top of Notifications. It shows while a notification is on and the phone has notifications
/// off for the app. It is not a setting: the switches below stay as the person left them, and nothing can come until
/// this is allowed. The same permission has a row under Permissions, at the top of this screen.
class _NotificationsOffBanner extends StatelessWidget {
  const _NotificationsOffBanner();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GetBuilder<SettingsController>(
      builder: (native) => GetBuilder<MemoriesController>(
        builder: (memories) => GetBuilder<StoriesController>(
          builder: (stories) {
            final wanted =
                memories.settings.enabled ||
                stories.reminderEnabled ||
                native.indexNudgeEnabled;
            if (!wanted || native.backgroundNotificationsGranted) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.base,
                    right: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_off_outlined,
                        size: 18,
                        color: AppColors.ink48,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notifications are off',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.ink80,
                                ),
                              ),
                              Text(
                                'Turn on notifications to get your daily memory, stories note and indexing reminder.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.ink48,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () async {
                          await native.requestBackgroundScanPermission(
                            purpose: 'send your daily memory and your notes',
                          );
                          await memories.loadSettings();
                        },
                        child: const Text('Turn on'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
