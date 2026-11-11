part of '../export_zip_screen.dart';

class _InsideCard extends StatelessWidget {
  const _InsideCard({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final albums = c.selectedAlbums;
    const shown = 4;
    Widget row(
      IconData icon,
      String text, {
      double indent = 0,
      Color? color,
      String? trailing,
    }) {
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.ink48),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
          ],
        ),
      );
    }

    return _Card(
      title: 'Inside the zip',
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final album in albums.take(shown)) ...[
              row(Icons.folder_rounded, album.name, color: AppColors.primary),
              if (!album.loaded || album.images > 0)
                row(
                  Icons.image_outlined,
                  'Images',
                  indent: 26,
                  trailing: album.loaded ? '${album.images}' : '…',
                ),
              if (!album.loaded || album.videos > 0)
                row(
                  Icons.videocam_outlined,
                  'Videos',
                  indent: 26,
                  trailing: album.loaded ? '${album.videos}' : '…',
                ),
            ],
            if (albums.length > shown)
              row(
                Icons.more_horiz_rounded,
                '${albums.length - shown} more ${albums.length - shown == 1 ? 'album' : 'albums'}',
              ),
            if (c.includeList) row(Icons.description_outlined, 'list.json'),
          ],
        ),
      ),
    );
  }
}
