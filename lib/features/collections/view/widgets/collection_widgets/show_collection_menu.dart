part of '../collection_widgets.dart';

/// Long-press menu for a collection card. Every collection can be edited, hidden or deleted, and a built-in that has
/// been edited can also be reset.
void showCollectionMenu(
  BuildContext context,
  SmartCollection collection,
  CollectionsController controller,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
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
                child: Text(collection.name, style: Theme.of(context).textTheme.titleSmall),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              _MenuRow(
                icon: Icons.edit_outlined,
                label: 'Rename or change',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showEditCollectionSheet(context, collection, controller);
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.folder_zip_outlined,
                label: 'Export as zip',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openExportZip(context, select: {ExportController.collectionKey(collection.id)});
                },
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.visibility_off_outlined,
                label: 'Hide',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.hideCollection(collection.id);
                },
              ),
              if (collection.isBuiltIn && controller.isEdited(collection.id)) ...[
                const Divider(height: 1, color: AppColors.dividerSoft),
                _MenuRow(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset to default',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.resetBuiltIn(collection.id);
                  },
                ),
              ],
              const Divider(height: 1, color: AppColors.dividerSoft),
              _MenuRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showConfirmDialog(
                    context,
                    title: 'Delete this collection?',
                    message: collection.isBuiltIn
                        ? 'It comes off your list. You can bring it back any time from Settings, under "Restore default collections".'
                        : 'Only the collection goes - your photos and videos are untouched.',
                    confirmLabel: 'Delete',
                    onConfirm: () => controller.deleteCollection(collection.id),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Edits [collection] in the same sheet that makes a new one (see [showCollectionSheet]), filled in as the collection
/// is now.
Future<void> showEditCollectionSheet(
  BuildContext context,
  SmartCollection collection,
  CollectionsController controller,
) => showCollectionSheet(context, controller, editing: collection);
