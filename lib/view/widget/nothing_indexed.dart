import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/header_action.dart';

/// Takes the person to the Library tab (closing whatever is open on top of the tabs first).
void goToLibrary(BuildContext context) {
  final native = Get.find<NativeController>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  native.setHomeTab(2);
  native.searchFocusNode.unfocus();
}

/// What every screen shows when nothing has been indexed yet: the same words and the same button
/// everywhere (Search, Collections, People, the zip export), with only the icon changing.
class NothingIndexed extends StatelessWidget {
  const NothingIndexed({super.key, this.icon = Icons.photo_library_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Icon(icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'Nothing indexed yet',
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Index your phone or a folder in the Library, then this fills in.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink48,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        HeaderActionPill(
          icon: Icons.folder_open_rounded,
          label: 'Go to Library',
          onTap: () => goToLibrary(context),
        ),
      ],
    );
  }
}
