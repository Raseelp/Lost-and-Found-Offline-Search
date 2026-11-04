import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/grid_video_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:video_player/video_player.dart';

/// Laid over the picture of a video's tile: when the video is the one the grid is playing, its silent preview
/// fades in over the picture, and the time left counts down in the corner. The rest of the time it draws nothing
/// (and shows [idleBadge], if the tile has one, where the countdown goes).
///
/// It costs a tile nothing while it is not playing: it only tells the [GridVideoController] where it is when
/// asked, a few times a second.
class GridVideoLayer extends StatefulWidget {
  const GridVideoLayer({
    super.key,
    required this.uri,
    this.idleBadge,
    this.badgeInset = const EdgeInsets.only(right: 6, bottom: 6),
  });

  final String uri;

  /// What the tile shows in the corner when nothing plays (the small play mark).
  final Widget? idleBadge;
  final EdgeInsets badgeInset;

  @override
  State<GridVideoLayer> createState() => _GridVideoLayerState();
}

class _GridVideoLayerState extends State<GridVideoLayer> {
  late final GridVideoController _controller =
      Get.isRegistered<GridVideoController>()
      ? Get.find<GridVideoController>()
      : Get.put(GridVideoController(), permanent: true);
  late final GridVideoSlot _slot = GridVideoSlot(
    widget.uri,
    _probe,
    _watchScroll,
  );

  /// What the tile knows about where it is. These are read while it builds, because a probe is made outside a build.
  bool _tickers = true;

  /// Whether the tab is showing. The home screen keeps all of its tabs built, with their animations running.
  bool _shown = true;
  bool _noMotion = false;
  Size _screen = Size.zero;
  ModalRoute<dynamic>? _route;

  ScrollPosition? _watched;

  @override
  void initState() {
    super.initState();
    _controller.register(_slot);
  }

  @override
  void didUpdateWidget(covariant GridVideoLayer old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      _slot.uri = widget.uri;
      _controller.uriChanged(_slot);
    }
  }

  /// Checks what plays after the frame, so that a tab switched away from or a screen opened stops the preview at once
  /// and not at the next tick. Where things are is not asked in the middle of building them.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.checkActive();
      }
    });
  }

  @override
  void dispose() {
    _controller.unregister(_slot);
    _watchScroll(false);
    super.dispose();
  }

  void _onScroll() => _controller.scrolled();

  /// Stops the preview at once when another screen opens over this one, before the viewer starts its own player.
  void _onCovered(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) {
      _controller.checkActive();
    }
  }

  Animation<double>? _watchedRoute;

  /// While this tile plays, it tells the controller when its list moves or a screen opens over it.
  void _watchScroll(bool on) {
    _watched?.removeListener(_onScroll);
    _watched = null;
    _watchedRoute?.removeStatusListener(_onCovered);
    _watchedRoute = null;
    if (!on || !mounted) {
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != null) {
      position.addListener(_onScroll);
      _watched = position;
    }
    final covering = _route?.secondaryAnimation;
    if (covering != null) {
      covering.addStatusListener(_onCovered);
      _watchedRoute = covering;
    }
  }

  /// Where the tile is, or null when it may not play: its tickers are off, its tab is not showing, animations are off,
  /// or its screen is not the current one or is still sliding in or out.
  GridVideoSpot? _probe() {
    if (!mounted || !_tickers || !_shown || _noMotion) return null;
    final route = _route;
    if (route != null) {
      if (!route.isCurrent) {
        return null;
      }
      final entering = route.animation, covered = route.secondaryAnimation;
      if (entering != null && entering.status != AnimationStatus.completed) {
        return null;
      }
      if (covered != null && covered.status != AnimationStatus.dismissed) {
        return null;
      }
    }
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return null;
    }
    final at = box.localToGlobal(Offset.zero);
    final rect = at & box.size;
    var clip = Offset.zero & _screen;
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      clip = clip.intersect(
        viewport.localToGlobal(Offset.zero) & viewport.size,
      );
    }
    final seen = rect.intersect(clip);
    final fraction = seen.width <= 0 || seen.height <= 0
        ? 0.0
        : (seen.width * seen.height) / (rect.width * rect.height);
    return GridVideoSpot(
      fraction: fraction.clamp(0.0, 1.0),
      top: at.dy,
      left: at.dx,
      scrolling: scrollable?.position.isScrollingNotifier.value ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    _tickers = TickerMode.of(context);
    _shown = Visibility.of(context);
    _noMotion = MediaQuery.disableAnimationsOf(context);
    _screen = MediaQuery.sizeOf(context);
    _route = ModalRoute.of(context);
    return ValueListenableBuilder<GridVideoPlay?>(
      valueListenable: _controller.playing,
      builder: (context, play, _) {
        final mine = play != null && identical(play.slot, _slot);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (mine)
              IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(play.controller),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, t, child) =>
                      Opacity(opacity: t, child: child),
                  child: _Picture(controller: play.controller),
                ),
              ),
            Positioned(
              right: widget.badgeInset.right,
              bottom: widget.badgeInset.bottom,
              child: mine
                  ? ExcludeSemantics(
                      child: _Countdown(remaining: _controller.remaining),
                    )
                  : (widget.idleBadge ?? const SizedBox.shrink()),
            ),
          ],
        );
      },
    );
  }
}

/// The video, filling the tile the way the picture does: cropped, not squeezed.
class _Picture extends StatelessWidget {
  const _Picture({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.isEmpty) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// The time left, shown the way Google Photos shows a video's length, and only while it plays.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining});

  final ValueListenable<int> remaining;

  static String _label(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: remaining,
      builder: (context, seconds, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.scrim.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          _label(seconds),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onMedia,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
