part of '../depth_widgets.dart';

/// A video. Until its first turn it is a still with a play mark. When that turn comes the play mark is tapped, which
/// presses it and spreads a ring, the clip starts and the bar under it begins to fill. From then on it keeps playing
/// in a loop, whether it is at the front or far back, for as long as the page is showing.
class _VideoCard extends StatefulWidget {
  const _VideoCard({super.key, required this.turn, required this.awake});

  final _Turn turn;

  /// Whether the page is showing and motion is allowed. The clip only runs then.
  final bool awake;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard>
    with SingleTickerProviderStateMixin {
  static const String _asset = 'assets/tour/videos/v_football.mp4';
  static const Duration _tapTime = Duration(milliseconds: 560);
  /// When the press lands and the clip starts, a little before the end of the tap.
  static const Duration _landAt = Duration(milliseconds: 330);

  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: _tapTime,
  );
  final Stopwatch _clock = Stopwatch();
  VideoPlayerController? _video;
  bool _ready = false;
  bool _pressed = false;
  bool _landed = false;
  Timer? _landTimer;
  int _generation = 0;

  /// True when the clip could not be loaded on this phone. The still stays, and it is not tried again every frame.
  bool _failed = false;

  /// How far the clock is behind or ahead of the clip. The bar runs off the clock, because the player only says where
  /// it is every half second and the bar would step. The offset is corrected whenever the player reports.
  Duration _offset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _VideoCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.awake && _video == null && !_failed) {
      unawaited(_load(++_generation));
    }
    if (!widget.awake) {
      if (_pressed || _video != null) _sleep();
    } else if (!_pressed && widget.turn.focus > 0.45) {
      _press();
    }
  }

  /// Loads the clip, muted and looping. When there is no player here or the clip is not playable, the still stays and
  /// the bar still fills.
  Future<void> _load(int generation) async {
    final controller = VideoPlayerController.asset(
      _asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        if (identical(_video, controller)) _video = null;
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || generation != _generation) return;
      controller.addListener(_follow);
      if (_landed) await controller.play();
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
    } catch (_) {
      _failed = true;
      if (identical(_video, controller)) _video = null;
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  /// Corrects the clock offset when the player's position is more than 120 milliseconds away from it. Across the loop
  /// point the two can sit on either side of it, so the difference is taken the short way round.
  void _follow() {
    final v = _video?.value;
    if (v == null || !v.isPlaying || !_clock.isRunning) return;
    final length = v.duration.inMilliseconds;
    if (length <= 0) return;
    var diff = v.position.inMilliseconds - _here(length);
    if (diff > length / 2) diff -= length;
    if (diff < -length / 2) diff += length;
    if (diff.abs() > 120) _offset += Duration(milliseconds: diff);
  }

  int _here(int length) =>
      (_clock.elapsedMilliseconds + _offset.inMilliseconds) % length;

  void _press() {
    _pressed = true;
    _tap.forward(from: 0);
    _landTimer?.cancel();
    _landTimer = Timer(_landAt, () {
      if (!mounted || !_pressed) return;
      setState(() => _landed = true);
      _clock.start();
      if (_ready) unawaited(_video?.play());
    });
  }

  /// Called when the page went away. Stops, gives the player back and becomes a still again for when the page comes
  /// back. A phone only has a few video decoders and the other pages want them.
  void _sleep() {
    _generation++;
    _pressed = false;
    _landed = false;
    _ready = false;
    _landTimer?.cancel();
    _clock.stop();
    _clock.reset();
    _offset = Duration.zero;
    final controller = _video;
    _video = null;
    controller?.removeListener(_follow);
    if (controller != null) unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _generation++;
    _landTimer?.cancel();
    _tap.dispose();
    final controller = _video;
    _video = null;
    controller?.removeListener(_follow);
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  /// The still lies over the clip until the press lands.
  @override
  Widget build(BuildContext context) {
    final f = widget.turn.focus;
    final length = _ready
        ? _video!.value.duration.inMilliseconds.clamp(1, 1 << 30)
        : 4000;
    final progress = _landed ? _here(length) / length : 0.0;
    final showStill = !(_ready && _landed);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: TourPalette.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && _video != null)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            AnimatedOpacity(
              opacity: showStill ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Image.asset(
                'assets/tour/videos/v_football.jpg',
                fit: BoxFit.cover,
                cacheWidth: 400,
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _tap,
                builder: (context, _) {
                  final t = _tap.value;
                  final press =
                      1 - 0.16 * math.sin((t / 0.55).clamp(0.0, 1.0) * math.pi);
                  final u = ((t - 0.08) / 0.62).clamp(0.0, 1.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_pressed && u > 0 && u < 1)
                        Container(
                          width: 30 + 26 * u,
                          height: 30 + 26 * u,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: TourPalette.white.withValues(
                              alpha: 0.42 * (1 - u),
                            ),
                          ),
                        ),
                      AnimatedOpacity(
                        opacity: _landed ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: Transform.scale(
                          scale: _pressed ? press : 1,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: TourPalette.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                              color: TourPalette.teal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Opacity(
                opacity: _landed
                    ? 1
                    : _DepthWidgetsState._smooth((f - 0.1) / 0.4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: TourPalette.white.withValues(alpha: 0.5),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      TourPalette.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
