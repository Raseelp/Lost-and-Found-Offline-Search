part of '../tour_screen.dart';

class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: TourPalette.teal,
          elevation: 0,
          shadowColor: TourPalette.teal.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: TourPalette.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
