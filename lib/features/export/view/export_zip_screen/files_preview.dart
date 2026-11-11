part of '../export_zip_screen.dart';

/// The zip files that will be made, as a plain list of their names and sizes, each with a bar of how full it is.
class _FilesPreview extends StatelessWidget {
  const _FilesPreview({required this.c, required this.sizes});

  final ExportController c;
  final List<int> sizes;

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = c.zipFileNames(sizes.length);
    final shown = sizes.length <= _shown ? sizes.length : _shown;
    final rest = sizes.length - shown;
    final restBytes = sizes.skip(shown).fold<int>(0, (a, b) => a + b);
    final sentence = sizes.length == 1
        ? 'You will get one zip file, about ${zipBytes(sizes.first)}.'
        : 'You will get ${sizes.length} zip files. Each one is a complete zip you can open on its own.';
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sentence, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < shown; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.folder_zip_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          names[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        zipBytes(sizes[i]),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink80,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (sizes.length > 1 && c.activeLimit > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: (sizes[i] / c.activeLimit).clamp(0.02, 1.0),
                          ),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 4,
                                backgroundColor: AppColors.hairline,
                                color: AppColors.primary.withValues(alpha: .65),
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (rest > 0)
            Text(
              'and $rest more ${rest == 1 ? 'file' : 'files'} (${zipBytes(restBytes)})',
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
        ],
      ),
    );
  }
}
