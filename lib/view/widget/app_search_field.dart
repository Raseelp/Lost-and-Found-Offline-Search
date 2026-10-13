import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

/// The size, shape and type of the app's search box. The Search tab's own box uses these too, so
/// every search box in the app is the same height and width-to-corner as that one.
class AppSearchBox {
  AppSearchBox._();

  /// Around the row of icon, field and buttons.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.base,
    vertical: AppSpacing.xxs,
  );

  /// Above and below the typed line: with [padding], what sets the box's height.
  static const EdgeInsets fieldPadding = EdgeInsets.symmetric(
    vertical: AppSpacing.md,
  );

  static const double iconSize = 19;

  /// Size of the small buttons that sit inside the box (clear, filter ...).
  static const double buttonSize = 34;

  static BoxDecoration decoration() => BoxDecoration(
    color: AppColors.parchment,
    borderRadius: BorderRadius.circular(AppRadius.pill),
  );
}

/// A search box that filters as you type (no search button: the list under it just narrows). It
/// has the Search tab's size and look. A tap anywhere outside it puts the keyboard away, which
/// Android does not do by itself.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.focusNode,
    this.trailingWhenEmpty,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// Shown at the right while nothing is typed (the clear button takes its place once there is).
  final Widget? trailingWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: AppSearchBox.padding,
      decoration: AppSearchBox.decoration(),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: AppSearchBox.iconSize,
            color: AppColors.ink48,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              textInputAction: TextInputAction.search,
              style: textStyle,
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: AppSearchBox.fieldPadding,
                hintText: hint,
                hintStyle: textStyle?.copyWith(color: AppColors.ink48),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) {
                return trailingWhenEmpty ?? const SizedBox.shrink();
              }
              // Counts as part of the field for "tap outside", so clearing keeps the keyboard.
              return TextFieldTapRegion(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                    child: const SizedBox(
                      width: AppSearchBox.buttonSize,
                      height: AppSearchBox.buttonSize,
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.ink48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
