import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/collections/view/collection_screen.dart';
import 'package:lost_and_found/features/people/view/person_screen.dart';
import 'package:lost_and_found/features/viewer/view/widgets/media_chrome_button.dart';
import 'package:lost_and_found/core/widgets/new_tag.dart';
import 'package:lost_and_found/features/memories/features/stories/view/widgets/story_rings.dart';
import 'package:video_player/video_player.dart';
part 'story_viewer_screen/story_page.dart';
part 'story_viewer_screen/story_route.dart';
part 'story_viewer_screen/cube_face.dart';
part 'story_viewer_screen/look.dart';
part 'story_viewer_screen/ambient.dart';
part 'story_viewer_screen/story_loading.dart';

/// The stories, one ring after another. Each ring is a page; a story ends by turning to the next
/// ring like the face of a cube, and a swipe sideways does the same. Inside a story, a tap on the right
/// side goes to the next picture, a tap on the left to the one before, and holding pauses. Pulling down closes: the
/// picture follows the finger, moves, shrinks a little and gets round corners, and the black behind it gives way to
/// what is underneath.
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

  /// The flags that keep the story on screen from running: swiping or turning between rings, being pulled down, or the
  /// app being out of sight.
  bool _turning = false;
  bool _sliding = false;
  bool _dragging = false;
  bool _away = false;

  /// Where the picture has been pulled to, which follows the finger, and the animation that settles it back or sends it
  /// off the screen.
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

  /// Stops the story running while the app is out of sight.
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
      _turnTo(_current + 1);
    } else {
      _close();
    }
  }

  void _previousRing() {
    if (_turning || _current == 0) return;
    _turnTo(_current - 1);
  }

  /// Turns to [page]. With motion off the next story is simply there.
  void _turnTo(int page) {
    if (calm(context)) {
      _pages.jumpToPage(page);
    } else {
      _turn(_pages.animateToPage(page, duration: _turnTime, curve: Curves.easeInOutCubic));
    }
  }

  /// Ignores touches while the pages turn by themselves, because touching a page that is turning would stop it half way
  /// and let it fall back to where it was.
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

  /// Sets [_turning]. A scroll can start or end while the pages are being laid out, when the pages are told they cannot
  /// be dragged any more, say. Then the change waits for the end of the frame.
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

  /// The pointer being followed. Which way a touch is going is decided once, on its first few pixels. Mostly down is a
  /// pull and the picture follows the finger. Anything else belongs to the pages, so a sideways swipe turns to the next
  /// ring or the one before and never moves the picture, however much the finger drifts up or down on the way.
  int? _pointer;
  Offset _travel = Offset.zero;

  /// Whether the touch is a pull, and null until that is decided.
  bool? _pulling;
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
    setState(() => _dragging = true);
    _offset.value = Offset(0, dy);
  }

  /// Moves the picture with the finger. Pulling up is harder than pulling down, since only down closes.
  void _pull(double dy) {
    final up = dy < 0 && _offset.value.dy <= 0 ? dy * 0.35 : dy;
    _offset.value += Offset(0, up);
  }

  void _pullEnd(double velocityY) {
    final height = MediaQuery.sizeOf(context).height;
    final away = _offset.value.dy > height * 0.16 || velocityY > 700;
    if (away) {
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

  /// The button at the bottom. It shows the person's photos as a search, so they come up in the Search tab with the
  /// stories one tap away, or opens the person's or collection's own page. A name that two people share is not
  /// understood as either, so their own page is the way then.
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

    final pages = RepaintBoundary(
      child: IgnorePointer(
        ignoring: _sliding,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PageView.builder(
            controller: _pages,
            physics: _dragging ? const NeverScrollableScrollPhysics() : null,
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
