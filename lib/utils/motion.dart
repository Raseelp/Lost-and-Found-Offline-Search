import 'package:flutter/widgets.dart';

/// The app's answer to "Remove animations" (Android's accessibility setting, which turns off the phone's own
/// motion): every change still happens, and every screen still works, but nothing moves to get there.
///
/// Flutter already does part of it: with the setting on, an animation that plays once (forward, reverse,
/// animateTo, and every built-in animated widget) runs 20 times faster, so it is over in a frame or two. What is
/// left to the app:
/// - A controller that keeps time rather than moving anything (a story's five seconds a picture, how long a hint
///   stays up) would run 20 times faster too: those are made with AnimationBehavior.preserve.
/// - A loop (repeat) keeps its full speed, so it has to be stopped, on a still frame: [loopUnlessCalm].
/// - Springs and tickers of the app's own, and scroll glides, are not touched by Flutter: [calm] says to skip them,
///   and [glideTo] jumps instead of gliding.
/// Page transitions, dialogs and sheets run on controllers that Flutter speeds up, so they need nothing.
bool calm(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Keeps a looping controller going, or with motion off stops it on [rest]. Call from didChangeDependencies (so it
/// follows the setting as it changes) and wherever the loop would otherwise start.
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
