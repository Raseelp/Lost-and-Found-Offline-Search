part of '../export_zip_screen.dart';

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.selected,
    required this.onTap,
  });

  final ExportAlbum album;
  final bool selected;
  final VoidCallback onTap;

  String get _subtitle {
    if (album.loaded) {
      final parts = <String>[
        if (album.images > 0)
          '${album.images} ${album.images == 1 ? 'photo' : 'photos'}',
        if (album.videos > 0)
          '${album.videos} ${album.videos == 1 ? 'video' : 'videos'}',
      ];
      if (parts.isEmpty) return 'Nothing readable';
      return '${parts.join(' · ')} · ${zipBytes(album.bytes)}';
    }
    if (album.loading) return 'Counting…';
    return '${album.approxCount} ${album.approxCount == 1 ? 'item' : 'items'}';
  }

  Widget _avatar() {
    if (album.person != null) {
      return FaceAvatar(faceId: album.person!.coverFaceId, size: 46);
    }
    if (album.memory != null) {
      return SizedBox(
        width: 46,
        height: 46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      );
    }
    final Uint8List? cover = Get.isRegistered<CollectionsController>()
        ? Get.find<CollectionsController>().coverFor(album.collection!.id)
        : null;
    return SizedBox(
      width: 46,
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: cover != null
            ? Image.memory(cover, fit: BoxFit.cover, cacheWidth: 140)
            : ColoredBox(
                color: AppColors.parchment,
                child: Icon(
                  album.collection!.icon,
                  color: AppColors.ink48,
                  size: 22,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _subtitle,
                        key: ValueKey(_subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : AppColors.canvas,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.hairline,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: AppColors.onPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
