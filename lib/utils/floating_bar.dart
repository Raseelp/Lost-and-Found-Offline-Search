import 'package:flutter/widgets.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

/// Height of the floating navigation pill (and the round search button).
const double kFloatingBarHeight = 58;

/// Gap between the pill and the bottom of the screen (above the system
/// navigation area).
const double kFloatingBarBottomGap = 20;

/// The home screen's navigation bar floats over its content, so each tab's
/// scrollable ends with this much empty space - the last item can scroll up
/// clear of the bar instead of being stuck underneath it. Just a small
/// margin while the keyboard is up, since the bar is hidden then.
double floatingBarClearance(BuildContext context) {
  final media = MediaQuery.of(context);
  if (media.viewInsets.bottom > 0) return AppSpacing.base;
  return media.padding.bottom + kFloatingBarHeight + kFloatingBarBottomGap + AppSpacing.base;
}

/// The same, on a tab where the round action button (ActionFab) floats above the bar: the button sits in the
/// bottom right corner, so the last row would otherwise end up under it.
double actionFabClearance(BuildContext context) {
  final media = MediaQuery.of(context);
  if (media.viewInsets.bottom > 0) return AppSpacing.base;
  return floatingBarClearance(context) + kFloatingBarHeight + AppSpacing.md;
}
