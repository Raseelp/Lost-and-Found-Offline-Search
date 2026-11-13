part of '../library_tab.dart';

/// A row of choices, all in view, one tap to pick. It is used for what to index and where to look. [tinted] is for
/// putting it on a parchment background, where it is white with a thin edge so it still stands out.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.tinted = false,
  });

  final List<T> options;
  final T value;
  final String Function(T option) labelOf;
  final ValueChanged<T> onChanged;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tinted ? AppColors.canvas : AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: tinted ? Border.all(color: AppColors.hairline) : null,
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                label: labelOf(option),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (option != value) onChanged(option);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: option == value
                          ? (tinted ? AppColors.parchment : AppColors.canvas)
                          : AppColors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: option == value
                            ? AppColors.hairline
                            : AppColors.transparent,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labelOf(option),
                        maxLines: 1,
                        style: textTheme.bodySmall?.copyWith(
                          color: option == value
                              ? AppColors.primary
                              : AppColors.ink80,
                          fontWeight: option == value
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
