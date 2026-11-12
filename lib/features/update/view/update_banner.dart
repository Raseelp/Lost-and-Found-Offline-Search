import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/update/controllers/update_controller.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';

/// A quiet card under the title of the home screen when a newer version of the app is waiting in Google Play: offer it,
/// show it downloading, and ask to restart once it is ready. It is not there the rest of the time.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<UpdateController>()) return const SizedBox.shrink();
    return GetBuilder<UpdateController>(
      builder: (update) => SmoothSize(
        child: update.visible
            ? Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
                child: _UpdateCard(update: update),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.update});

  final UpdateController update;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stage = update.stage;
    final (title, subtitle) = switch (stage) {
      UpdateStage.downloading => ('Downloading the update', null),
      UpdateStage.downloaded => ('Update ready', 'Restart the app to finish.'),
      _ => ('Update available', 'A new version of Lost & Found is ready.'),
    };
    final actions = _actions(stage);
    final big = MediaQuery.textScalerOf(context).scale(14) > 18;

    final message = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.system_update_rounded, size: 22, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              if (subtitle != null) Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.ink48)),
              if (stage == UpdateStage.downloading) ...[
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: update.progress,
                    minHeight: 3,
                    color: AppColors.primary,
                    backgroundColor: AppColors.parchment,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions != null && !big) ...[const SizedBox(width: AppSpacing.sm), actions],
      ],
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.pearl,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.dividerSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.md, AppSpacing.md, AppSpacing.md),
          child: actions != null && big
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [message, const SizedBox(height: AppSpacing.sm), Align(alignment: Alignment.centerRight, child: actions)],
                )
              : message,
        ),
      ),
    );
  }

  Widget? _actions(UpdateStage stage) {
    final pill = FilledButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      shape: const StadiumBorder(),
    );
    switch (stage) {
      case UpdateStage.downloaded:
        return FilledButton(onPressed: update.restart, style: pill, child: const Text('Restart'));
      case UpdateStage.available:
        return Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: update.dismiss,
              style: TextButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: AppColors.ink48),
              child: const Text('Not now'),
            ),
            FilledButton(onPressed: update.accept, style: pill, child: const Text('Update')),
          ],
        );
      case UpdateStage.downloading:
      case UpdateStage.none:
        return null;
    }
  }
}
