import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/features/library/view/widgets/scan_palette.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/features/library/view/widgets/chip_art.dart';
import 'package:lost_and_found/core/native/device_service.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
part 'scan_square/shared.dart';
part 'scan_square/square_painter.dart';
part 'scan_square/bento_layouts.dart';
part 'scan_square/complete_texts.dart';
part 'scan_square/scan_story.dart';
part 'scan_square/ruler_painter.dart';

/// The Library page's scanning hero: a rounded square that is the scan, with the indexing progress as its teal
/// outline. The photos indexed since the last round (up to six) are cut into patches that light as they are read, then
/// drop into the strip underneath, the queue of photos waiting for their faces, whose plum outline fills as the queue
/// nears the next face batch. When the batch starts, the queued photos rise into the square, their faces are found and
/// lifted out one by one, and each travels to the person it matches along the bottom (a face nobody matches starts a
/// person).
class SquareScanHero extends StatefulWidget {
  const SquareScanHero({
    super.key,
    required this.progress,
    required this.photos,
    required this.semanticsLabel,
    required this.loadPhoto,
    this.faceMode = false,
    this.faceProgress,
    this.events = const [],
    this.queue,
    this.discovered,
    this.rate = 0,
    this.stats,
    this.mode = ScanChipMode.scanning,
    this.onStart,
    this.onDismiss,
    this.summary,
    this.idleHint = 'TAP TO SCAN',
  });

  /// What the lid says while waiting to be tapped.
  final String idleHint;

  /// Indexing's progress, 0..1 (null while the folder is still being walked).
  final double? progress;

  /// The latest indexed photos, newest first.
  final List<OrbitPhoto> photos;
  final String semanticsLabel;
  final Future<Uint8List?> Function(String uri) loadPhoto;

  /// Indexing is paused while the faces of a batch are found.
  final bool faceMode;
  final double? faceProgress;

  /// Faces found in the batch, newest first.
  final List<FaceEvent> events;

  /// The queue of photos waiting for the next face batch (null if faces do not follow).
  final OrbitQueueInfo? queue;

  /// While the folder is still being walked: how many files it has found so far.
  final int? discovered;

  /// How fast photos are being indexed (per second): how busy the connections look.
  final double rate;

  /// The numbers the story under the chip tells.
  final ScanChipStats? stats;

  /// Idle (a tap on the chip starts a scan), scanning, or done (a tap dismisses it).
  final ScanChipMode mode;
  final VoidCallback? onStart;
  final VoidCallback? onDismiss;
  final ScanChipSummary? summary;

  @override
  State<SquareScanHero> createState() => _SquareScanHeroState();
}

class _SquareScanHeroState extends State<SquareScanHero>
    with SingleTickerProviderStateMixin {
  /// Seconds since the hero appeared (a year long, so it never runs out).
  static const _clockSeconds = 365.0 * 24 * 3600;
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(days: 365),
  )..addListener(_step);
  double get _now => _clock.value * _clockSeconds;

  bool _still = false;

  /// The clock runs only while something on the chip moves: a scan, the lid, a wire fading, the
  /// reflection following the phone. A chip at rest under its lid draws nothing at all.
  void _wake() {
    if (!mounted || _still || _clock.isAnimating) return;
    _clock.forward();
  }

  bool _animating() {
    if (_still) return false;
    if (_mode != ScanChipMode.idle) return true;
    if (_lid > 0 || (_bootAt >= 0 && _now - _bootAt < 3.4)) return true;
    if (_idleAmt < .998 || _scanAmt > .002 || _doneAmt > .002) return true;
    if ((_clipAlpha - 1).abs() > .002 || (_faceAlpha - .5).abs() > .002) return true;
    for (var i = 0; i < chipWireCount; i++) {
      if (_wireClip[i] > .002 || _wireFace[i] > .002) return true;
    }
    if (!_tiltLive) return true;
    return (_tilt - _tiltTarget).distance > .002;
  }

  late ScanChipMode _mode = widget.mode;
  /// How much of each state is showing (they cross-fade when the state changes).
  late double _idleAmt = widget.mode == ScanChipMode.idle ? 1 : 0;
  late double _scanAmt = widget.mode == ScanChipMode.scanning ? 1 : 0;
  late double _doneAmt = widget.mode == ScanChipMode.complete ? 1 : 0;
  double _bootAt = -100;
  double _completeAt = -100;
  bool _dismissed = false;
  bool _pressed = false;
  Timer? _dismissTimer;
  /// How the phone is held, for the light on the lid (from the accelerometer, while the lid is on and in view; without
  /// one the lid just glints from time to time).
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  Offset _tilt = Offset.zero, _tiltTarget = Offset.zero;
  Offset? _tiltBase, _tiltFilter;
  bool _tiltLive = false;
  bool _inView = true;

  /// Follows how the phone is held, as gravity smoothed so that shaking and small movements do not reach the
  /// reflection, with a small dead band so that holding it still keeps it still. The way it is held becomes the middle
  /// again over many seconds. Full swing is at about a quarter of the way to tipping the phone on its side.
  void _syncTilt() {
    final want = _mode != ScanChipMode.scanning && !_still && _inView;
    if (!want) {
      _tiltSub?.cancel();
      _tiltSub = null;
      _tiltLive = false;
      _wake();
      return;
    }
    if (_tiltSub != null) return;
    try {
      _tiltSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (e) {
          final raw = Offset(e.x, e.y) / 9.81;
          _tiltFilter = _tiltFilter == null ? raw : Offset.lerp(_tiltFilter!, raw, .12);
          _tiltBase = _tiltBase == null ? _tiltFilter : Offset.lerp(_tiltBase!, _tiltFilter!, .004);
          var d = _tiltFilter! - _tiltBase!;
          double dead(double v) => v.abs() < .03 ? 0 : v - v.sign * .03;
          d = Offset(dead(d.dx), dead(d.dy));
          _tiltTarget = Offset((-d.dx / .42).clamp(-1.0, 1.0), (d.dy / .42).clamp(-1.0, 1.0));
          final wasLive = _tiltLive;
          _tiltLive = true;
          if (!wasLive || (_tilt - _tiltTarget).distance > .002) _wake();
        },
        onError: (Object _) {
          _tiltLive = false;
          _tiltSub?.cancel();
          _tiltSub = null;
          _wake();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _tiltLive = false;
      _wake();
    }
  }

  /// How far the lid is off (0 closed, 1 gone), and what is etched on it.
  double _lid = 0;
  ChipLidText _lidIdle = const ChipLidText(above: 'ON-DEVICE', big: 'VISION', below: 'PRIVATE AI', hint: 'TAP TO SCAN');
  ChipLidText? _lidDone;

  _Shot? _shot;
  /// The strip: photos read and waiting for their faces, oldest first.
  final List<_QTile> _queue = [];
  double _fill = 0;
  /// How much of each bond wire has been bonded, in the two rows (CLIP along the top, FACE along
  /// the bottom), and how bright each row is.
  final List<double> _wireClip = List.filled(chipWireCount, 0);
  final List<double> _wireFace = List.filled(chipWireCount, 0);
  double _clipAlpha = 1, _faceAlpha = .5;
  /// The two rows of wires are lanes of a link between the die (or the memory bank) and the board. The scan brings
  /// them up one after another (a lane coming up trains, with a pattern running along it, and flashes when it locks),
  /// and data packets run along the lanes that are up, as many as indexing really moves. The memory array along the
  /// top of the bank fills a cell at a time as items are stored, much finer than the lanes, so even a big library
  /// visibly moves.
  final List<_Packet> _packets = [];
  /// The lane each row is bringing up at the moment, or -1.
  final List<int> _training = [-1, -1];
  final List<double> _trainFraction = [0, 0];
  /// When each lane last locked (for the flash along it), and how many were up when last looked.
  final List<List<double>> _lockAt = [
    List.filled(chipWireCount, -100.0),
    List.filled(chipWireCount, -100.0),
  ];
  final List<int> _lanesUp = [-1, -1];
  final List<double> _packetDebt = [0, 0];
  /// The cells of the memory array that have been written, and when the latest were.
  int _cellsWritten = 0;
  final Map<int, double> _cellWrittenAt = {};

  double _lastStep = 0;
  /// Since when no photo has been in the square (it then shows that it is waiting).
  double _idleSince = -100;
  /// When this scan began, and when the model of each kind (0: photos, 1: faces) began to load.
  double _scanAt = -100;
  /// Cores to a row of the die: as many as the phone has (two rows).
  int _dieColumns = 4;
  final List<double> _loadStart = [-1, -1];
  /// At the start of a face batch the strip's photos rise into the square; they are then the
  /// photos the faces are looked for in.
  List<_QTile> _launch = [];
  double _launchAt = -100;
  List<_Pic> _batchPics = [];
  final Set<String> _shown = {};
  bool _starting = false;
  final Map<String, Future<_Pic?>> _pics = {};
  final math.Random _random = math.Random();
  final Map<int, int> _lastLayout = {};

  _FaceShot? _faceShot;
  final List<_FaceGroup> _groups = [];
  final Set<int> _seenFaces = {};
  final List<_Person?> _tray = List.filled(_traySlots, null);
  bool _wasFaceMode = false;

  /// Starts the hero. What is already there when it appears is not replayed. The core count is known after the marks
  /// load, and the pictures of everything under the lid are made then, a little apart, before anyone has tapped.
  @override
  void initState() {
    super.initState();
    _wasFaceMode = widget.faceMode;
    for (final photo in widget.photos) {
      _shown.add(photo.id);
    }
    for (final e in widget.events) {
      _seenFaces.add(e.id);
    }
    if (_mode == ScanChipMode.complete) _completeAt = 0;
    _loadMarks().whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) await warmChipInside(_photoBox, _strip, _dieColumns);
    });
  }

  Future<void> _loadMarks() async {
    final chip = await DeviceService().deviceChip();
    if (chip == null || !mounted) return;
    String clean(Object? v) => (v as String? ?? '').trim();
    var maker = clean(chip['maker']).toUpperCase();
    if (maker == 'QTI' || maker == 'QUALCOMM TECHNOLOGIES, INC') maker = 'QUALCOMM';
    var model = clean(chip['model']).toUpperCase();
    if (model.isEmpty || model == 'UNKNOWN') model = clean(chip['hardware']).toUpperCase();
    final cores = (chip['cores'] as num?)?.toInt() ?? 0;
    final abi = switch (clean(chip['abi'])) {
      'arm64-v8a' => 'ARM64',
      'armeabi-v7a' => 'ARMV7',
      'x86_64' => 'X86-64',
      final other => other.toUpperCase(),
    };
    final parts = [if (cores > 0) '$cores CORES', if (abi.isNotEmpty) abi];
    final mhz = (chip['maxMhz'] as num?)?.toInt() ?? 0;
    final ramMb = (chip['ramMb'] as num?)?.toInt() ?? 0;
    final release = clean(chip['release']);
    final speed = [
      if (mhz > 0) '${(mhz / 1000).toStringAsFixed(mhz % 1000 == 0 ? 0 : 1)} GHZ MAX',
      if (ramMb > 0) '${(ramMb / 1024).round()} GB RAM',
    ];
    setState(() {
      if (cores > 0) _dieColumns = chipDieColumns(cores);
      _lidIdle = ChipLidText(
        above: maker.isEmpty || maker == 'UNKNOWN' ? 'ON-DEVICE' : maker,
        big: model.isEmpty ? 'VISION' : model,
        below: parts.isEmpty ? 'PRIVATE AI' : parts.join(' · '),
        extras: [
          if (speed.isNotEmpty) speed.join(' · '),
          if (release.isNotEmpty) 'ANDROID $release',
        ],
        hint: 'TAP TO SCAN',
      );
    });
  }

  /// Makes the chip's pictures as sharp as this screen can show. With reduced motion nothing moves by itself: the
  /// square only changes when the scan reports something (see [didUpdateWidget]).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _inView = TickerMode.of(context);
    setChipArtScale(MediaQuery.devicePixelRatioOf(context));
    _syncTilt();
    if (_still) {
      _clock.stop();
    } else {
      _wake();
    }
  }

  /// The state of the chip changed: what belonged to the last scan goes, and a finished scan
  /// announces itself.
  void _changeMode(ScanChipMode to) {
    _mode = to;
    _syncTilt();
    _dismissTimer?.cancel();
    _shot = null;
    _queue.clear();
    _launch = [];
    _batchPics = [];
    _groups.clear();
    _faceShot = null;
    _fill = 0;
    _idleSince = _now;
    if (to == ScanChipMode.scanning) _scanAt = _now;
    _loadStart[0] = _loadStart[1] = -1;
    _wasFaceMode = widget.faceMode;
    _shown
      ..clear()
      ..addAll(widget.photos.map((p) => p.id));
    for (final e in widget.events) {
      _seenFaces.add(e.id);
    }
    for (var i = 0; i < _tray.length; i++) {
      _tray[i] = null;
    }
    if (to == ScanChipMode.complete) {
      _completeAt = _now;
      _dismissed = false;
      HapticFeedback.mediumImpact();
      // With reduced motion the clock does not run, so the wait is by the wall clock.
      if (_still) {
        _dismissTimer = Timer(const Duration(seconds: 8), () {
          if (mounted && _mode == ScanChipMode.complete) widget.onDismiss?.call();
        });
      }
    }
  }

  static String _thousands(int n) {
    final digits = '$n';
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// What is etched on the lid when a scan has finished.
  ChipLidText? _doneText(ScanChipSummary? summary) {
    if (summary == null) return _lidDone;
    final extra = [
      if (summary.people > 0) '${summary.people} ${summary.people == 1 ? 'PERSON' : 'PEOPLE'}',
      if (summary.failed > 0) '${summary.failed} UNREADABLE',
    ];
    return ChipLidText(
      above: 'SCAN COMPLETE',
      big: _thousands(summary.indexed),
      below: 'ITEMS INDEXED',
      extras: extra,
      hint: 'TAP TO CLOSE',
    );
  }

  void _tap() {
    if (_mode == ScanChipMode.idle) {
      HapticFeedback.lightImpact();
      _bootAt = _now;
      _wake();
      widget.onStart?.call();
    } else if (_mode == ScanChipMode.complete) {
      widget.onDismiss?.call();
    }
  }

  @override
  void didUpdateWidget(SquareScanHero old) {
    super.didUpdateWidget(old);
    _wake();
    if (widget.mode != _mode) _changeMode(widget.mode);
    _lidDone = _doneText(widget.summary);
    if (_mode != ScanChipMode.scanning) {
      if (_still) _step();
      return;
    }
    if (widget.faceMode != _wasFaceMode) {
      _wasFaceMode = widget.faceMode;
      _finishShot();
      _groups.clear();
      _faceShot = null;
      if (widget.faceMode) {
        for (final e in widget.events) {
          _seenFaces.add(e.id);
        }
        _launch = [..._queue];
        _launchAt = _now;
        _batchPics = [for (final tile in _queue) tile.pic];
        _queue.clear();
      } else {
        _fill = 0;
        _launch = [];
        _batchPics = [];
      }
    }
    if (widget.faceMode) _ingestFaces();
    if (_still) _step();
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    _dismissTimer?.cancel();
    _clock.dispose();
    _releaseImages();
    super.dispose();
  }

  /// The photos the hero decoded are freed with it (not left for the garbage collector, which
  /// would hold their memory for a while). Each is freed once, whatever shows it.
  void _releaseImages() {
    final freed = <ui.Image>{};
    void free(_Pic? pic) {
      if (pic != null && freed.add(pic.image)) pic.image.dispose();
    }

    for (final group in _groups) {
      free(group.pic);
    }
    free(_faceShot?.pic);
    for (final person in _tray) {
      free(person?.pic);
    }
    for (final decoding in _pics.values) {
      decoding.then(free);
    }
    _pics.clear();
  }

  Future<_Pic?> _ensure(String id, Uint8List bytes) {
    final cached = _pics[id];
    if (cached != null) return cached;
    if (_pics.length > 24) _pics.remove(_pics.keys.first);
    return _pics[id] = _decodePic(bytes);
  }

  /// Where tile [i] of [m] sits: spread out, then overlapping once there are too many.
  double _layoutX(int i, int m) {
    if (m <= 1) return _queueLeft;
    final step = math.min(_tileSize + 4, (_queueRight - _queueLeft - _tileSize) / (m - 1));
    return _queueLeft + i * step;
  }

  /// Where photo [i] of the ones being read lands in the strip.
  double landingX(int i) {
    final n = _shot?.pics.length ?? 1;
    return _layoutX(_queue.length + i, _queue.length + n);
  }

  /// What the two rows of bond wires show. The top row (CLIP, gold) is the indexing: wires bond one after another as
  /// the scan advances, or, while the folder is still being walked, a run of bonding goes back and forth. The bottom
  /// row (FACE, copper) is the faces: dimly the queue of photos waiting for their faces while indexing, brightly the
  /// batch during a batch. A finished scan bonds both rows. A wire that is not wanted any more is drawn back a little
  /// slower than it was drawn, which leaves a trail behind a moving run.
  final List<double> _clipTarget = List.filled(chipWireCount, 0);
  final List<double> _faceTarget = List.filled(chipWireCount, 0);

  void _updateWires(double now, double dt) {
    final clip = _clipTarget..fillRange(0, chipWireCount, 0);
    final face = _faceTarget..fillRange(0, chipWireCount, 0);
    double fill(double n, int i) => (n - i).clamp(0.0, 1.0);
    double run(int i, double speed, double phase) {
      final span = chipWireCount - 1;
      final x = (now * speed + phase) % (2 * span);
      final at = x <= span ? x : 2 * span - x;
      return math.max(0.0, 1 - (i - at).abs() / 2.2);
    }

    var clipAlpha = 1.0, faceAlpha = .5;
    switch (_mode) {
      case ScanChipMode.scanning:
        final progress = widget.progress;
        final batch = widget.faceMode;
        for (var i = 0; i < chipWireCount; i++) {
          clip[i] = progress == null ? run(i, 15, 0) : fill(progress * chipWireCount, i);
          if (batch) {
            final fp = widget.faceProgress;
            face[i] = fp == null ? run(i, 15, chipWireCount.toDouble()) : fill(fp * chipWireCount, i);
          } else if (widget.queue != null) {
            face[i] = fill(_fill * chipWireCount, i);
          }
        }
        if (batch) {
          clipAlpha = .45;
          faceAlpha = 1;
        }
      case ScanChipMode.complete:
        final t = now - _completeAt;
        final n = Curves.easeOutCubic.transform((t / 1.1).clamp(0.0, 1.0)) * chipWireCount;
        for (var i = 0; i < chipWireCount; i++) {
          clip[i] = fill(n, i);
          face[i] = fill(n, i);
        }
        faceAlpha = 1;
      case ScanChipMode.idle:
        break;
    }
    final since = now - _bootAt;
    if (_bootAt >= 0 && since < 1.4 && _mode != ScanChipMode.complete) {
      final n = (since / .6).clamp(0.0, 1.0) * chipWireCount;
      final fade = 1 - ((since - .6) / .8).clamp(0.0, 1.0);
      for (var i = 0; i < chipWireCount; i++) {
        clip[i] = math.max(clip[i], fill(n, i) * fade);
        face[i] = math.max(face[i], fill(n, i) * fade);
      }
    }
    final decay = _still ? 0.0 : math.exp(-dt * 9);
    for (var i = 0; i < chipWireCount; i++) {
      _wireClip[i] = math.max(clip[i], _wireClip[i] * decay);
      _wireFace[i] = math.max(face[i], _wireFace[i] * decay);
      if (_wireClip[i] < .001) _wireClip[i] = 0;
      if (_wireFace[i] < .001) _wireFace[i] = 0;
    }
    final k = _still ? 1.0 : 1 - math.exp(-dt * 6);
    _clipAlpha += (clipAlpha - _clipAlpha) * k;
    _faceAlpha += (faceAlpha - _faceAlpha) * k;
    if ((_clipAlpha - clipAlpha).abs() < .001) _clipAlpha = clipAlpha;
    if ((_faceAlpha - faceAlpha).abs() < .001) _faceAlpha = faceAlpha;
    _stepLanes(now, dt);
  }

  /// Brings the lanes up one after another and runs data packets along the ones that are up: more of it the faster
  /// indexing goes, and a steady trickle otherwise, because the scan is working whatever its speed.
  void _stepLanes(double now, double dt) {
    final working = _mode == ScanChipMode.scanning && _scanAmt > .5;
    final progress = widget.progress;
    final fp = widget.faceProgress;

    final up = [0, 0];
    _training[0] = _training[1] = -1;
    if (working) {
      if (progress != null && progress < 1) {
        final n = progress.clamp(0.0, 1.0) * chipWireCount;
        up[0] = n.floor();
        _training[0] = up[0].clamp(0, chipWireCount - 1);
        _trainFraction[0] = n - n.floor();
      } else if (progress != null) {
        up[0] = chipWireCount;
      }
      if (widget.faceMode) {
        if (fp != null && fp < 1) {
          final n = fp.clamp(0.0, 1.0) * chipWireCount;
          up[1] = n.floor();
          _training[1] = up[1].clamp(0, chipWireCount - 1);
          _trainFraction[1] = n - n.floor();
        } else if (fp != null) {
          up[1] = chipWireCount;
        }
      } else if (widget.queue != null) {
        up[1] = (_fill * chipWireCount).floor();
      }
    }
    for (var bar = 0; bar < 2; bar++) {
      if (_lanesUp[bar] >= 0 && up[bar] > _lanesUp[bar] && working) {
        for (var k = _lanesUp[bar]; k < up[bar] && k < chipWireCount; k++) {
          _lockAt[bar][k] = now;
        }
      }
      _lanesUp[bar] = working ? up[bar] : -1;
    }

    if (working && progress != null) {
      final written = (progress.clamp(0.0, 1.0) * _memoryCellCount).floor();
      if (written > _cellsWritten) {
        for (var k = math.max(_cellsWritten, written - 40); k < written; k++) {
          _cellWrittenAt[k] = now;
        }
      }
      _cellsWritten = written;
    } else if (!working) {
      _cellsWritten = _mode == ScanChipMode.complete ? _memoryCellCount : 0;
    }
    _cellWrittenAt.removeWhere((_, at) => now - at > .8);

    final rate = [
      working ? (math.max(1.6, widget.rate * 1.1)).clamp(1.6, 9.0).toDouble() : 0.0,
      working ? (widget.faceMode ? 4.0 : (widget.queue != null ? .7 : 0.0)) : 0.0,
    ];
    for (var bar = 0; bar < 2; bar++) {
      _packetDebt[bar] += rate[bar] * dt;
      while (_packetDebt[bar] >= 1) {
        _packetDebt[bar] -= 1;
        if (up[bar] <= 0) continue;
        _packets.add(_Packet(bar, _random.nextInt(math.min(up[bar], chipWireCount)), 22 + _random.nextDouble() * 22));
      }
    }
    for (final packet in _packets) {
      packet.t += packet.speed * dt / 15;
    }
    _packets.removeWhere((packet) => packet.t >= 1.1);
    if (_packets.length > 40) _packets.removeRange(0, _packets.length - 40);
  }

  /// The lid is off while scanning (and for a moment after a tap, whether or not a scan starts) and on otherwise, and
  /// takes about a second and a quarter either way. The queue fill rises smoothly and empties at once when a batch has
  /// started.
  void _glide() {
    final now = _now;
    final dt = (now - _lastStep).clamp(0.0, .2);
    _lastStep = now;
    final k = _still ? 1.0 : 1 - math.exp(-dt * 9);
    final m = _queue.length + (_shot?.pics.length ?? 0);
    for (var i = 0; i < _queue.length; i++) {
      _queue[i].x += (_layoutX(i, m) - _queue[i].x) * k;
    }
    final lidOpen = _mode == ScanChipMode.scanning ||
        (_mode == ScanChipMode.idle && _bootAt >= 0 && now - _bootAt < 3.2);
    final lidTarget = lidOpen ? 1.0 : 0.0;
    _lid = _still
        ? lidTarget
        : (lidTarget > _lid ? math.min(lidTarget, _lid + dt / 1.3) : math.max(lidTarget, _lid - dt / 1.3));
    _tilt = Offset.lerp(_tilt, _tiltTarget, _still ? 1.0 : 1 - math.exp(-dt * 4))!;
    if ((_tilt - _tiltTarget).distance < .001) _tilt = _tiltTarget;
    _updateWires(now, dt);
    final kAmt = _still ? 1.0 : 1 - math.exp(-dt * 7);
    _idleAmt += ((_mode == ScanChipMode.idle ? 1.0 : 0.0) - _idleAmt) * kAmt;
    _scanAmt += ((_mode == ScanChipMode.scanning ? 1.0 : 0.0) - _scanAmt) * kAmt;
    _doneAmt += ((_mode == ScanChipMode.complete ? 1.0 : 0.0) - _doneAmt) * kAmt;
    if (_idleAmt > .999) _idleAmt = 1;
    if (_scanAmt < .001) _scanAmt = 0;
    if (_doneAmt < .001) _doneAmt = 0;
    final target = widget.faceMode || _mode != ScanChipMode.scanning
        ? 0.0
        : (widget.queue?.fill ?? 0.0);
    _fill += (target - _fill) * (_still ? 1.0 : 1 - math.exp(-dt * (target < _fill ? 20 : 3)));
  }

  void _step() {
    if (!mounted) return;
    _glide();
    switch (_mode) {
      case ScanChipMode.scanning:
        if (widget.faceMode) {
          _stepFaces();
        } else {
          _stepIndex();
        }
      case ScanChipMode.complete:
        if (!_still && !_dismissed && _now - _completeAt > 2.2 + 8) {
          _dismissed = true;
          widget.onDismiss?.call();
        }
      case ScanChipMode.idle:
        break;
    }
    if (!_animating()) _clock.stop();
  }

  /// The photo being read is done: it joins the queue in the strip.
  void _finishShot() {
    final shot = _shot;
    if (shot == null) return;
    _idleSince = _now;
    final before = _queue.length;
    for (var i = 0; i < shot.pics.length; i++) {
      _queue.add(_QTile(shot.pics[i], _layoutX(before + i, before + shot.pics.length), shot.frames[i]));
    }
    final cap = widget.queue == null ? _lastMax : _queueMax;
    while (_queue.length > cap) {
      _queue.removeAt(0);
    }
    _shot = null;
  }

  /// A different layout from the last round's for the same number of photos.
  int _pickLayout(int n) {
    final count = _bentoLayouts[n.clamp(1, 6)].length;
    var layout = _random.nextInt(count);
    final last = _lastLayout[n];
    if (count > 1 && layout == last) layout = (layout + 1 + _random.nextInt(count - 1)) % count;
    _lastLayout[n] = layout;
    return layout;
  }

  /// Takes the photos indexed since the last round together: the newest few if there were many, because the ones
  /// skipped over are not shown late.
  void _stepIndex() {
    final now = _now;
    final shot = _shot;
    if (shot != null && !_still && now - shot.start < shot.cycle) return;
    final fresh = [
      for (final photo in widget.photos)
        if (photo.bytes != null && !_shown.contains(photo.id)) photo,
    ];
    if (shot != null && _still && fresh.isEmpty) return;
    _finishShot();
    if (_starting || fresh.isEmpty) return;
    final take = fresh.take(_mosaicMax).toList().reversed.toList();
    _starting = true;
    for (final photo in fresh) {
      _shown.add(photo.id);
    }
    while (_shown.length > 80) {
      _shown.remove(_shown.first);
    }
    Future.wait([for (final photo in take) _ensure(photo.id, photo.bytes!)]).then((pics) {
      _starting = false;
      if (!mounted || widget.faceMode || _mode != ScanChipMode.scanning) return;
      final ok = <_Pic>[];
      final frames = <int?>[];
      for (var i = 0; i < take.length; i++) {
        final pic = pics[i];
        if (pic == null) continue;
        ok.add(pic);
        frames.add(take[i].isVideo ? take[i].frames : null);
      }
      if (ok.isEmpty) return;
      _shot = _Shot(ok, frames, _now, _pickLayout(ok.length));
    });
  }

  /// A photo that cannot be had, or takes too long, is given up on so it never holds up the ones behind it. When faces
  /// come faster than they can be shown, the oldest waiting photos are skipped. A face without a box or landmarks has
  /// nothing to draw it by and is skipped.
  void _ingestFaces() {
    for (final e in widget.events.reversed) {
      if (!_seenFaces.add(e.id)) continue;
      if (e.personId == null || e.box.length != 4 || e.landmarks.length < 10) continue;
      _FaceGroup? group;
      if (_groups.isNotEmpty && _groups.last.uri == e.photoUri) group = _groups.last;
      if (group == null) {
        group = _FaceGroup(e.photoUri);
        _groups.add(group);
        widget
            .loadPhoto(e.photoUri)
            .then<Uint8List?>((bytes) => bytes)
            .timeout(const Duration(seconds: 8), onTimeout: () => null)
            .then((bytes) async {
              final pic = bytes == null ? null : await _decodePic(bytes);
              if (pic == null) {
                group!.failed = true;
              } else {
                group!.pic = pic;
              }
            })
            .catchError((_) {
              group!.failed = true;
            });
      }
      group.events.add(e);
    }
    while (_groups.length > 4) {
      _groups.removeAt(0);
    }
    if (_seenFaces.length > 300) _seenFaces.remove(_seenFaces.first);
  }

  void _stepFaces() {
    final now = _now;
    final shot = _faceShot;
    if (shot != null) {
      for (var i = 0; i < shot.faces.length; i++) {
        final face = shot.faces[i];
        if (!face.committed && now >= shot.start + (.86 + .03 * i) * _faceCycle) {
          _commit(shot, face);
        }
      }
      if (now - shot.start < _faceCycle) return;
      for (final face in shot.faces) {
        if (!face.committed) _commit(shot, face);
      }
      _faceShot = null;
    }
    while (_groups.isNotEmpty && _groups.first.failed) {
      _groups.removeAt(0);
    }
    if (_groups.isEmpty) return;
    final group = _groups.first;
    final pic = group.pic;
    if (pic == null) return;
    _groups.removeAt(0);
    _faceShot = _startShot(group, pic, now);
  }

  /// Faces that match someone already on the tray go first, so a face never takes their place.
  _FaceShot _startShot(_FaceGroup group, _Pic pic, double now) {
    final events = [...group.events]..sort((a, b) => b.score.compareTo(a.score));
    final shown = events.take(_maxFacesShown).toList();
    final reserved = <int>{};
    final faces = <_FaceItem>[];
    for (final e in shown) {
      final slot = _tray.indexWhere((p) => p != null && p.id == e.personId);
      if (slot >= 0) {
        reserved.add(slot);
        faces.add(_FaceItem(e, slot, true));
      }
    }
    for (final e in shown) {
      if (faces.any((f) => f.event == e)) continue;
      var slot = -1;
      for (var j = 0; j < _traySlots; j++) {
        if (_tray[j] == null && !reserved.contains(j)) {
          slot = j;
          break;
        }
      }
      if (slot < 0) {
        var oldest = double.infinity;
        for (var j = 0; j < _traySlots; j++) {
          final p = _tray[j];
          if (p == null || reserved.contains(j)) continue;
          if (p.lastUsed < oldest) {
            oldest = p.lastUsed;
            slot = j;
          }
        }
      }
      if (slot < 0) continue;
      reserved.add(slot);
      faces.add(_FaceItem(e, slot, false));
    }
    faces.sort((a, b) => shown.indexOf(a.event).compareTo(shown.indexOf(b.event)));
    return _FaceShot(pic, _faceView(pic, [for (final f in faces) f.event]), faces, now);
  }

  void _commit(_FaceShot shot, _FaceItem face) {
    face.committed = true;
    final now = _now;
    final e = face.event;
    final existing = _tray[face.slot];
    if (existing != null && existing.id == e.personId) {
      existing
        ..count = e.personPhotos
        ..pulseAt = now
        ..lastUsed = now;
    } else {
      _tray[face.slot] = _Person(
        id: e.personId!,
        pic: shot.pic,
        src: _faceCrop(shot.pic, e),
        count: e.personPhotos,
        bornAt: now,
        isNew: e.isNew,
      )..lastUsed = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, 320.0);
        final interactive = widget.mode != ScanChipMode.scanning;
        Widget chip = TweenAnimationBuilder<double>(
          tween: Tween(end: widget.progress ?? 0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, p, _) {
            return TweenAnimationBuilder<double>(
              tween: Tween(end: widget.faceMode ? 1 : 0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              builder: (context, faceAmount, _) {
                return TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.faceProgress ?? 0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, fp, _) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        size: Size(side, side),
                        painter: _SquarePainter(
                          scene: this,
                          repaint: _clock,
                          progress: p,
                          indeterminate: widget.progress == null,
                          faceAmount: faceAmount,
                          faceProgress: fp,
                          faceIndeterminate: widget.faceMode && widget.faceProgress == null,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
        if (interactive) {
          chip = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = widget.mode == ScanChipMode.idle),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: _tap,
            child: chip,
          );
        }
        return Center(
          child: SizedBox(
            width: side,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: interactive,
                  label: widget.semanticsLabel,
                  child: chip,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _below(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// What is written under the chip.
  Widget _below() {
    switch (widget.mode) {
      case ScanChipMode.idle:
        return const SizedBox(key: ValueKey('idle'), width: double.infinity);
      case ScanChipMode.complete:
        final summary = widget.summary;
        if (summary == null) return const SizedBox(key: ValueKey('done'), width: double.infinity);
        return _CompleteTexts(key: const ValueKey('done'), summary: summary);
      case ScanChipMode.scanning:
        final stats = widget.stats;
        if (stats == null) return const SizedBox(key: ValueKey('scan'), width: double.infinity);
        return _ScanStory(
          key: const ValueKey('scan'),
          stats: stats,
          queue: widget.queue,
          facesNow: widget.faceMode,
        );
    }
  }
}

/// What the chip is doing: waiting to be started, scanning, or showing that a scan is done.
enum ScanChipMode { idle, scanning, complete }

/// A just-indexed photo (or video, shown by one of its frames) to read in the square.
class OrbitPhoto {
  const OrbitPhoto({required this.id, required this.bytes, this.isVideo = false, this.frames = 0});

  final String id;
  final Uint8List? bytes;
  final bool isVideo;

  /// For a video, how many frames were read from it (0 when not told).
  final int frames;
}

/// Photos kept in the strip: all of a batch's while faces follow the scan, else the last few.
const int _queueMax = 12;

const int _lastMax = 5;

/// Seconds the photos shown together take to be read (the more there are, the quicker, to look like the pace of the
/// scan), and to have a photo's faces lifted out and placed.
const int _mosaicMax = 6;

const int _maxFacesShown = 5;

/// Where to put a photo so it fills the photo area as far as it can while keeping the faces
/// [events] in view: scaled to cover the area, centred on the faces, and pulled back only when
/// the faces would not fit otherwise. The result may be larger than the area (it is clipped).
Rect _faceView(_Pic pic, List<FaceEvent> events) {
  const box = _photoBox;
  final cover = math.max(box.width / pic.w, box.height / pic.h);
  final contain = math.min(box.width / pic.w, box.height / pic.h);
  var left = 1.0, top = 1.0, right = 0.0, bottom = 0.0;
  for (final e in events) {
    if (e.box.length != 4) continue;
    left = math.min(left, e.box[0]);
    top = math.min(top, e.box[1]);
    right = math.max(right, e.box[2]);
    bottom = math.max(bottom, e.box[3]);
  }
  if (right <= left || bottom <= top) {
    left = 0;
    top = 0;
    right = 1;
    bottom = 1;
  }
  final faceW = (right - left) * pic.w, faceH = (bottom - top) * pic.h;
  final keep = math.min(box.width / (faceW * 1.4), box.height / (faceH * 1.5));
  final scale = math.max(contain, math.min(cover, keep));
  final w = pic.w * scale, h = pic.h * scale;
  double place(double size, double boxStart, double boxSize, double faceMid) {
    if (size <= boxSize) return boxStart + (boxSize - size) / 2;
    return (boxStart + boxSize / 2 - faceMid * size).clamp(boxStart + boxSize - size, boxStart);
  }

  return Rect.fromLTWH(
    place(w, box.left, box.width, (left + right) / 2),
    place(h, box.top, box.height, (top + bottom) / 2),
    w,
    h,
  );
}

Future<_Pic?> _decodePic(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 300);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final pic = _Pic(frame.image);
    pic.tones = await _patchTones(frame.image);
    return pic;
  } catch (_) {
    return null;
  }
}

Future<List<Color>?> _patchTones(ui.Image image) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final w = image.width, h = image.height;
    final side = math.min(w, h);
    final ox = (w - side) ~/ 2, oy = (h - side) ~/ 2;
    final sums = List<int>.filled(49 * 4, 0);
    for (var y = 0; y < side; y += 2) {
      final row = math.min<int>(6, y * 7 ~/ side);
      for (var x = 0; x < side; x += 2) {
        final k = (row * 7 + math.min<int>(6, x * 7 ~/ side)) * 4;
        final i = ((oy + y) * w + ox + x) * 4;
        sums[k] += data.getUint8(i);
        sums[k + 1] += data.getUint8(i + 1);
        sums[k + 2] += data.getUint8(i + 2);
        sums[k + 3]++;
      }
    }
    return [
      for (var k = 0; k < 49; k++)
        sums[k * 4 + 3] == 0
            ? ScanPalette.gray500
            : Color.fromARGB(255, sums[k * 4] ~/ sums[k * 4 + 3], sums[k * 4 + 1] ~/ sums[k * 4 + 3], sums[k * 4 + 2] ~/ sums[k * 4 + 3]),
    ];
  } catch (_) {
    return null;
  }
}

/// A packet of data running along a bond wire (t from the die, or bank, to the board).
class _Packet {
  _Packet(this.bar, this.wire, this.speed);

  final int bar, wire;
  final double speed;
  double t = 0;
}

/// A thumbnail in the queue strip.
class _QTile {
  _QTile(this.pic, this.x, [this.frames]);

  final _Pic pic;
  double x;

  /// For a video, how many frames were read from it (0 when not told); null for a photo.
  final int? frames;
}

/// The photo the square is reading at the moment.
class _Shot {
  _Shot(this.pics, this.frames, this.start, this.layout) : cycle = _cycleFor(pics.length);

  /// The photos read together, oldest first.
  final List<_Pic> pics;

  /// For each of [pics], null for a photo, or for a video how many frames were read from it.
  final List<int?> frames;
  final double start;
  final double cycle;

  /// Which of the bento layouts for this many photos is used.
  final int layout;
}

double _cycleFor(int photos) => const [3.6, 3.6, 3.2, 2.9, 2.6, 2.3, 2.0][photos.clamp(1, 6)];

/// A person on the tray along the bottom.
class _Person {
  _Person({
    required this.id,
    required this.pic,
    required this.src,
    required this.count,
    required this.bornAt,
    required this.isNew,
  });

  final int id;
  final _Pic pic;
  final Rect src;
  int count;
  final double bornAt;
  final bool isNew;
  double pulseAt = -100;
  double lastUsed = 0;
}

/// The faces of one photo, waiting for their turn (and for the photo to be read in).
class _FaceGroup {
  _FaceGroup(this.uri);

  final String uri;
  final List<FaceEvent> events = [];
  _Pic? pic;
  bool failed = false;
}

class _FaceShot {
  _FaceShot(this.pic, this.dst, this.faces, this.start);

  final _Pic pic;
  final Rect dst;
  final List<_FaceItem> faces;
  final double start;
}

/// One face being lifted out.
class _FaceItem {
  _FaceItem(this.event, this.slot, this.matched);

  final FaceEvent event;
  final int slot;
  final bool matched;
  bool committed = false;
}
