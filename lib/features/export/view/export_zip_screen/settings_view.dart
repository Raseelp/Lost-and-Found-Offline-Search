part of '../export_zip_screen.dart';

/// Name, where it goes, how it is split and what is inside. It is a page of its own after the albums are chosen, so
/// none of it can be missed before the zip is made. Only a zip big enough to be split gets the splitting controls.
class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = c.selectedAlbums.map((a) => a.name).toList();
    final shown = names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')} and ${names.length - 3} more';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
                onPressed: () => c.setStep(0),
              ),
              Expanded(
                child: Text('Zip settings', style: textTheme.titleLarge),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              AppSpacing.base,
            ),
            children: [
              Text(
                'Making a zip of $shown.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink80,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _ZipFileCard(c: c),
              const SizedBox(height: AppSpacing.md),
              if (c.canSplit) ...[
                _SplitCard(c: c),
                const SizedBox(height: AppSpacing.md),
              ] else if (c.selected.isNotEmpty && !c.loadingAny) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    'It is small (about ${zipBytes(c.totalBytes)}), so it will be one zip file.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _InsideCard(c: c),
            ],
          ),
        ),
        _SummaryBar(c: c, settings: true),
      ],
    );
  }
}
