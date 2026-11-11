part of '../video_full_screen.dart';

/// A message over the video: a bold title, a quieter line under it and, for a scan result, the faces that were found,
/// overlapping at the left. Near-black, with no coloured edge or icon.
class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.data});

  final _ToastData data;

  static const double _face = 34;
  static const double _overlap = 20;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const surface = AppColors.mediaSurface;
    final faces = data.faces.take(3).toList();

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: EdgeInsets.fromLTRB(
        faces.isEmpty ? AppSpacing.base : AppSpacing.md,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (faces.isNotEmpty) ...[
            SizedBox(
              width: _face + (faces.length - 1) * (_face - _overlap) + 4,
              height: _face + 4,
              child: Stack(
                children: [
                  for (var i = 0; i < faces.length; i++)
                    Positioned(
                      left: i * (_face - _overlap),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: surface,
                          shape: BoxShape.circle,
                        ),
                        child: FaceAvatar(faceId: faces[i], size: _face),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.onMedia,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (data.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.onMedia.withValues(alpha: 0.66),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
