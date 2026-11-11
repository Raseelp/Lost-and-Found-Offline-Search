part of '../library_tab.dart';

/// The controls under the chip before a scan and after one: what to include, and the way to index one folder instead
/// of the whole phone.
class _IdleControls extends StatelessWidget {
  const _IdleControls({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.base),
        if (controller.interruptedScan != null) ...[
          _InterruptedScanBanner(controller: controller),
          const SizedBox(height: AppSpacing.base),
        ],
        if (controller.modelResetFrom != 0) ...[
          _ModelUpdatedBanner(controller: controller),
          const SizedBox(height: AppSpacing.base),
        ],
        Text(
          'WHAT TO INDEX',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Segmented<ContentMode>(
          options: _scopeOrder,
          value: controller.selectedContentMode,
          labelOf: _scopeLabel,
          onChanged: (mode) =>
              controller.toggleSelectedContentMode(contentMode: mode),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'WHERE TO LOOK',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Segmented<bool>(
          options: const [true, false],
          value: controller.scanWholePhone,
          labelOf: (wholePhone) => wholePhone ? 'Whole phone' : 'One folder',
          onChanged: controller.setScanWholePhone,
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            controller.scanWholePhone
                ? 'Everything on your phone, in one go.'
                : 'Tap the chip, then pick the folder.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
          ),
        ),
      ],
    );
  }
}

const _scopeOrder = [ContentMode.images, ContentMode.both, ContentMode.videos];

String _scopeLabel(ContentMode mode) {
  switch (mode) {
    case ContentMode.images:
      return 'Photos';
    case ContentMode.videos:
      return 'Videos';
    case ContentMode.both:
      return 'Photos & videos';
  }
}
