part of '../export_zip_screen.dart';

/// What the screen shows when the zip is made. Files in Downloads have a media address, and anything else went to a
/// folder the person chose.
class _DoneView extends StatelessWidget {
  const _DoneView({super.key, required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final s = c.status;
    final textTheme = Theme.of(context).textTheme;
    final inDownloads =
        s.results.isEmpty || s.results.first.uri.startsWith('content://media/');
    final saved = inDownloads
        ? 'Downloads › Lost & Found'
        : (c.savedLabel ?? 'the folder you chose');
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          const ZipDoneMark(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            s.results.length > 1
                ? 'Your ${s.results.length} zips are ready'
                : 'Your zip is ready',
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Saved in $saved',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.ink80),
          ),
          const SizedBox(height: AppSpacing.lg),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in s.results)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_zip_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          zipBytes(r.bytes),
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.ink48,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (s.skipped > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${s.skipped} ${s.skipped == 1 ? 'file' : 'files'} could not be read completely and ${s.skipped == 1 ? 'is' : 'are'} marked in the list.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: s.results.length > 1 ? 'Share the zips' : 'Share',
              enabled: true,
              onTap: () => ExportService().shareZips([
                for (final r in s.results) r.uri,
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (inDownloads)
                TextButton(
                  onPressed: ExportService().openDownloads,
                  child: const Text('Show in Downloads'),
                ),
              TextButton(
                onPressed: c.another,
                child: const Text('Make another'),
              ),
              TextButton(
                onPressed: () {
                  c.another();
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
