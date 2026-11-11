import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';

/// Where a video tile is on the screen, as far as playing it is concerned.
class GridVideoSpot {
  const GridVideoSpot({
    required this.fraction,
    required this.top,
    required this.left,
    required this.scrolling,
  });

  /// How much of the tile can be seen (0..1): clipped by its list and by the screen.
  final double fraction;
  final double top, left;

  /// Its list is moving.
  final bool scrolling;
}

/// A video tile that can be played: the tile says where it is when asked, and takes the picture it is given.
class GridVideoSlot {
  GridVideoSlot(this.uri, this.probe, this.watchScroll);

  String uri;

  /// Null when the tile must not play: gone, covered by another screen, on a tab that is not showing, or with
  /// animations turned off.
  final GridVideoSpot? Function() probe;

  /// Starts or stops telling the controller when the tile's list moves. Only the one that is playing needs it.
  final void Function(bool on) watchScroll;
}

/// What is on show: the preview of [slot], with [controller] drawing it.
class GridVideoPlay {
  const GridVideoPlay(this.slot, this.controller);

  final GridVideoSlot slot;
  final VideoPlayerController controller;
}

/// Plays a short, silent preview of the videos in the grids: the first video in view plays (up to [cap]), then the
/// next one in view, and a video that scrolls away stops. Players are scarce, so there is one, disposed as soon as its
/// video ends, scrolls away, or anything else (the app leaving, a scan, battery saver, the switch in Settings) says
/// no. When the phone can run several video decoders, the next video is made ready beforehand.
class GridVideoController extends GetxController with WidgetsBindingObserver {
  /// A preview is never longer than this.
  static const Duration cap = Duration(seconds: 15);

  /// How much of a tile must be seen for it to start, and to go on playing.
  static const double startVisible = 0.6;
  static const double keepVisible = 0.45;

  static const Duration _tickEvery = Duration(milliseconds: 350);
  static const Duration _initTimeout = Duration(seconds: 8);
  static const Duration _envEvery = Duration(seconds: 20);
  static const String _prefsKey = 'grid_video_autoplay';

  /// The switch in Settings.
  bool enabled = true;

  /// What is on show, once its first frame is drawn (null the rest of the time).
  final ValueNotifier<GridVideoPlay?> playing = ValueNotifier(null);

  /// Whole seconds left of the preview that is on show.
  final ValueNotifier<int> remaining = ValueNotifier(0);

  final List<GridVideoSlot> _slots = [];

  /// The tiles that have played to the end and are still in view. They do not play again until they have left it.
  final Set<GridVideoSlot> _played = {};
  final Set<String> _failed = {};

  GridVideoSlot? _active;
  VideoPlayerController? _controller;
  Timer? _capTimer;

  /// The next video, made ready while the active one plays. Only phones with decoders to spare do this.
  GridVideoSlot? _next;
  VideoPlayerController? _nextController;
  GridVideoSlot? _preparing;

  /// Counts starts. An answer that comes back after something newer began is thrown away.
  int _gen = 0;
  int _nextGen = 0;

  /// How many players exist, from being made until they are released. However fast the list is scrolled, no more
  /// than [_maxLive] are ever alive. One that is slow to start or to release still counts.
  int _live = 0;
  static const int _maxLive = 3;

  Timer? _tick;
  bool _foreground = true;
  bool _powerSave = false;
  int _maxDecoders = 1;
  DateTime? _envAt;
  bool _envBusy = false;
  DateTime _lastScrollCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadEnabled());
    unawaited(_refreshEnv());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _tick = null;
    _stopAll();
    playing.dispose();
    remaining.dispose();
    super.onClose();
  }

  Future<void> _loadEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? true;
      update();
    } catch (e) {
      debugPrint('grid video: could not read the switch: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (!value) _stopAll();
    update();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('grid video: could not save the switch: $e');
    }
  }

  /// Asks the native side about power saving and the number of decoders. It is asked again after a failure only
  /// after a while, not at every tick.
  Future<void> _refreshEnv() async {
    if (_envBusy) return;
    _envBusy = true;
    try {
      final env = await MediaService().videoEnv();
      _powerSave = env.powerSave;
      _maxDecoders = env.maxDecoders;
      if (_powerSave) _stopAll();
    } catch (e) {
      debugPrint('grid video: videoEnv failed: $e');
    } finally {
      _envAt = DateTime.now();
      _envBusy = false;
    }
  }

  /// Stops everything when the app leaves the screen, so nothing keeps decoding. On return, videos that failed
  /// (the phone was busy, say) get another chance.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _failed.clear();
      unawaited(_refreshEnv());
      _syncTick();
    } else {
      _foreground = false;
      _stopAll();
      _syncTick();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _dropNext();
  }

  void register(GridVideoSlot slot) {
    if (_slots.contains(slot)) return;
    _slots.add(slot);
    _syncTick();
  }

  void unregister(GridVideoSlot slot) {
    _slots.remove(slot);
    _played.remove(slot);
    if (identical(_active, slot)) _stopActive();
    if (identical(_next, slot) || identical(_preparing, slot)) _dropNext();
    _syncTick();
  }

  /// The tile shows another video.
  void uriChanged(GridVideoSlot slot) {
    _played.remove(slot);
    if (identical(_active, slot)) _stopActive();
    if (identical(_next, slot) || identical(_preparing, slot)) _dropNext();
  }

  /// Checks that what plays is still fit to (a screen opened over it, say), without waiting for the next tick.
  void checkActive() {
    final active = _active;
    if (active != null && !_stillGood(active)) {
      _stopActive();
    }
  }

  /// The list of the playing tile moved: it stops at once if it has gone.
  void scrolled() {
    final now = DateTime.now();
    if (now.difference(_lastScrollCheck) < const Duration(milliseconds: 60)) {
      return;
    }
    _lastScrollCheck = now;
    final active = _active;
    if (active != null && !_stillGood(active)) _stopActive();
  }

  /// The tick runs only while there are tiles and the app is showing. It makes a few measurements every third of a
  /// second.
  void _syncTick() {
    final want = _slots.isNotEmpty && _foreground;
    if (want && _tick == null) {
      _tick = Timer.periodic(_tickEvery, (_) => _onTick());
    } else if (!want && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  bool get _allowed {
    if (!enabled || !_foreground || _powerSave) return false;
    if (Get.isRegistered<LibraryController>() &&
        Get.find<LibraryController>().isScanning) {
      return false;
    }
    return true;
  }

  bool _stillGood(GridVideoSlot slot) {
    final spot = slot.probe();
    return spot != null && spot.fraction >= keepVisible;
  }

  void _onTick() {
    try {
      _tickOnce();
    } catch (e) {
      debugPrint('grid video: tick failed: $e');
    }
  }

  void _tickOnce() {
    final env = _envAt;
    if (env == null || DateTime.now().difference(env) > _envEvery) {
      unawaited(_refreshEnv());
    }

    if (!_allowed) {
      _stopAll();
      return;
    }
    final active = _active;
    if (active != null && !_stillGood(active)) {
      _stopActive();
    }
    _forgetOutOfView();
    if (_active == null) {
      _pickAndStart();
    } else {
      _prepareNext();
    }
  }

  /// Lets a tile that is out of sight play again when it comes back.
  void _forgetOutOfView() {
    if (_played.isEmpty) return;
    _played.removeWhere((slot) {
      if (!_slots.contains(slot)) return true;
      final spot = slot.probe();
      return spot == null || spot.fraction < 0.2;
    });
  }

  /// The tiles that may start, the first in reading order first, or those after [after] when it is given. Rows are
  /// told apart with a little room, so tiles of one row keep left-to-right order.
  List<GridVideoSlot> _candidates({GridVideoSlot? after}) {
    final found = <(GridVideoSlot, GridVideoSpot)>[];
    for (final slot in _slots) {
      if (_played.contains(slot) ||
          _failed.contains(slot.uri) ||
          identical(slot, after)) {
        continue;
      }
      final spot = slot.probe();
      if (spot == null || spot.scrolling || spot.fraction < startVisible) {
        continue;
      }
      found.add((slot, spot));
    }
    found.sort((a, b) {
      final rowA = (a.$2.top / 8).round(), rowB = (b.$2.top / 8).round();
      return rowA != rowB
          ? rowA.compareTo(rowB)
          : a.$2.left.compareTo(b.$2.left);
    });
    var list = [for (final f in found) f.$1];
    if (after != null) {
      final spot = after.probe();
      if (spot != null) {
        list = [
          for (final f in found)
            if (_comesAfter(f.$2, spot)) f.$1,
        ];
      }
    }
    return list;
  }

  bool _comesAfter(GridVideoSpot s, GridVideoSpot of) {
    final rowS = (s.top / 8).round(), rowO = (of.top / 8).round();
    return rowS != rowO ? rowS > rowO : s.left > of.left;
  }

  /// Starts the first candidate, using the video made ready beforehand when it is that one. When there is nothing
  /// to play (covered, scrolled, all played) no player is kept ready either.
  void _pickAndStart() {
    final list = _candidates();
    if (list.isEmpty) {
      if (_next != null || _preparing != null) {
        _dropNext();
      }
      return;
    }
    final first = list.first;
    if (identical(first, _next) && _nextController != null) {
      _promoteNext();
    } else if (_live < _maxLive) {
      unawaited(_start(first));
    }
  }

  /// Makes a player and counts it as alive. It is silent and mixes with other audio, so it does not take the sound
  /// away from what the person is listening to.
  VideoPlayerController _make(String uri) {
    _live++;
    return VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  /// Starts the preview of [slot]. When something goes wrong after the player has become the active one, it is
  /// stopped the usual way.
  Future<void> _start(GridVideoSlot slot) async {
    final gen = ++_gen;
    _active = slot;
    final controller = _make(slot.uri);
    try {
      await controller.initialize().timeout(_initTimeout);
      if (gen != _gen) {
        unawaited(_safeDispose(controller));
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(false);
      if (gen != _gen) {
        unawaited(_safeDispose(controller));
        return;
      }
      _begin(slot, controller, gen);
    } catch (e) {
      debugPrint('grid video: could not play ${slot.uri}: $e');
      _failed.add(slot.uri);
      if (identical(_controller, controller)) {
        _stopActive();
      } else {
        unawaited(_safeDispose(controller));
        if (gen == _gen) _active = null;
      }
    }
  }

  /// Makes [controller], which is ready (initialised, silent), the active one.
  ///
  /// The video's own end or the cap ends the preview. The position is only reported every so often, so a timer also
  /// ends it.
  void _begin(GridVideoSlot slot, VideoPlayerController controller, int gen) {
    _controller = controller;
    controller.addListener(_onValue);
    slot.watchScroll(true);
    unawaited(
      controller.play().catchError((Object e) {
        debugPrint('grid video: play failed: $e');
      }),
    );
    final duration = controller.value.duration;
    final limit = duration > Duration.zero && duration < cap ? duration : cap;
    _capTimer?.cancel();
    _capTimer = Timer(limit + const Duration(milliseconds: 250), () {
      if (gen == _gen) _finish();
    });
    remaining.value =
        limit.inSeconds + (limit.inMilliseconds % 1000 > 0 ? 1 : 0);
    _limit = limit;
    _prepareNext();
  }

  Duration _limit = cap;

  /// Follows the active player. The preview is shown once it has really started, and until then the thumbnail
  /// stays, so nothing flashes black.
  void _onValue() {
    final c = _controller, slot = _active;
    if (c == null || slot == null) return;
    final v = c.value;
    if (v.hasError) {
      _failed.add(slot.uri);
      _stopActive();
      return;
    }
    if (playing.value == null &&
        v.isPlaying &&
        v.position >= const Duration(milliseconds: 80)) {
      playing.value = GridVideoPlay(slot, c);
    }
    final left = _limit - v.position;
    final secs = left <= Duration.zero
        ? 0
        : (left.inMilliseconds / 1000).ceil();
    if (secs != remaining.value) remaining.value = secs;
    if (v.isCompleted || left <= const Duration(milliseconds: 120)) _finish();
  }

  /// The preview has run its course: the next one starts.
  void _finish() {
    final slot = _active;
    if (slot == null) return;
    _played.add(slot);
    _stopActive();
    if (_allowed) _pickAndStart();
  }

  /// Stops and releases the active player. The notifiers change when no frame is being built. A tile that is going
  /// away stops its own preview.
  void _stopActive() {
    _gen++;
    _capTimer?.cancel();
    _capTimer = null;
    final slot = _active, c = _controller;
    _active = null;
    _controller = null;
    _whenIdle(() {
      if (_controller == null) {
        playing.value = null;
        remaining.value = 0;
      }
    });
    slot?.watchScroll(false);
    if (c != null) {
      c.removeListener(_onValue);
      unawaited(_safeDispose(c));
    }
  }

  /// Runs [change] at once, or after the frame when one is being built, because a notifier must not change in the
  /// middle of it.
  void _whenIdle(void Function() change) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      change();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => change());
    }
  }

  /// The one way a player is let go. The pause is sent first, so it stops decoding even if the release takes a
  /// moment.
  Future<void> _safeDispose(VideoPlayerController c) async {
    unawaited(c.pause().catchError((_) {}));
    try {
      await c.dispose();
    } catch (e) {
      debugPrint('grid video: dispose failed: $e');
    } finally {
      _live--;
    }
  }

  void _stopAll() {
    _stopActive();
    _dropNext();
  }

  bool get _canPrepare => _maxDecoders >= 4 && _allowed;

  /// Makes the next candidate ready, only when there is room to spare. A player still being released counts.
  void _prepareNext() {
    final active = _active;
    if (!_canPrepare || active == null || _controller == null) {
      if (_next != null || _preparing != null) _dropNext();
      return;
    }
    final list = _candidates(after: active);
    final want = list.isEmpty ? null : list.first;
    if (want == null) {
      _dropNext();
      return;
    }
    if (identical(want, _next) || identical(want, _preparing)) return;
    _dropNext();
    if (_live < 2) {
      unawaited(_prepare(want));
    }
  }

  Future<void> _prepare(GridVideoSlot slot) async {
    final gen = ++_nextGen;
    _preparing = slot;
    final controller = _make(slot.uri);
    try {
      await controller.initialize().timeout(_initTimeout);
      if (gen != _nextGen) {
        unawaited(_safeDispose(controller));
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(false);
      if (gen != _nextGen) {
        unawaited(_safeDispose(controller));
        return;
      }
      _next = slot;
      _nextController = controller;
      _preparing = null;
    } catch (e) {
      debugPrint('grid video: could not prepare ${slot.uri}: $e');
      _failed.add(slot.uri);
      unawaited(_safeDispose(controller));
      if (gen == _nextGen) _preparing = null;
    }
  }

  void _promoteNext() {
    final slot = _next, c = _nextController;
    if (slot == null || c == null) return;
    _next = null;
    _nextController = null;
    _preparing = null;
    _nextGen++;
    final gen = ++_gen;
    _active = slot;
    _begin(slot, c, gen);
  }

  void _dropNext() {
    _nextGen++;
    final c = _nextController;
    _next = null;
    _nextController = null;
    _preparing = null;
    if (c != null) unawaited(_safeDispose(c));
  }
}
