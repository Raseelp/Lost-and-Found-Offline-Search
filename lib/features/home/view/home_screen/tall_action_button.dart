part of '../home_screen.dart';

class _TallActionButton extends StatelessWidget {
  const _TallActionButton({
    required this.action,
    required this.label,
    required this.main,
  });

  final _BarAction action;
  final String label;

  /// The main action is a solid white button; the other is a soft one.
  final bool main;

  @override
  Widget build(BuildContext context) {
    final foreground = main ? AppColors.primary : AppColors.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: main
                ? AppColors.onPrimary
                : AppColors.onPrimary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(_chipHeight / 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 18, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
