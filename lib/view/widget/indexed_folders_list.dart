import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:twentyonevision/controllers/native_controller.dart';
import 'package:twentyonevision/models/indexed_folder_model.dart';
import 'package:twentyonevision/utils/app_colors.dart';

class IndexedFoldersList extends StatelessWidget {
  const IndexedFoldersList({
    super.key,
    this.compact = false,
    this.maxVisibleItems,
  });

  final bool compact;
  final int? maxVisibleItems;

  @override
  Widget build(BuildContext context) {
    final NativeController nativeController = Get.find();
    return GetBuilder<NativeController>(
      init: nativeController,
      builder: (controller) {
        final folders = controller.allIndexedFoldersList;
        final visibleFolders = maxVisibleItems == null
            ? folders
            : folders.take(maxVisibleItems!).toList();
        final hiddenCount = folders.length - visibleFolders.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Indexed Folders',
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.titleMedium
                                    : Theme.of(context).textTheme.titleLarge)
                                ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: compact ? 2 : 4),
                      Text(
                        folders.isEmpty
                            ? 'Start by indexing your phone or selecting a folder.'
                            : compact
                            ? 'Latest places ready for local search.'
                            : 'Manage everything you have already added to search.',
                        maxLines: compact ? 1 : null,
                        overflow: compact
                            ? TextOverflow.ellipsis
                            : TextOverflow.visible,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondoryButtonColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${folders.length} ${folders.length == 1 ? 'folder' : 'folders'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 18),
            if (folders.isEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 14 : 22),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(compact ? 20 : 28),
                  border: Border.all(
                    color: AppColors.borderColor.withValues(alpha: 0.08),
                  ),
                  boxShadow: compact
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.shadowColor.withValues(alpha: 0.4),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 40 : 52,
                      height: compact ? 40 : 52,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAccent,
                        borderRadius: BorderRadius.circular(compact ? 14 : 18),
                      ),
                      child: const Icon(
                        Icons.folder_copy_outlined,
                        color: AppColors.primarybuttonColor,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: Text(
                        compact
                            ? 'No indexed folders yet. Add one to start building your searchable library.'
                            : 'No folders indexed yet. Once you add one, progress, duration, and embedding stats will show up here.',
                        maxLines: compact ? 3 : null,
                        overflow: compact
                            ? TextOverflow.ellipsis
                            : TextOverflow.visible,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: visibleFolders.length,
                itemBuilder: (context, index) {
                  final IndexedFolder folder = visibleFolders[index];
                  return FileInfoCard(folder: folder, compact: compact);
                },
              ),
              if (hiddenCount > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAccent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$hiddenCount more indexed ${hiddenCount == 1 ? 'folder is' : 'folders are'} saved here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primarybuttonColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class FileInfoCard extends StatelessWidget {
  const FileInfoCard({super.key, required this.folder, this.compact = false});

  final IndexedFolder folder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final NativeController nativeController = Get.find();
    final progress = folder.total == 0
        ? 0.0
        : (folder.processed / folder.total).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 16),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 18),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(compact ? 20 : 28),
          border: Border.all(
            color: AppColors.borderColor.withValues(alpha: 0.08),
          ),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: AppColors.shadowColor.withValues(alpha: 0.5),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 38 : 48,
                  height: compact ? 38 : 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(compact ? 14 : 18),
                  ),
                  child: Icon(
                    Icons.folder_special_outlined,
                    size: compact ? 20 : 24,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.path,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: compact ? 13 : 14,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      SizedBox(height: compact ? 3 : 6),
                      Text(
                        '${folder.embedded} embeddings available for semantic search',
                        maxLines: compact ? 1 : null,
                        overflow: compact
                            ? TextOverflow.ellipsis
                            : TextOverflow.visible,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        nativeController.deleteFolderById(id: folder.id);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.dangerColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: compact ? 10 : 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: compact ? 6 : 10,
                value: progress,
                backgroundColor: AppColors.surfaceAccent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primarybuttonColor,
                ),
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Row(
              children: [
                Text(
                  '${folder.processed}/${folder.total} files processed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!nativeController.isScanning &&
                    folder.processed > 0 &&
                    folder.processed < folder.total) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· stopped early',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatPill(
                    icon: Icons.image_search_outlined,
                    label: '${folder.embedded} embedded',
                  ),
                  _StatPill(
                    icon: Icons.fast_forward_outlined,
                    label: '${folder.skipped} skipped',
                  ),
                  _StatPill(
                    icon: Icons.schedule_outlined,
                    label: nativeController.formatDuration(
                      milliseconds: folder.elapsedMs,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primarybuttonColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
