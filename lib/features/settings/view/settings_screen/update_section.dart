part of '../settings_screen.dart';

/// The Update section at the top of Settings. It is there from the moment a newer version is found until the app is
/// updated, also after "Not now" on the home screen. Tapping starts the update, or restarts the app once it is ready.
class _UpdateSection extends StatelessWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<UpdateController>()) return const SizedBox.shrink();
    return GetBuilder<UpdateController>(
      builder: (update) {
        if (!update.pending) return const SizedBox.shrink();
        final (title, subtitle, onTap) = switch (update.stage) {
          UpdateStage.downloading => ('Downloading the update', 'The update is on its way. You can keep using the app.', null),
          UpdateStage.downloaded => ('Update ready', 'The update is ready. Tap to restart the app and finish.', update.restart),
          _ => ('Update available', 'A new version of Lost & Found is ready. Tap to update.', update.accept),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _GroupLabel('Update'),
            _GroupCard(
              children: [
                _TapRow(
                  icon: Icons.system_update_rounded,
                  title: title,
                  subtitle: subtitle,
                  chevron: onTap != null,
                  dot: true,
                  onTap: onTap,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        );
      },
    );
  }
}
