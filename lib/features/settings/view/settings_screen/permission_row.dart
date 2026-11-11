part of '../settings_screen.dart';

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});

  final String label;
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    final isGranted = granted == true;
    final color = granted == null
        ? AppColors.ink48
        : (isGranted ? AppColors.primary : AppColors.danger);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            granted == null
                ? Icons.hourglass_empty_rounded
                : (isGranted
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined),
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          Text(
            granted == null
                ? 'Checking...'
                : (isGranted ? 'Granted' : 'Not granted'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
