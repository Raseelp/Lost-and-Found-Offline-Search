part of '../collection_widgets.dart';

/// Asks for the name of a new or edited collection, and the phrase to search when it is not already known. [onSave]
/// gets the finished values. Its query already has any "@name" mentions stripped out, the same as the search's own
/// queryWithoutMention, and those people come separately in [onSave]'s third argument.
Future<void> showSaveCollectionSheet(
  BuildContext context, {
  String? title,
  String initialName = '',
  String? initialQuery,
  bool showQuery = false,
  required Future<void> Function(String name, String query, List<int> personIds) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _SaveCollectionSheet(
      title: title ?? 'Save as collection',
      initialName: initialName,
      initialQuery: initialQuery,
      showQuery: showQuery,
      onSave: onSave,
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
