part of '../settings_screen.dart';

/// The face controls that are not shown, because their defaults are the best settings. To bring them back, add
/// `..._expertFaceRows(context, faces, st, models)` to the People section. They call [FacesController] members such
/// as `setStrictness`, `setRefine`, `setThorough`, `retune`, `regroup` and `selectModel`. The grouping strictness
/// applies when "Regroup now" runs.
// ignore: unused_element
List<Widget> _expertFaceRows(
  BuildContext context,
  FacesController faces,
  FaceStatus status,
  FaceModels? models,
) {
  final textTheme = Theme.of(context).textTheme;

  Widget chips(String kind) {
    final list = models?.ofKind(kind) ?? const <FaceModelInfo>[];
    if (list.isEmpty) {
      return Text(
        'none installed',
        style: textTheme.bodySmall?.copyWith(color: AppColors.danger),
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final m in list)
          ChoiceChip(
            label: Text(
              '${m.name}  ${(m.sizeBytes / 1048576).toStringAsFixed(0)} MB',
            ),
            selected: m.selected,
            onSelected: (_) => faces.selectModel(m),
          ),
      ],
    );
  }

  return [
    SheetRow(
      icon: Icons.auto_fix_high_rounded,
      label: 'Regroup now',
      subtitle:
          'Sorts the faces into people again. Names and your edits are kept',
      onTap: faces.regroup,
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Text(
        'Models',
        style: textTheme.labelMedium?.copyWith(color: AppColors.ink48),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Finds faces', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          chips('detector'),
          const SizedBox(height: AppSpacing.md),
          Text('Tells people apart', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          chips('embedder'),
        ],
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Text(
        'Grouping',
        style: textTheme.labelMedium?.copyWith(color: AppColors.ink48),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'strict', label: Text('Strict')),
            ButtonSegment(value: 'balanced', label: Text('Balanced')),
            ButtonSegment(value: 'loose', label: Text('Loose')),
          ],
          selected: {status.strictness},
          onSelectionChanged: (s) => faces.setStrictness(s.first),
        ),
      ),
    ),
    SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      title: Text(
        'Recognise small and blurry faces',
        style: textTheme.bodyMedium,
      ),
      subtitle: Text(
        'A second pass after the clear faces are done, matching the rest to the same people.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
      value: status.refine,
      onChanged: (v) => faces.setRefine(v),
    ),
    SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      title: Text('Search harder for small faces', style: textTheme.bodyMedium),
      subtitle: Text(
        'Slower. Applies to photos scanned from now on.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
      value: status.thorough,
      onChanged: (v) => faces.setThorough(v),
    ),
    SheetRow(
      icon: Icons.speed_rounded,
      label: 'Speed test',
      subtitle: status.tuning ?? 'Runs once, at the start of the next scan',
      onTap: faces.retune,
    ),
  ];
}
