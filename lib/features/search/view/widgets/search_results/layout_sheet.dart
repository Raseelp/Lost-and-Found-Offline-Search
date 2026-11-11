part of '../search_results.dart';

class _LayoutSheet extends StatelessWidget {
  const _LayoutSheet({required this.controller});

  final NativeController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  'How should results be laid out?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              for (final layout in ResultsLayout.values) ...[
                if (layout != ResultsLayout.values.first)
                  const Divider(height: 1, color: AppColors.dividerSoft),
                _LayoutOption(
                  layout: layout,
                  selected: controller.resultsLayout == layout,
                  onTap: () {
                    controller.setResultsLayout(layout);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
