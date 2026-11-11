part of '../search_results.dart';

/// The same bordered pill with a chevron as the scan-scope control, and the same sheet-with-options pattern for
/// picking, so pickers look and behave alike.
class _LayoutPickerButton extends StatelessWidget {
  const _LayoutPickerButton({required this.controller});

  final AppSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => _showLayoutPicker(context, controller),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _layoutIcon(controller.resultsLayout),
                size: 14,
                color: AppColors.ink80,
              ),
              const SizedBox(width: AppSpacing.xxs),
              const Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: AppColors.ink48,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showLayoutPicker(BuildContext context, AppSearchController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (_) => _LayoutSheet(controller: controller),
  );
}
