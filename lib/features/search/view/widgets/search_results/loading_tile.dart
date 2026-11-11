part of '../search_results.dart';

/// What a thumbnail that has not arrived yet looks like: a soft band of light drifting across the tile while a small
/// icon that suits the media fades in and out, swapping every moment, so a grid that is still filling in feels like it
/// is being developed rather than broken.
class _LoadingTile extends StatefulWidget {
  const _LoadingTile({required this.index, required this.isVideo});

  final int index;
  final bool isVideo;

  @override
  State<_LoadingTile> createState() => _LoadingTileState();
}

class _LoadingTileState extends State<_LoadingTile>
    with SingleTickerProviderStateMixin {
  static const _imageIcons = [
    Icons.landscape_outlined,
    Icons.wb_sunny_outlined,
    Icons.local_florist_outlined,
    Icons.pets_outlined,
    Icons.photo_outlined,
  ];
  static const _videoIcons = [
    Icons.movie_outlined,
    Icons.play_circle_outline_rounded,
    Icons.videocam_outlined,
  ];

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  Timer? _swap;
  late int _iconIndex = widget.index;

  List<IconData> get _icons => widget.isVideo ? _videoIcons : _imageIcons;

  /// Neighbouring tiles start at different points so the grid does not pulse in lockstep. The value has to be set
  /// before repeat() starts, because the AnimationController.value setter stops the controller, and the other order
  /// cancelled the repeat in the same frame and left the shimmer frozen. With motion off the icon stays as it is,
  /// because changing it with no fade would blink across the grid.
  @override
  void initState() {
    super.initState();
    _sweep.value = (widget.index * 0.137) % 1;
    _swap = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (mounted && !calm(context)) setState(() => _iconIndex++);
    });
  }

  /// With motion off the shimmer rests, each tile where it was.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _sweep, rest: (widget.index * 0.137) % 1);
  }

  @override
  void dispose() {
    _swap?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  /// A grid full of these ticks constantly and independently, so the tile has its own compositing layer. Without it,
  /// every tile's sweep would ask Flutter to reconsider repainting the whole grid each frame.
  @override
  Widget build(BuildContext context) {
    final icon = _icons[_iconIndex % _icons.length];

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) {
          final t = _sweep.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-2 + 4 * t, -1),
                end: Alignment(-1 + 4 * t, 1),
                colors: const [
                  AppColors.parchment,
                  AppColors.pearl,
                  AppColors.parchment,
                ],
              ),
            ),
            child: child,
          );
        },
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              icon,
              key: ValueKey(icon),
              size: 28,
              color: AppColors.ink48.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
