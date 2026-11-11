part of '../story_viewer_screen.dart';

/// One ring's story: its pictures one after the other, the bars on top, who it is, and the button.
///
/// A dark shade at the top and bottom keeps the bars and the button readable on any picture. A screen reader goes
/// through the pictures with custom actions, since the sides of the picture are not buttons for it. The ring of the
/// avatar turns while the story is being found.
class _StoryPage extends StatefulWidget {
  const _StoryPage({
    super.key,
    required this.ring,
    required this.active,
    required this.playing,
    required this.hasPrevious,
    required this.onNextRing,
    required this.onPreviousRing,
    required this.onAction,
    required this.onClose,
  });

  final StoryRing ring;

  /// This is the ring on screen (the others are beside it, waiting).
  final bool active;

  /// Nothing is holding the story: not swiping, pulling down or out of sight.
  final bool playing;
  final bool hasPrevious;
  final VoidCallback onNextRing, onPreviousRing, onAction, onClose;

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage> with SingleTickerProviderStateMixin {
  static const Duration _frameTime = Duration(seconds: 5);

  /// A video plays from the moment that was picked for it, or from the start if little would be left, for as long as it
  /// lasts, but not longer than [_videoCap] and not shorter than [_videoMin].
  static const Duration _videoCap = Duration(seconds: 15);
  static const Duration _videoMin = Duration(seconds: 2);

  final StoriesController _stories = Get.find<StoriesController>();
  late final AnimationController _progress;

  int _frame = 0;

  /// The picture this page starts at when it becomes the one on screen: the first that came after the story was last
  /// opened. A page that is already on screen starts there at once.
  int _start = 0;

  /// Null while the story's pictures are being found.
  List<StoryFrame>? _frames;

  /// How the story's pictures were chosen ("New this week"), when it says.
  String? _caption;
  final Map<int, Uint8List> _bytes = {};
  final Set<int> _failed = {};

  /// What each picture looks like from far away (its colours and shape), and the ring's own face or cover, for the
  /// loading picture.
  final Map<int, _Look> _looks = {};
  _Look? _coverLook;

  /// The route that shows the page, while it is still opening.
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeListener;
  bool _held = false;
  bool _gone = false;

  /// The player of the video on screen (only the ring on screen has one), whether it is ready, whether its picture has
  /// taken over from the still, and a count of starts so that a player that arrives late is dropped.
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoShown = false;
  int _videoRun = 0;

  bool get _isVideo {
    final frames = _frames;
    return frames != null && _frame < frames.length && frames[_frame].isVideo;
  }

  bool get _canRun => !_gone && widget.active && widget.playing && !_held;

  @override
  void initState() {
    super.initState();
    // A clock, not a movement: with the phone's animations off Flutter would run it 20 times faster otherwise,
    // and each picture would be gone in a moment.
    _progress = AnimationController(vsync: this, duration: _frameTime, animationBehavior: AnimationBehavior.preserve)
      ..addStatusListener(_onProgress);
    _storiesMuted.addListener(_onMute);
    unawaited(_loadCoverLook());
    _load();
  }

  @override
  void dispose() {
    _gone = true;
    final listener = _routeListener;
    if (listener != null) _routeAnimation?.removeStatusListener(listener);
    _storiesMuted.removeListener(_onMute);
    _releaseVideo();
    _progress.dispose();
    super.dispose();
  }

  void _onMute() {
    unawaited(_video?.setVolume(_storiesMuted.value ? 0 : 1));
  }

  @override
  void didUpdateWidget(covariant _StoryPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (_frames != null) unawaited(_stories.markViewed(widget.ring, shown: _frames));
      _frame = _start;
      _start = 0;
      _enterFrame();
    } else if (!widget.active && old.active) {
      _pause();
      _releaseVideo();
    } else if (widget.playing != old.playing) {
      if (_canRun) {
        _resume();
      } else {
        _pause();
      }
    }
  }

  /// Completes when the route that shows the page has finished opening. The page is built while its route is still
  /// opening, and what it asks of the phone (the pictures of a ring, their dates, the thumbnails) waits for the opening
  /// to end, so it does not take frames from it.
  Future<void> _routeSettled() {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gone) {
        done.complete();
        return;
      }
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.status == AnimationStatus.completed) {
        done.complete();
        return;
      }
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          animation.removeStatusListener(listener);
          if (!done.isCompleted) done.complete();
        }
      }

      _routeAnimation = animation;
      _routeListener = listener;
      animation.addStatusListener(listener);
    });
    return done.future;
  }

  Future<void> _loadCoverLook() async {
    final ring = widget.ring;
    final bytes = ring.kind == StoryKind.person
        ? Get.find<FacesController>().cachedCrop(ring.person!.coverFaceId)
        : Get.find<CollectionsController>().coverFor(ring.collection!.id);
    if (bytes == null) return;
    final look = await _Look.of(bytes);
    if (_gone || look == null) return;
    setState(() => _coverLook = look);
  }

  /// The queue that makes rings ready one at a time: the one on screen first, the ones beside it after. Each asks the
  /// phone for everything a person or collection holds, and several at once would take a lot of frames from the story
  /// that is playing. A ring that does not answer within 40 seconds is given up, so that it does not keep the rings
  /// behind it from being made ready.
  static Future<void> _queue = Future<void>.value();

  Future<StoryEdition> _edition() async {
    final before = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await before;
      if (_gone) return StoryEdition.empty;
      return await _stories
          .loadEdition(widget.ring)
          .timeout(const Duration(seconds: 40), onTimeout: () => StoryEdition.empty);
    } catch (e) {
      debugPrint('story: could not make the story of ${widget.ring.key}: $e');
      return StoryEdition.empty;
    } finally {
      done.complete();
    }
  }

  /// Makes the story ready once the route has opened. Opening a story is what greys its ring, so the ring is marked as
  /// viewed only once the story exists. The first picture is fetched before anything else and the rest follow one
  /// after another.
  Future<void> _load() async {
    await _routeSettled();
    if (_gone) return;
    final edition = await _edition();
    if (_gone) return;
    final frames = edition.frames;
    final first = edition.firstUnread;
    setState(() {
      _frames = frames;
      _caption = edition.caption;
      if (widget.active) {
        _frame = first;
      } else {
        _start = first;
      }
    });
    if (widget.active) unawaited(_stories.markViewed(widget.ring, shown: frames));
    final order = frames.isEmpty
        ? <int>[]
        : [first, for (var k = 0; k < frames.length; k++) if (k != first) k];
    for (final k in order) {
      if (_gone) return;
      await _fetch(k);
    }
  }

  Future<void> _fetch(int k) async {
    final bytes = await _stories.frameBytes(_frames![k]);
    final look = bytes == null ? null : await _Look.of(bytes);
    if (_gone) return;
    setState(() {
      if (bytes == null) {
        _failed.add(k);
      } else {
        _bytes[k] = bytes;
        if (look != null) _looks[k] = look;
      }
    });
    if (k == _frame && widget.active) _enterFrame();
  }

  /// Starts the time of the picture shown once it is there, or moves past it if it has failed.
  void _enterFrame() {
    _progress
      ..stop()
      ..duration = _frameTime
      ..value = 0;
    _releaseVideo();
    if (!widget.active) return;
    if (_failed.contains(_frame)) {
      _next();
    } else if (_bytes.containsKey(_frame)) {
      if (_isVideo) {
        unawaited(_startVideo());
      } else if (_canRun) {
        _progress.forward(from: 0);
      }
    }
  }

  /// Plays the video of the picture on screen over its still. Until it is ready the still is what is shown, as it is
  /// the same moment, and if the video cannot be played the still is shown for the usual time. The video mixes with
  /// other audio, so it does not take the sound away from what the person is listening to.
  Future<void> _startVideo() async {
    final run = ++_videoRun;
    final frame = _frames![_frame];
    final player = VideoPlayerController.contentUri(
      Uri.parse(frame.uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = player;
    try {
      await player.initialize().timeout(const Duration(seconds: 6));
      final total = player.value.duration;
      var start = Duration(milliseconds: frame.timestampMs);
      if (total - start < const Duration(seconds: 3)) start = Duration.zero;
      var length = total - start;
      if (length > _videoCap) length = _videoCap;
      if (length < _videoMin) length = _videoMin;
      await player.setVolume(_storiesMuted.value ? 0 : 1);
      await player.setLooping(false);
      if (start > Duration.zero) await player.seekTo(start);
      if (_gone || run != _videoRun) return;
      _progress.duration = length;
      setState(() => _videoReady = true);
      if (_canRun) {
        _progress.forward(from: 0);
        await _playVideo(player, run);
      }
    } catch (e) {
      debugPrint('story video: could not play ${frame.uri}: $e');
      if (_gone || run != _videoRun) return;
      _releaseVideo();
      if (_canRun) _progress.forward(from: 0);
    }
  }

  /// Plays the video, and after a moment for its first picture to be there it takes over from the still.
  Future<void> _playVideo(VideoPlayerController player, int run) async {
    await player.play();
    if (_videoShown) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!_gone && run == _videoRun) setState(() => _videoShown = true);
  }

  /// Lets the player go. A later start that finds the count changed lets go of its own. The picture of it is taken off
  /// the screen first and the player is released after that frame, never while something still draws it.
  void _releaseVideo() {
    _videoRun++;
    final player = _video;
    _video = null;
    _videoReady = false;
    _videoShown = false;
    if (player == null) return;
    unawaited(player.pause().catchError((_) {}));
    if (!_gone && mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_disposeVideo(player)));
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Pauses the player first, so it stops playing even if letting go takes a moment, and then disposes of it.
  Future<void> _disposeVideo(VideoPlayerController player) async {
    unawaited(player.pause().catchError((_) {}));
    try {
      await player.dispose();
    } catch (e) {
      debugPrint('story video: dispose failed: $e');
    }
  }

  void _pause() {
    _progress.stop();
    final player = _video;
    if (player != null) unawaited(player.pause().catchError((_) {}));
  }

  void _resume() {
    if (!_canRun || !_bytes.containsKey(_frame) || _progress.isCompleted) return;
    if (_isVideo) {
      final player = _video;
      if (player == null || !_videoReady) return;
      unawaited(_playVideo(player, _videoRun).catchError((_) {}));
    }
    _progress.forward();
  }

  void _onProgress(AnimationStatus status) {
    if (status == AnimationStatus.completed) _next();
  }

  void _next() {
    final frames = _frames;
    if (frames == null) return;
    if (_frame + 1 < frames.length) {
      setState(() => _frame++);
      _enterFrame();
    } else {
      widget.onNextRing();
    }
  }

  void _previous() {
    if (_frame > 0) {
      setState(() => _frame--);
      _enterFrame();
    } else if (widget.hasPrevious) {
      widget.onPreviousRing();
    } else {
      _enterFrame();
    }
  }

  void _hold(bool held) {
    _held = held;
    if (held) {
      _pause();
    } else {
      _resume();
    }
  }

  /// What the loading picture is made from: the colours of the last picture of this story that is there, else the
  /// ring's own face or cover.
  _Look? _loadingLook() {
    for (var k = _frame - 1; k >= 0; k--) {
      final look = _looks[k];
      if (look != null) return look;
    }
    return _looks.values.isEmpty ? _coverLook : _looks.values.first;
  }

  String _actionLabel(StoryRing ring) {
    if (ring.kind == StoryKind.person && (ring.person!.name ?? '').trim().isNotEmpty) {
      return 'Search ${ring.title}';
    }
    return 'Open ${ring.kind == StoryKind.person ? 'this person' : ring.title}';
  }

  @override
  Widget build(BuildContext context) {
    final ring = widget.ring;
    final frames = _frames;

    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            customSemanticsActions: {
              CustomSemanticsAction(label: 'Next picture'): _next,
              CustomSemanticsAction(label: 'Previous picture'): _previous,
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (d.localPosition.dx < MediaQuery.sizeOf(context).width / 3) {
                  _previous();
                } else {
                  _next();
                }
              },
              onLongPressStart: (_) => _hold(true),
              onLongPressEnd: (_) => _hold(false),
              onLongPressCancel: () => _hold(false),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey('$_frame-${_bytes.containsKey(_frame)}'),
                  child: _picture(ring, frames),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.scrim.withValues(alpha: 0.55),
                    AppColors.transparent,
                    AppColors.transparent,
                    AppColors.scrim.withValues(alpha: 0.6),
                  ],
                  stops: const [0, 0.22, 0.7, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                  child: _Bars(count: frames?.length ?? 0, frame: _frame, progress: _progress),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.sm, AppSpacing.xs, 0),
                  child: Row(
                    children: [
                      StoryAvatar(ring: ring, size: 40, lit: false, forceSpin: frames == null),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ring.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.onMedia),
                            ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _caption ?? '${ring.count} photos and videos',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onMedia70),
                                  ),
                                ),
                                if (frames != null && _frame < frames.length && frames[_frame].fresh) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  const NewTag(label: 'New picture'),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_isVideo)
                        ValueListenableBuilder<bool>(
                          valueListenable: _storiesMuted,
                          builder: (context, muted, _) => IconButton(
                            tooltip: muted ? 'Turn sound on' : 'Turn sound off',
                            onPressed: () => _storiesMuted.value = !muted,
                            icon: Icon(
                              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: AppColors.onMedia,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, color: AppColors.onMedia),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
                  child: Material(
                    color: AppColors.onMedia,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: widget.onAction,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _actionLabel(ring),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.ink),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.ink),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The picture on screen. It sits on the picture's own colours, top to bottom and a little from each side, so
  /// whatever the picture does not cover looks like a continuation of it, with nothing stretched and nothing blocky. The
  /// picture is a card with round corners that glows in its own colour. A video plays over its still once it has a
  /// picture of its own.
  Widget _picture(StoryRing ring, List<StoryFrame>? frames) {
    final bytes = _bytes[_frame];
    final video = _isVideo ? _video : null;
    if (frames != null && frames.isEmpty) {
      return const _Message('Nothing to show here yet');
    }
    if (bytes == null) {
      if (_failed.contains(_frame)) return const _Message("This one can't be shown");
      return Semantics(
        label: 'Loading',
        child: _StoryLoading(look: _loadingLook()),
      );
    }

    final look = _looks[_frame];
    final still = Image.memory(
      bytes,
      fit: look == null ? BoxFit.contain : BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    final playing = (video != null && _videoReady)
        ? Positioned.fill(
            child: AnimatedOpacity(
              opacity: _videoShown ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: FittedBox(
                fit: look == null ? BoxFit.contain : BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              ),
            ),
          )
        : null;

    return Semantics(
      image: true,
      label: '${ring.title}, picture ${_frame + 1} of ${frames?.length ?? 1}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Ambient(look: look),
          if (look == null)
            Positioned.fill(child: still)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AspectRatio(
                  aspectRatio: look.aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_cardRadius),
                      boxShadow: [BoxShadow(color: look.glow.withValues(alpha: 0.55), blurRadius: 44, spreadRadius: 3)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_cardRadius),
                      child: Stack(fit: StackFit.expand, children: [still, ?playing]),
                    ),
                  ),
                ),
              ),
            ),
          if (look == null) ?playing,
        ],
      ),
    );
  }
}

/// Whether a video in a story is silent. It starts silent, and what the person chooses stays for the rest of the session.
final ValueNotifier<bool> _storiesMuted = ValueNotifier(true);

const double _cardRadius = 22;

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onMedia70),
        ),
      ),
    );
  }
}

/// One bar per picture: full for those shown, filling for the one on screen, empty for the rest.
class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.frame, required this.progress});

  final int count;
  final int frame;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: 3,
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) => Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: i < frame ? 1 : (i == frame ? progress.value : 0),
                        minHeight: 3,
                        backgroundColor: AppColors.onMedia24,
                        valueColor: const AlwaysStoppedAnimation(AppColors.onMedia),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
