part of '../export_zip_screen.dart';

/// What the screen shows when the zip was cancelled or failed.
class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.c,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ExportController c;
  final IconData icon;
  final String title, message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          Icon(icon, size: 56, color: AppColors.ink48),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.ink80,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Back to albums',
            enabled: true,
            onTap: c.another,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () {
              c.another();
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
