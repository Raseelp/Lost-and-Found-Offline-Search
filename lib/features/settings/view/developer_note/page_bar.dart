import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';

/// The top of a page opened from Settings: a back arrow, the title if there is one and, if given, actions on the right.
class PageBar extends StatelessWidget {
  const PageBar({super.key, this.title, this.actions = const []});

  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppColors.ink,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Text(
                    title!,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
