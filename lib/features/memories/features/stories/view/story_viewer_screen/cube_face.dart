part of '../story_viewer_screen.dart';

/// One ring's page turned as the face of a cube: the page leaving swings away on its far edge while
/// the one coming in swings round to meet it, and the one going dims as it turns from you.
///
/// Each page is its own layer, so while the picture is pulled or the pages turn the page is moved as it is and not
/// drawn again. The next ring is built beside the one on screen, so its first picture is ready when it turns in.
class _CubeFace extends StatelessWidget {
  const _CubeFace({required this.controller, required this.index, required this.initial, required this.child});

  final PageController controller;
  final int index;
  final int initial;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? initial.toDouble())
            : initial.toDouble();
        final delta = (index - page).clamp(-1.0, 1.0);
        // The same widgets whether the page is in front or turning: a page that changed its place in the tree
        // would be built again, and its story with it.
        return Transform(
          alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: delta == 0
              ? Matrix4.identity()
              : (Matrix4.identity()
                  ..setEntry(3, 2, 0.0009)
                  ..rotateY(-delta * math.pi / 2)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (delta != 0)
                IgnorePointer(
                  child: ColoredBox(color: AppColors.scrim.withValues(alpha: 0.6 * delta.abs())),
                ),
            ],
          ),
        );
      },
    );
  }
}
