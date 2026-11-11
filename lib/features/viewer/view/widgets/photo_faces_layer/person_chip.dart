part of '../photo_faces_layer.dart';

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photos = person.photoCount;
    return GestureDetector(
      onTap: onTap,
      child: _Glass(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xs + 2, AppSpacing.xs + 2, AppSpacing.md, AppSpacing.xs + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaceAvatar(faceId: person.coverFaceId, size: 40),
            const SizedBox(width: AppSpacing.md - 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name ?? 'Unnamed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(color: FacePalette.white),
                  ),
                  Text(
                    photos == 1 ? '1 photo' : '$photos photos',
                    style: textTheme.bodySmall?.copyWith(color: FacePalette.white.withValues(alpha: 0.72)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, size: 22, color: FacePalette.white.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }
}
