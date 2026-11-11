part of '../collection_widgets.dart';

/// Long-press menu for the "On this day" card. It is not a saved search, so there is nothing to rename or change.
/// It can be exported, or taken off the tab and brought back from there. [onHidden] runs after it is hidden (the
/// memories screen closes itself).
void showOnThisDayMenu(
  BuildContext context,
  MemoriesController memories, {
  VoidCallback? onHidden,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  'On this day  ·  ${memories.today.dateLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              _MenuRow(
                icon: Icons.folder_zip_outlined,
                label: 'Export as zip',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openExportZip(
                    context,
                    select: {ExportController.memoryKey},
                  );
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.visibility_off_outlined,
                label: 'Hide',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  memories.setHidden(true);
                  onHidden?.call();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
