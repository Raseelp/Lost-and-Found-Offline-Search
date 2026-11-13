part of '../library_tab.dart';

/// What shows under the scan button before a scan and after one: the banner about a model that was updated. A scan that
/// was interrupted shows on the scan card as paused, and its button picks it up again (see [startIndexing]). The settings
/// of the scan are in the button.
class _IdleControls extends StatelessWidget {
  const _IdleControls({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.modelResetFrom != 0) ...[
          const SizedBox(height: AppSpacing.base),
          _ModelUpdatedBanner(controller: controller),
        ],
      ],
    );
  }
}
