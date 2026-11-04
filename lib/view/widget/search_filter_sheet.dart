import 'package:flutter/material.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

void showSearchFilterSheet(BuildContext context, NativeController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.transparent,
    builder: (_) => _SearchFilterSheet(controller: controller),
  );
}

/// Every control here edits a local draft, not the live settings.
///
/// Applying, and possibly searching again, on every tap would fire a search while the person is still trying a few
/// options. There is no good way to signal a change without either popping the sheet on each change or leaving it
/// open with no feedback. One clear commit point, the button at the bottom, solves both.
class _SearchFilterSheet extends StatefulWidget {
  const _SearchFilterSheet({required this.controller});

  final NativeController controller;

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

/// The button offers to search only when there is a query on screen, typed text or an attached image. That is the
/// condition runSearch guards on. Otherwise a tap on search would do nothing, so the button only offers to save the
/// settings. It reads the current state, not whether a search was run earlier.
class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late ContentMode _contentMode;
  late double _limit;

  @override
  void initState() {
    super.initState();
    _contentMode = widget.controller.searchContentMode;
    _limit = widget.controller.sliderValue;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    final hasQuery =
        controller.pickedSearchImageUri != null ||
        controller.searchTextController.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  'Search filters',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.base,
                  AppSpacing.base,
                  AppSpacing.xs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'INCLUDE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.ink48,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  0,
                  AppSpacing.base,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    for (final mode in ContentMode.values) ...[
                      if (mode != ContentMode.values.first) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FilterChip(
                          label: _filterModeLabel(mode),
                          selected: _contentMode == mode,
                          onTap: () => setState(() => _contentMode = mode),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.base,
                  AppSpacing.base,
                  0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Results per search', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${_limit.round()}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: _limit,
                    min: 10,
                    max: 100,
                    divisions: 90,
                    onChanged: (value) => setState(() => _limit = value),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.sm,
                  AppSpacing.base,
                  AppSpacing.base,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: () {
                        controller.setSearchContentMode(_contentMode);
                        controller.setSliderValue(_limit);
                        Navigator.of(context).pop();
                        if (hasQuery) controller.runSearch();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Text(
                          hasQuery ? 'Confirm and search' : 'Confirm',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: AppColors.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

String _filterModeLabel(ContentMode mode) {
  switch (mode) {
    case ContentMode.both:
      return 'Both';
    case ContentMode.images:
      return 'Images';
    case ContentMode.videos:
      return 'Videos';
  }
}
