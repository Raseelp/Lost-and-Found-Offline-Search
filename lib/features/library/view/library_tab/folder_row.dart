part of '../library_tab.dart';

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.controller});

  final IndexedFolder folder;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.pearl,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18, color: AppColors.ink48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.path.isEmpty ? 'Unknown' : folder.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${folder.embedded} embeddings',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => showConfirmDialog(
                context,
                title: 'Remove this folder?',
                message:
                    'This forgets everything indexed from "${folder.path}".',
                confirmLabel: 'Remove',
                onConfirm: () => controller.deleteFolderById(id: folder.id),
              ),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.ink48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
