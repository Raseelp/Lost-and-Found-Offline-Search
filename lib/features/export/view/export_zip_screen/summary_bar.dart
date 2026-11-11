part of '../export_zip_screen.dart';

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.c, required this.settings});

  final ExportController c;

  /// On the settings step the button makes the zip and the notes about it show. On the first step it goes on to the
  /// settings.
  final bool settings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final chosen = c.selected.isNotEmpty;
    final loading = chosen && c.loadingAny;
    final parts = settings ? c.partSizes.length : 0;
    final notes = <(String, bool)>[
      if (settings && chosen && !loading && c.repeatedFiles > 0)
        (
          '${c.repeatedFiles} ${c.repeatedFiles == 1 ? 'file is' : 'files are'} in more than one chosen album, so ${c.repeatedFiles == 1 ? 'it is' : 'they are'} in the zip more than once (${zipBytes(c.repeatedBytes)} extra).',
          false,
        ),
      if (settings && chosen && !loading && c.unreadable > 0)
        (
          '${c.unreadable} ${c.unreadable == 1 ? 'file cannot' : 'files cannot'} be read and will be left out.',
          false,
        ),
      if (settings && chosen && !loading && c.tooBigForDownloads)
        (
          'This is more than the free space on your phone (${zipBytes(c.freeBytes)}). Choose a folder on another drive, or fewer albums.',
          true,
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                note.$1,
                style: textTheme.bodySmall?.copyWith(
                  color: note.$2 ? AppColors.danger : AppColors.ink80,
                  height: 1.35,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: !chosen
                    ? Text(
                        'Choose one or more albums',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink48,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<int>(
                            tween: IntTween(end: c.totalFiles),
                            duration: const Duration(milliseconds: 400),
                            builder: (context, files, _) => Text(
                              loading
                                  ? 'Counting… $files files'
                                  : '${c.totalImages} ${c.totalImages == 1 ? 'photo' : 'photos'}'
                                        '${c.totalVideos > 0 ? ' · ${c.totalVideos} ${c.totalVideos == 1 ? 'video' : 'videos'}' : ''}',
                              style: textTheme.titleSmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            'about ${zipBytes(c.totalBytes)} · not compressed',
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.ink48,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (settings)
                _PrimaryButton(
                  label: parts > 1 ? 'Make $parts zips' : 'Make zip',
                  enabled: c.canStart && !c.tooBigForDownloads,
                  busy: c.starting,
                  onTap: c.start,
                )
              else
                _PrimaryButton(
                  label: 'Next',
                  enabled: chosen,
                  onTap: () => c.setStep(1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
