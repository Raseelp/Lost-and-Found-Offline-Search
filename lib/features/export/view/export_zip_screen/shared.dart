part of '../export_zip_screen.dart';

/// Opens the zip export with [select] (see [ExportController.collectionKey] and
/// [ExportController.personKey]) already ticked.
Future<void> openExportZip(
  BuildContext context, {
  Set<String> select = const {},
}) {
  if (!Get.isRegistered<ExportController>()) Get.put(ExportController());
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ExportZipScreen(select: select)));
}

/// A titled box on the parchment colour.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
