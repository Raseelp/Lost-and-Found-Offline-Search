import 'package:flutter/widgets.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

/// Height of the floating navigation pill (and the round search button).
const double kFloatingBarHeight = 58;

/// Gap between the pill and the bottom of the screen, above the system navigation area.
const double kFloatingBarBottomGap = 20;

/// The empty space at the end of each home tab's scrollable, so the last item can scroll up clear of the floating
/// bar instead of sitting under it. Only a small margin while the keyboard is up, since the bar is hidden then.
double floatingBarClearance(BuildContext context) {
  final media = MediaQuery.of(context);
  if (media.viewInsets.bottom > 0) return AppSpacing.base;
  return media.padding.bottom + kFloatingBarHeight + kFloatingBarBottomGap + AppSpacing.base;
}

/// The same on a tab where the round action button ([ActionFab]) floats above the bar in the bottom right corner, so
/// the last row does not end up under it.
double actionFabClearance(BuildContext context) {
  final media = MediaQuery.of(context);
  if (media.viewInsets.bottom > 0) return AppSpacing.base;
  return floatingBarClearance(context) + kFloatingBarHeight + AppSpacing.md;
}

/// Whether the home screen, and so its floating bar, is built right now. [AppToast] sits above the bar while it
/// shows and at the bottom of the screen anywhere else.
class FloatingBarPresence {
  const FloatingBarPresence._();

  static bool shown = false;
}
