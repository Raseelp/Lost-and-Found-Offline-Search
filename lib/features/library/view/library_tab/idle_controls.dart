part of '../library_tab.dart';

/// What shows under the scan button before a scan and after one: the banners about an interrupted scan and a model that
/// was updated. The settings of the scan are in the button.
class _IdleControls extends StatelessWidget {
  const _IdleControls({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.interruptedScan != null) ...[
          const SizedBox(height: AppSpacing.base),
          _InterruptedScanBanner(controller: controller),
        ],
        if (controller.modelResetFrom != 0) ...[
          const SizedBox(height: AppSpacing.base),
          _ModelUpdatedBanner(controller: controller),
        ],
      ],
    );
  }
}
