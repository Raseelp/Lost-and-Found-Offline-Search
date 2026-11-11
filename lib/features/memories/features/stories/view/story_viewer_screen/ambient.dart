part of '../story_viewer_screen.dart';

/// The screen painted in the colours of a picture ([look]): top to bottom, with a little of the colour at each side.
/// Without a look, the app's own dark teal.
class _Ambient extends StatelessWidget {
  const _Ambient({this.look});

  final _Look? look;

  @override
  Widget build(BuildContext context) {
    final l = look;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [l?.top ?? AppColors.primary, l?.middle ?? AppColors.mediaInk, l?.bottom ?? AppColors.mediaInk],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        if (l != null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  l.left.withValues(alpha: 0.55),
                  l.left.withValues(alpha: 0),
                  l.right.withValues(alpha: 0),
                  l.right.withValues(alpha: 0.55),
                ],
                stops: const [0, 0.4, 0.6, 1],
              ),
            ),
          ),
      ],
    );
  }
}
