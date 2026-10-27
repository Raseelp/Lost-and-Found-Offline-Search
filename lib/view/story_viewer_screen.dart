import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/controllers/stories_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/collection_screen.dart';
import 'package:lost_and_found/view/person_screen.dart';
import 'package:lost_and_found/view/widget/media_chrome_button.dart';
import 'package:lost_and_found/view/widget/story_rings.dart';
import 'package:video_player/video_player.dart';

// Whether a video in a story is silent. It starts silent, and what the person chooses stays for the rest of the session.
final ValueNotifier<bool> _storiesMuted = ValueNotifier(true);

/// The route that opens the stories: a round window grows out of the ring that was tapped until it
/// fills the screen, and shrinks back into it on closing. (After a drag-down the picture has already
/// left the screen by itself, so there is nothing to shrink.)
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
        // Starts gently and ends gently: a curve that is fast at the start made the first frames jump.
        final t = Curves.easeInOutCubic.transform(animation.value);
        // Far enough to take in the corner that is furthest from the ring.
        final reach = [
          (from - Offset.zero).distance,
          (from - Offset(size.width, 0)).distance,
          (from - Offset(0, size.height)).distance,
          (from - Offset(size.width, size.height)).distance,
        ].reduce(math.max);
        final radius = originRadius + (reach - originRadius) * t;
        // No fade (a fade over the whole screen is drawn in a layer of its own, every frame): the window itself is the
        // entrance. The page is its own layer, so growing the window only changes what is cut out of it.
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

/// The stories, one ring after another. Each ring is a page; a story ends by turning to the next
/// ring like the face of a cube, and a swipe sideways does the same. Inside a story: tap the right
/// side for the next picture, the left for the one before, hold to pause. Pull down to close: the
/// picture follows the finger.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.rings, required this.initial});

  final List<StoryRing> rings;
  final int initial;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _turnTime = Duration(milliseconds: 520);

  late final PageController _pages = PageController(initialPage: widget.initial);
  int _current = 0;

  // What keeps the story on screen from running: swiping or turning between rings, being pulled
  // down, or the app being out of sight.
  bool _turning = false;
  bool _sliding = false;
  bool _dragging = false;
  bool _away = false;

  // Where the picture has been pulled to (it follows the finger), and the animation that settles
  // it back, or sends it off the screen.
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);
  late final AnimationController _settle = AnimationController(vsync: this);
  Offset _settleFrom = Offset.zero;
  Offset _settleTo = Offset.zero;
  Curve _settleCurve = Curves.easeOutCubic;

  bool get _playing => !_turning && !_dragging && !_away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _current = widget.initial;
    _settle.addListener(() {
      _offset.value = Offset.lerp(_settleFrom, _settleTo, _settleCurve.transform(_settle.value))!;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  // Not running while the app is out of sight.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away != _away) setState(() => _away = away);
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  void _nextRing() {
    if (_turning) return;
    if (_current + 1 < widget.rings.length) {
      _turn(_pages.nextPage(duration: _turnTime, curve: Curves.easeInOutCubic));
    } else {
      _close();
    }
  }

  void _previousRing() {
    if (_turning || _current == 0) return;
    _turn(_pages.previousPage(duration: _turnTime, curve: Curves.easeInOutCubic));
  }

  // While the pages turn by themselves a touch is ignored: touching a page that is turning would stop it
  // half way and let it fall back to where it was.
  void _turn(Future<void> turning) {
    setState(() => _sliding = true);
    turning.whenComplete(() {
      if (mounted) setState(() => _sliding = false);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _setTurning(true);
    } else if (n is ScrollEndNotification) {
      _setTurning(false);
    }
    return false;
  }

  // A scroll can start or end while the pages are being laid out (the pages are told they cannot be dragged any
  // more, say): then the change waits for the end of the frame.
  void _setTurning(bool value) {
    if (_turning == value) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _turning != value) setState(() => _turning = value);
      });
    } else {
      setState(() => _turning = value);
    }
  }

  // Which way a touch is going is decided once, on its first few pixels: mostly down is a pull and the
  // picture follows the finger; anything else belongs to the pages, so a sideways swipe turns to the next
  // or the one before and never moves the picture, however much the finger drifts up or down on the way.
  int? _pointer;
  Offset _travel = Offset.zero;
  bool? _pulling; // null until decided
  VelocityTracker _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);

  void _pointerDown(PointerDownEvent e) {
    if (_pointer != null || _sliding) return;
    _pointer = e.pointer;
    _travel = Offset.zero;
    _pulling = null;
    _velocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || _pulling == false) return;
    _velocity.addPosition(e.timeStamp, e.position);
    if (_pulling == true) {
      _pull(e.delta.dy);
      return;
    }
    _travel += e.delta;
    if (_travel.distance < 10) return;
    if (_travel.dy > 0 && _travel.dy > _travel.dx.abs() * 1.5) {
      _pulling = true;
      _pullStart(_travel.dy);
    } else {
      _pulling = false;
    }
  }

  void _pointerEnd(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final pulled = _pulling == true;
    _pointer = null;
    _pulling = null;
    if (pulled) _pullEnd(_velocity.getVelocity().pixelsPerSecond.dy);
  }

  void _pullStart(double dy) {
    _settle.stop();
    // The pages are not to scroll under a pull.
    setState(() => _dragging = true);
    _offset.value = Offset(0, dy);
  }

  // The picture goes with the finger. Pulling up is harder than pulling down, since only down closes.
  void _pull(double dy) {
    final up = dy < 0 && _offset.value.dy <= 0 ? dy * 0.35 : dy;
    _offset.value += Offset(0, up);
  }

  void _pullEnd(double velocityY) {
    final height = MediaQuery.sizeOf(context).height;
    final away = _offset.value.dy > height * 0.16 || velocityY > 700;
    if (away) {
      // Carries on out of the screen the way it was going.
      _runSettle(
        Offset(0, height),
        const Duration(milliseconds: 230),
        Curves.easeInCubic,
        onDone: () {
          final route = ModalRoute.of(context);
          if (route is StoryRoute) route.dragged = true;
          _close();
        },
      );
    } else {
      _runSettle(
        Offset.zero,
        const Duration(milliseconds: 320),
        Curves.easeOutBack,
        onDone: () {
          setState(() => _dragging = false);
        },
      );
    }
  }

  void _runSettle(Offset to, Duration duration, Curve curve, {required VoidCallback onDone}) {
    _settleFrom = _offset.value;
    _settleTo = to;
    _settleCurve = curve;
    _settle
      ..duration = duration
      ..forward(from: 0).whenComplete(() {
        if (mounted) onDone();
      });
  }

  // The button at the bottom: the person's photos as a search (so they come up in the Search tab,
  // with the stories one tap away), or the person's or collection's own page.
  void _act(StoryRing ring) {
    final navigator = Navigator.of(context);
    final native = Get.find<NativeController>();

    if (ring.kind == StoryKind.collection) {
      Get.find<CollectionsController>().openCollection(ring.collection!);
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => const CollectionScreen()));
      return;
    }

    final person = ring.person!;
    if ((person.name ?? '').trim().isNotEmpty) {
      native.setSearchPhotoMode(false);
      native.searchTextController.text = person.name!;
      // A name that two people share is not understood as either: their own page is the way then.
      if (native.searchTextController.recognizedPeople.any((p) => p.id == person.id)) {
        navigator.pop();
        native.runSearch();
        return;
      }
      native.searchTextController.clear();
    }
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => PersonScreen(person: person)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Its own layer: while the picture is pulled or the pages turn, the page is moved as it is, not drawn again.
    final pages = RepaintBoundary(
      child: IgnorePointer(
        ignoring: _sliding,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PageView.builder(
            controller: _pages,
            physics: _dragging ? const NeverScrollableScrollPhysics() : null,
            // The next ring is built beside this one, so its first picture is ready when it turns in.
            allowImplicitScrolling: true,
            itemCount: widget.rings.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) => _CubeFace(
              controller: _pages,
              index: i,
              initial: widget.initial,
              child: _StoryPage(
                key: ValueKey(widget.rings[i].key),
                ring: widget.rings[i],
                active: i == _current,
                playing: _playing,
                hasPrevious: i > 0,
                onNextRing: _nextRing,
                onPreviousRing: _previousRing,
                onAction: () => _act(widget.rings[i]),
                onClose: _close,
              ),
            ),
          ),
        ),
      ),
    );

    // The picture follows the finger as it is pulled down: it moves, shrinks a little and gets
    // round corners, and the black behind it gives way to what is underneath.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kMediaOverlayStyle,
      child: Material(
        type: MaterialType.transparency,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerEnd,
          onPointerCancel: _pointerEnd,
          child: ValueListenableBuilder<Offset>(
            valueListenable: _offset,
            child: pages,
            builder: (context, offset, child) {
              final p = (offset.distance / (size.height * 0.45)).clamp(0.0, 1.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.mediaBackdrop.withValues(alpha: 1 - 0.9 * p)),
                  // One transform (move and shrink together) over the page's own layer.
                  Transform(
                    alignment: Alignment.center,
                    transform:
                        Matrix4.translationValues(offset.dx, offset.dy, 0) *
                        Matrix4.diagonal3Values(1 - 0.3 * p, 1 - 0.3 * p, 1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32 * p),
                      child: ColoredBox(color: AppColors.mediaBackdrop, child: child),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One ring's page turned as the face of a cube: the page leaving swings away on its far edge while
/// the one coming in swings round to meet it, and the one going dims as it turns from you.
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
        // -1 one page to the left, 0 in front, 1 one page to the right.
        final delta = (index - page).clamp(-1.0, 1.0);
        // The same widgets whether the page is in front or turning (when it is in front the transform is
        // plain): a page that changed its place in the tree would be built again, and its story with it.
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

/// One ring's story: its pictures one after the other, the bars on top, who it is, and the button.
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

  // A video plays from the moment that was picked for it (or the start, if little would be left) for as long as
  // it lasts, but not longer than this, and not shorter than the minimum.
  static const Duration _videoCap = Duration(seconds: 15);
  static const Duration _videoMin = Duration(seconds: 2);

  final StoriesController _stories = Get.find<StoriesController>();
  late final AnimationController _progress;

  int _frame = 0;

  // Null while the story's pictures are being found.
  List<StoryFrame>? _frames;

  // How the story's pictures were chosen ("New this week"), when it says.
  String? _caption;
  final Map<int, Uint8List> _bytes = {};
  final Set<int> _failed = {};

  // What each picture looks like from far away (its colours and shape), and the ring's own face or cover, for the
  // loading picture.
  final Map<int, _Look> _looks = {};
  _Look? _coverLook;

  // The route that shows the page, while it is still opening.
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeListener;
  bool _held = false;
  bool _gone = false;

  // The player of the video on screen (only the ring on screen has one), whether it is ready, whether its
  // picture has taken over from the still, and a count of starts so a player that arrives late is dropped.
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
    _progress = AnimationController(vsync: this, duration: _frameTime)..addStatusListener(_onProgress);
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
      // Turned to: starts from its first picture.
      if (_frames != null) unawaited(_stories.markViewed(widget.ring));
      _frame = 0;
      _enterFrame();
    } else if (!widget.active && old.active) {
      _pause();
      // Another ring is on screen: this one lets its player go (they are scarce).
      _releaseVideo();
    } else if (widget.playing != old.playing) {
      if (_canRun) {
        _resume();
      } else {
        _pause();
      }
    }
  }

  // The page is built while its route is still opening; what it asks of the phone (the pictures of a ring, their dates,
  // the thumbnails) waits for the opening to end, so it does not take frames from it.
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

  // Rings are made ready one at a time: the one on screen first, the ones beside it after. Each asks the phone for
  // everything a person or collection holds, and several at once would take a lot of frames from the story that is playing.
  static Future<void> _queue = Future<void>.value();

  Future<StoryEdition> _edition() async {
    final before = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await before;
      if (_gone) return StoryEdition.empty;
      // Not for ever: one ring that never answers must not keep the rings behind it from being made ready.
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

  Future<void> _load() async {
    await _routeSettled();
    if (_gone) return;
    final edition = await _edition();
    if (_gone) return;
    final frames = edition.frames;
    setState(() {
      _frames = frames;
      _caption = edition.caption;
    });
    // Its story is there: opening it is what greys the ring (once the story exists to be opened).
    if (widget.active) unawaited(_stories.markViewed(widget.ring));
    // The first picture before anything else; the rest one after another behind it.
    for (var k = 0; k < frames.length; k++) {
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

  // The picture shown now is there (or has failed): start its time, or move past it.
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

  // Plays the video of the picture on screen over its still. Until it is ready the still is what is shown
  // (it is the same moment), and if it cannot be played the still is shown for the usual time.
  Future<void> _startVideo() async {
    final run = ++_videoRun;
    final frame = _frames![_frame];
    final player = VideoPlayerController.contentUri(
      Uri.parse(frame.uri),
      // It must not take the sound away from what the person is listening to.
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

  Future<void> _playVideo(VideoPlayerController player, int run) async {
    await player.play();
    if (_videoShown) return;
    // A moment for its first picture to be there, then it takes over from the still.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!_gone && run == _videoRun) setState(() => _videoShown = true);
  }

  // Lets the player go (a later start that finds the count changed lets go of its own). The picture of it is taken
  // off the screen first and the player is released after that frame, never while something still draws it.
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

  Future<void> _disposeVideo(VideoPlayerController player) async {
    // Sent first, so it stops playing even if letting go takes a moment.
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
      // Still starting: it starts the time itself when it is ready.
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

  // What the loading picture is made from: the colours of the last picture of this story that is there, else the ring's
  // own face or cover.
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
            // A screen reader goes through the pictures with these (the sides of the picture are not buttons for it).
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
          // Shades so the bars and the button read on any picture.
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
                      // The ring turns while the story is being found.
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
                            Text(
                              _caption ?? '${ring.count} photos and videos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onMedia70),
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
    // A video plays over its still once it has a picture of its own.
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
          // Behind the picture: its own colours, top to bottom and a little from each side, so whatever the
          // picture does not cover looks like a continuation of it (nothing is stretched, so nothing is blocky).
          _Ambient(look: look),
          if (look == null)
            Positioned.fill(child: still)
          else
            // The picture is a card with round corners that glows in its own colour.
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

const double _cardRadius = 22;

/// What a picture looks like from far away: its colours at the top, the middle, the bottom and the two sides (worked
/// out from a picture of 3 by 3 pixels, so it is smooth however large it is drawn), and its shape. Used to paint
/// the screen round the picture.
class _Look {
  const _Look({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.left,
    required this.right,
    required this.glow,
    required this.aspect,
  });

  final Color top, middle, bottom, left, right, glow;

  /// Width over height of the picture.
  final double aspect;

  static Future<_Look?> of(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) return null;
      codec = await descriptor.instantiateCodec(targetWidth: 3, targetHeight: 3);
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      Color at(int row, int col) {
        final i = (row * 3 + col) * 4;
        return Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      }

      Color mean(List<Color> colors) {
        var r = 0, g = 0, b = 0;
        for (final c in colors) {
          r += (c.r * 255).round();
          g += (c.g * 255).round();
          b += (c.b * 255).round();
        }
        return Color.fromARGB(255, r ~/ colors.length, g ~/ colors.length, b ~/ colors.length);
      }

      final centre = mean([
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++) at(r, c),
      ]);
      return _Look(
        top: _deepen(mean([at(0, 0), at(0, 1), at(0, 2)])),
        middle: _deepen(mean([at(1, 0), at(1, 1), at(1, 2)])),
        bottom: _deepen(mean([at(2, 0), at(2, 1), at(2, 2)])),
        left: _deepen(mean([at(0, 0), at(1, 0), at(2, 0)])),
        right: _deepen(mean([at(0, 2), at(1, 2), at(2, 2)])),
        glow: HSLColor.fromColor(centre).withLightness(0.5).withSaturation(0.7).toColor(),
        aspect: descriptor.width / descriptor.height,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  // The colour made darker and a little richer, so white writing on it can be read whatever the picture is.
  static Color _deepen(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.1, 0.32))
        .withSaturation((hsl.saturation * 1.1).clamp(0.0, 0.85))
        .toColor();
  }
}

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

/// What is on screen while a picture is on its way: the colours of the last picture of the story (or of the face or
/// cover of the ring), breathing a little darker and lighter, with a pale band of light sliding across. When the
/// picture arrives it fades in over it. Only colours are drawn - no blurred picture, nothing to work out again and
/// again while a window is opening.
class _StoryLoading extends StatefulWidget {
  const _StoryLoading({this.look});

  final _Look? look;

  @override
  State<_StoryLoading> createState() => _StoryLoadingState();
}

class _StoryLoadingState extends State<_StoryLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _run;

  @override
  void initState() {
    super.initState();
    _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Ambient(look: widget.look),
        // Only these move, and they are a layer of their own.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _run,
            builder: (context, _) {
              final t = _run.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Breathes: a little darker, a little lighter.
                  ColoredBox(color: AppColors.scrim.withValues(alpha: 0.12 + 0.1 * math.sin(t * 2 * math.pi))),
                  // The band of light, left to right.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-2.2 + 4.4 * t, -1),
                        end: Alignment(-0.8 + 4.4 * t, 1),
                        colors: [
                          AppColors.onMedia.withValues(alpha: 0),
                          AppColors.onMedia.withValues(alpha: 0.14),
                          AppColors.onMedia.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

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

// One bar per picture: full for those shown, filling for the one on screen, empty for the rest.
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
