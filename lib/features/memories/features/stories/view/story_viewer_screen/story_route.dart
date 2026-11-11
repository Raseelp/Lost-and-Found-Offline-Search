part of '../story_viewer_screen.dart';

/// The route that opens the stories: a round window grows out of the ring that was tapped until it
/// fills the screen, and shrinks back into it on closing. After a drag-down the picture has already
/// left the screen by itself, so there is nothing to shrink.
class StoryRoute extends PageRouteBuilder<void> {
  StoryRoute({required List<StoryRing> rings, required int initial, this.origin, this.originRadius = 30})
    : super(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, secondaryAnimation) => StoryViewerScreen(rings: rings, initial: initial),
      );

  /// Where the ring is on screen (its centre), and how big it is. Null: the middle of the screen.
  final Offset? origin;
  final double originRadius;

  /// Set when the viewer was dragged away: it is gone already, so closing shows nothing.
  bool dragged = false;

  /// Grows the round window from [origin] to the corner of the screen that is furthest from it.
  ///
  /// The curve starts and ends gently, because a curve that is fast at the start makes the first frames jump. There is
  /// no fade, since a fade over the whole screen is drawn in a layer of its own every frame, and the window itself is
  /// the entrance. The page is its own layer, so growing the window only changes what is cut out of it.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (dragged && animation.status == AnimationStatus.reverse) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        final from = origin ?? size.center(Offset.zero);
        final t = Curves.easeInOutCubic.transform(animation.value);
        final reach = [
          (from - Offset.zero).distance,
          (from - Offset(size.width, 0)).distance,
          (from - Offset(0, size.height)).distance,
          (from - Offset(size.width, size.height)).distance,
        ].reduce(math.max);
        final radius = originRadius + (reach - originRadius) * t;
        return ClipPath(
          clipper: _CircleClipper(center: from, radius: radius),
          child: RepaintBoundary(child: child),
        );
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) => old.center != center || old.radius != radius;
}
