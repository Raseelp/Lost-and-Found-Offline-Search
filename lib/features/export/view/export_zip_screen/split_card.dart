part of '../export_zip_screen.dart';

class _SplitCard extends StatefulWidget {
  const _SplitCard({required this.c});

  final ExportController c;

  @override
  State<_SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends State<_SplitCard> {
  /// Bigger zips choose from a few sizes, and "Custom" for the slider. Smaller ones have only the slider.
  bool _custom = false;

  /// Where the slider is, as a step from its left end. It is null until touched, and then it follows the limit in force,
  /// which starts as no split at the right end.
  double? _step;

  String _label(int bytes) => bytes >= ExportController.gb
      ? '${bytes ~/ ExportController.gb} GB'
      : '${bytes ~/ ExportController.mb} MB';

  /// The range of the slider: from the smallest part worth making to the whole zip, at which it is not split. Its steps
  /// are round sizes.
  ({int min, int max, int unit, int steps}) _range(int total, bool onlySlider) {
    const mb = ExportController.mb;
    final min = onlySlider ? (total >= 200 * mb ? 50 * mb : 25 * mb) : 100 * mb;
    final max = onlySlider
        ? total
        : (total < 8 * ExportController.gb ? total : 8 * ExportController.gb);
    var unit = 5 * mb;
    for (final candidate in const [5, 10, 25, 50, 100, 250, 500]) {
      unit = candidate * mb;
      if ((max - min) / unit <= 24) break;
    }
    return (
      min: min,
      max: max,
      unit: unit,
      steps: ((max - min) / unit).ceil().clamp(1, 1000),
    );
  }

  int _bytesAt(({int min, int max, int unit, int steps}) r, double step) =>
      step.round() >= r.steps ? r.max : r.min + step.round() * r.unit;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final textTheme = Theme.of(context).textTheme;
    final total = c.totalBytes;
    final presets = c.applicablePresets;
    final onlySlider = presets.isEmpty;
    final showSlider = onlySlider || _custom;
    final range = _range(total, onlySlider);
    final sizes = c.partSizes;
    final overFat = c.activeLimit == 0 && total > 4 * ExportController.gb;
    final noSplitAtEnd = range.max >= total;

    final step =
        (_step ??
                (c.activeLimit == 0
                    ? range.steps.toDouble()
                    : ((c.activeLimit - range.min) / range.unit)
                          .clamp(0, range.steps)
                          .toDouble()))
            .clamp(0.0, range.steps.toDouble());
    final atEnd = step.round() >= range.steps;
    final sliderBytes = _bytesAt(range, step);

    return _Card(
      title: 'Split into parts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            onlySlider
                ? 'Your zip would be about ${zipBytes(total)}. Drag the slider to cut it into smaller zip files, or leave it at the right to keep one.'
                : 'Your zip would be about ${zipBytes(total)}. Choose how big each part may be, or keep one file.',
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each part is a complete zip you can open on its own.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!onlySlider)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Chip(
                  label: 'One file',
                  selected: !_custom && c.activeLimit == 0,
                  onTap: () {
                    setState(() {
                      _custom = false;
                      _step = null;
                    });
                    c.setPartLimit(0);
                  },
                ),
                for (final p in presets)
                  _Chip(
                    label: 'Parts of ${_label(p)}',
                    selected: !_custom && c.activeLimit == p,
                    onTap: () {
                      setState(() {
                        _custom = false;
                        _step = null;
                      });
                      c.setPartLimit(p);
                    },
                  ),
                _Chip(
                  label: 'Custom',
                  selected: _custom,
                  onTap: () {
                    setState(() => _custom = true);
                    c.setPartLimit(atEnd && noSplitAtEnd ? 0 : sliderBytes);
                  },
                ),
              ],
            ),
          if (showSlider) ...[
            SizedBox(height: onlySlider ? 0 : AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    atEnd && noSplitAtEnd
                        ? 'One zip, not split'
                        : 'Parts of up to ${zipBytes(sliderBytes)}',
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: step,
              min: 0,
              max: range.steps.toDouble(),
              divisions: range.steps,
              label: atEnd && noSplitAtEnd ? 'One zip' : zipBytes(sliderBytes),
              onChanged: (v) {
                setState(() => _step = v);
                final bytes = _bytesAt(range, v);
                c.setPartLimit(
                  v.round() >= range.steps && noSplitAtEnd ? 0 : bytes,
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Smaller parts',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
                if (noSplitAtEnd)
                  Text(
                    'One zip',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.base),
          if (sizes.isEmpty)
            Text(
              'Nothing to put in a zip yet.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            )
          else
            _FilesPreview(c: c, sizes: sizes),
          if (overFat) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This is over 4 GB. Some SD cards and USB sticks cannot hold one file that big: splitting makes parts that fit.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink80,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.onPrimary : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
