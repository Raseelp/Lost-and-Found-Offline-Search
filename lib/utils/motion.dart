import 'package:flutter/widgets.dart';

/// Whether the phone asks for no animations ("Remove animations" in Android's accessibility settings). Every change
/// still happens and every screen still works, but nothing moves to get there. Flutter already runs a one-off
/// animation 20 times faster then. A controller that keeps time instead of moving anything is made with
/// AnimationBehavior.preserve so it is not sped up too, a loop is stopped on a still frame with [loopUnlessCalm], and
/// the app's own springs and tickers skip to where they would settle. Scrolling uses [glideTo].
bool calm(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Keeps a looping controller going, or with motion off stops it on [rest]. It is called from didChangeDependencies,
/// so it follows the setting as it changes, and wherever the loop would otherwise start.
void loopUnlessCalm(BuildContext context, AnimationController controller, {bool reverse = false, double rest = 0}) {
  if (calm(context)) {
    controller
      ..stop()
      ..value = rest;
  } else if (!controller.isAnimating) {
    controller.repeat(reverse: reverse);
  }
}

/// Moves a scroll position: a glide, or with motion off a jump.
Future<void> glideTo(
  BuildContext context,
  ScrollController controller,
  double offset, {
  Duration duration = const Duration(milliseconds: 300),
  Curve curve = Curves.easeOutCubic,
}) async {
  if (!controller.hasClients) return;
  if (calm(context)) {
    controller.jumpTo(offset);
  } else {
    await controller.animateTo(offset, duration: duration, curve: curve);
  }
}
