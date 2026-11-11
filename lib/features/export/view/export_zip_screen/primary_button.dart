part of '../export_zip_screen.dart';

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool enabled, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : .45,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
