part of '../search_results.dart';

class _LayoutOption extends StatelessWidget {
  const _LayoutOption({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final ResultsLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              _layoutIcon(layout),
              size: 18,
              color: selected ? AppColors.primary : AppColors.ink48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                _layoutLabel(layout),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

String _layoutLabel(ResultsLayout layout) {
  switch (layout) {
    case ResultsLayout.list:
      return 'List - one large preview per row';
    case ResultsLayout.grid2:
      return 'Grid - 2 across';
    case ResultsLayout.grid3:
      return 'Grid - 3 across';
    case ResultsLayout.grid4:
      return 'Grid - 4 across';
    case ResultsLayout.bento:
      return 'Bento - varied tile sizes';
  }
}
