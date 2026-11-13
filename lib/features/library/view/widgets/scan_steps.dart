import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/library/view/widgets/steps_morph.dart';
import 'package:lost_and_found/features/people/services/people_service.dart';

/// 12345 as "12,345".
String groupedCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Time left, rounded the way people say it. A figure that changes every second is noise.
String timeLeftText(int ms) {
  final minutes = ms / 60000;
  if (minutes < .75) return 'under a minute left';
  if (minutes < 1.5) return 'about a minute left';
  if (minutes < 20) return 'about ${minutes.round()} min left';
  if (minutes < 90) return 'about ${(minutes / 5).round() * 5} min left';
  final hours = minutes / 60;
  if (hours < 10) {
    final halves = (hours * 2).round() / 2;
    return 'about ${halves == halves.roundToDouble() ? halves.round() : halves} h left';
  }
  return 'about ${hours.round()} h left';
}

/// A speed in the words the card uses: "14 per second", "2.5 per second", or per minute when it is slow.
String speedText(double perSecond) {
  if (perSecond >= 10) return '${perSecond.round()} per second';
  if (perSecond >= 1) return '${perSecond.toStringAsFixed(1)} per second';
  return '${(perSecond * 60).round()} per minute';
}

enum _StepState { wait, busy, done }

/// What a circle is doing in a handoff: letting go of the work, or taking it up.
enum _Role { none, from, to }

const _barHeight = 8.0;

/// The ending of a scan, as fractions of [duration]. A bright dot runs down the rail and turns the first two circles
/// into checks as it passes. At the last circle the check pops, a ring spreads from it, the card's edge flashes and a teal
/// tint floods the card from that circle and drains away. Then the first two circles go back to how they were.
abstract final class _Finish {
  static const duration = Duration(milliseconds: 2600);
  static const dotEnd = 0.385;
  static const firstCheck = 0.03;
  static const secondCheck = 0.16;
  static const lastCheck = 0.29;
  static const release = 0.79;
  static const releaseEnd = 0.9;
  static const flashEnd = 0.675;
  static const floodLength = 0.577;
}

/// The handing of the work from one circle to the next, as fractions of [_handDuration]. The first circle lets go with a
/// ring, bright dashes flow along the rail towards the next one for most of the time, then a ring closes onto the next
/// circle, which takes up the work.
const _handDuration = Duration(milliseconds: 1400);
const _handFlowEnd = 0.94;
const _handReceiveFrom = 0.55;

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// A scan as three plain steps down a rail: reading the photos and videos, finding people, and whether search already
/// works. A step's circle is empty while it waits, turns round while it works with the photos or faces just read
/// showing inside it, and ends as a ring around a teal check.
///
/// Indexing and finding faces take turns. While one works, the other's circle is held: its last picture fades and a
/// pause sign pulses over it. When the turn passes from one to the other, the work is handed over along the rail. A soft
/// glow breathes behind the circle that is working, and slides to the other with the turn.
///
/// With [paused] set, a scan that was stopped part of the way folds into a row (see [StepsMorph]): "Paused" and how far it
/// got on top, and the three circles side by side as rings that show how far each step reached. Nothing moves then. A
/// scan that ran to the end keeps the rail.
class ScanStepsCard extends StatefulWidget {
  const ScanStepsCard({
    super.key,
    required this.processed,
    required this.total,
    required this.searchable,
    required this.people,
    required this.faceWork,
    required this.findingFaces,
    required this.tuning,
    required this.faceFraction,
    required this.batchPhotos,
    required this.semanticsLabel,
    this.facesProgress = 0,
    this.stopping = false,
    this.paused = false,
    this.idle = false,
    this.celebrate = false,
    this.found,
    this.etaMs,
    this.photoRate,
    this.faceRate,
    this.photoIds = const [],
    this.loadPhoto,
    this.faceIds = const [],
    this.loadFace,
  });

  /// Photos and videos indexed so far, and how many there are. The total is 0 until the walk through the phone ends.
  final int processed, total;

  /// How many items the walk has found so far, while the total is still 0.
  final int? found;
  final int? etaMs;

  /// How fast photos are indexed and faces are found, in items and photos per second, when known.
  final double? photoRate, faceRate;

  /// How many items can be searched now.
  final int searchable;

  /// People found so far.
  final int people;

  /// Whether face finding is running at all, and whether it is working through a batch right now.
  final bool faceWork, findingFaces;

  /// Whether the one-off speed test for this phone is what face finding is doing.
  final bool tuning;

  /// Whether the scan was stopped, so nothing moves.
  final bool paused;

  /// Whether the scan has been told to stop and is still finishing the photos in progress. The stopped card then says so.
  final bool stopping;

  /// Whether no scan has run yet, so the steps wait with nothing to show.
  final bool idle;

  /// Set when the scan has just run to the end: the ending then plays once.
  final bool celebrate;

  /// How far the faces have got through the whole library, from 0 to 1. A stopped scan shows it on the ring of the
  /// People step.
  final double facesProgress;

  /// How far through the batch of faces it is, and how many photos the batch has.
  final double faceFraction;
  final int batchPhotos;

  /// What was indexed and found most recently, newest first. Each is shown once as it comes, and [loadPhoto] and
  /// [loadFace] give its picture. Faces come from the people service unless a test gives another.
  final List<String> photoIds;
  final Future<Uint8List> Function(String id)? loadPhoto;
  final List<int> faceIds;
  final Future<Uint8List> Function(int faceId)? loadFace;

  final String semanticsLabel;

  @override
  State<ScanStepsCard> createState() => _ScanStepsCardState();

  static Future<Uint8List> _loadFaceFromPhone(int id) => PeopleService().faceCrop(id, size: 96);
}

class _ScanStepsCardState extends State<ScanStepsCard> with TickerProviderStateMixin {
  late final AnimationController _hand = AnimationController(vsync: this, duration: _handDuration);
  late final AnimationController _finish = AnimationController(vsync: this, duration: _Finish.duration);
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  /// 0 while the steps go down a rail, 1 once they have moved into the row of a stopped scan.
  late final AnimationController _morph = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// Whether the steps are on the rail and the circles have been measured there, which is when the glow can sit behind one.
  bool _onRail = true;

  final _cardKey = GlobalKey();
  final _nodeKeys = [GlobalKey(), GlobalKey(), GlobalKey()];
  List<Offset?> _centers = const [null, null, null];
  bool _measuring = false;

  /// The circle that shows as working (0 photos, 1 people), or null when none does. During a handoff it is still the
  /// circle the work is leaving, and [_to] is the one it is going to.
  int? _shown;
  int? _to;

  bool get _handing => _to != null;

  /// The circle that should be working now, from what the scan reports.
  int? get _target => widget.paused || widget.idle ? null : (widget.findingFaces || widget.tuning ? 1 : 0);

  /// The circle the glow sits behind.
  int? get _glowAt => _handing ? _to : _shown;

  /// Whether the scan was stopped part of the way. One that ran to the end, or is ending now, keeps the rail.
  bool get _stopped => _stoppedBy(widget);

  static bool _stoppedBy(ScanStepsCard w) => w.paused && !w.idle && !w.celebrate && !(w.total > 0 && w.processed >= w.total);

  @override
  void initState() {
    super.initState();
    _shown = _target;
    _morph.value = _stopped ? 1 : 0;
    _onRail = !_stopped;
    _morph.addStatusListener(_followMorph);
  }

  void _followMorph(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_morph.isDismissed) return;
        _measure();
        setState(() => _onRail = true);
      });
    } else if (_onRail) {
      setState(() => _onRail = false);
    }
  }

  void _followStopped(bool was) {
    if (_stopped == was) return;
    if (calm(context)) {
      _morph.value = _stopped ? 1 : 0;
    } else if (_stopped) {
      _morph.forward();
    } else {
      _morph.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followGlow();
  }

  @override
  void didUpdateWidget(covariant ScanStepsCard old) {
    super.didUpdateWidget(old);
    _followStopped(_stoppedBy(old));
    _followTarget();
    if (!old.celebrate && widget.celebrate) _startFinish();
    if (old.celebrate && !widget.celebrate) _finish.value = 0;
    _followGlow();
  }

  void _followTarget() {
    final target = _target;
    if (_handing) {
      if (target == _to) return;
      _hand.stop();
      _to = null;
      _shown = target;
      return;
    }
    if (target == _shown) return;
    final from = _shown;
    if (from != null && target != null && !calm(context) && !_finish.isAnimating) {
      _startHand(target);
    } else {
      _shown = target;
    }
  }

  void _startHand(int to) {
    _to = to;
    _hand.forward(from: 0).whenComplete(() {
      if (!mounted || _to != to) return;
      setState(() {
        _shown = to;
        _to = null;
      });
    });
  }

  void _startFinish() {
    if (calm(context)) return;
    _hand.stop();
    _to = null;
    _finish.forward(from: 0);
  }

  void _followGlow() {
    if (calm(context)) {
      _breath.stop();
      _breath.value = 0.5;
    } else if (_glowAt != null) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
    }
  }

  void _scheduleMeasure() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (mounted) _measure();
    });
  }

  /// Where the three circles are in the card, for what is drawn behind and over the steps.
  void _measure() {
    final card = _cardKey.currentContext?.findRenderObject();
    if (card is! RenderBox || !card.hasSize || !card.attached) return;
    final next = [for (final key in _nodeKeys) _centerOf(key, card)];
    if (!listEquals(next, _centers)) setState(() => _centers = next);
  }

  Offset? _centerOf(GlobalKey key, RenderBox card) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return card.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  @override
  void dispose() {
    _hand.dispose();
    _finish.dispose();
    _breath.dispose();
    _morph.dispose();
    super.dispose();
  }

  _Role _roleOf(int circle) => !_handing ? _Role.none : (circle == _to ? _Role.to : (circle == _shown ? _Role.from : _Role.none));

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    final w = widget;
    final preparing = w.total == 0 && !w.idle;
    final complete = w.total > 0 && w.processed >= w.total;
    final photosState = w.idle ? _StepState.wait : _StepState.busy;
    final peopleState = w.people > 0 || w.faceWork || w.tuning ? _StepState.busy : _StepState.wait;
    final searchState = w.searchable > 0 ? _StepState.done : _StepState.wait;
    final faceBatch = w.findingFaces && !w.tuning;
    final working = _handing ? null : _shown;
    final photosHeld = w.paused || working != 0;
    final peopleHeld = w.paused || working != 1;

    final photoDetail = preparing
        ? (w.found != null ? '${groupedCount(w.found!)} items found so far' : 'Getting ready')
        : [
            '${groupedCount(w.processed)} of ${groupedCount(w.total)}',
            if (w.paused) ...[if (!complete) 'paused'] else if (w.etaMs != null) timeLeftText(w.etaMs!),
          ].join('  ·  ');
    final peopleDetail = w.tuning
        ? 'Preparing face search for this phone'
        : w.people > 0
        ? '${groupedCount(w.people)} found so far'
        : peopleState == _StepState.wait
        ? 'Starts once the first photos are read'
        : 'Looking for faces';

    final text = Theme.of(context).textTheme;
    final stopped = _stopped;
    final indexed = w.total > 0 ? '${groupedCount(w.processed)} of ${groupedCount(w.total)} indexed.' : 'Nothing is indexed yet.';
    final states = [photosState, peopleState, searchState];
    final reached = w.total == 0 ? 0.0 : (w.processed / w.total).clamp(0.0, 1.0);
    final arcs = [reached, w.facesProgress, reached];
    final railTitle = [
      for (final state in states) text.titleSmall?.copyWith(color: state == _StepState.wait ? AppColors.ink48 : AppColors.ink),
    ];
    final railDetail = text.bodySmall?.copyWith(color: AppColors.ink48, height: 1.35);
    final rowTitle = text.titleSmall?.copyWith(color: AppColors.ink, fontSize: 13);
    final rowDetail = text.bodySmall?.copyWith(color: AppColors.ink48, height: 1.35);

    final titles = ['Reading photos and videos', 'Finding people', searchState == _StepState.done ? 'Search is ready' : 'Search'];
    final details = [
      photoDetail,
      peopleDetail,
      searchState == _StepState.done ? '${groupedCount(w.searchable)} searchable now' : 'Ready after the first photos',
    ];
    final rowTitles = ['Media', 'People', 'Search'];
    final rowDetails = [
      '${groupedCount(w.processed)} read',
      w.people > 0 ? '${groupedCount(w.people)} found' : 'None yet',
      searchState == _StepState.done ? 'Ready' : 'Not yet',
    ];
    final extras = <Widget?>[
      _Extra(
        bar: _Bar(value: preparing ? null : (w.total == 0 ? 0 : w.processed / w.total), color: AppColors.primary, height: _barHeight),
        text: !w.paused && w.photoRate != null && w.photoRate! > 0.02 ? speedText(w.photoRate!) : null,
      ),
      w.paused
          ? null
          : w.tuning
          ? const _Extra(
              bar: _Bar(value: null, color: AppColors.faceAccent, height: _barHeight),
              text: 'One time only, about a minute',
            )
          : faceBatch && w.batchPhotos > 0
          ? _Extra(
              bar: _Bar(value: w.faceFraction.clamp(0.0, 1.0), color: AppColors.faceAccent, height: _barHeight),
              text: [
                'Looking at the last ${groupedCount(w.batchPhotos)} photos',
                if (w.faceRate != null && w.faceRate! > 0.02) speedText(w.faceRate!),
              ].join('  ·  '),
            )
          : null,
      null,
    ];
    final icons = [Icons.photo_library_outlined, Icons.person_outline_rounded, Icons.search_rounded];
    final inside = <Widget?>[
      photosState == _StepState.wait
          ? null
          : _FlipNew<String>(
              ids: w.photoIds,
              load: w.loadPhoto ?? (_) => Future<Uint8List>.error('no pictures'),
              held: photosHeld,
              stopped: stopped,
              fallback: Icons.photo_library_outlined,
            ),
      peopleState == _StepState.wait
          ? null
          : _FlipNew<int>(
              ids: w.faceIds,
              load: w.loadFace ?? ScanStepsCard._loadFaceFromPhone,
              held: peopleHeld,
              stopped: stopped,
              fallback: Icons.person_outline_rounded,
            ),
      null,
    ];
    final spinning = [!photosHeld, !peopleHeld, false];
    final lineOn = [peopleState != _StepState.wait, searchState == _StepState.done];

    final steps = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.lg),
      child: StepsMorph(
        progress: _morph,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(w.stopping ? 'Stopping…' : 'Paused', style: text.headlineMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700, height: 1.1)),
            const SizedBox(height: AppSpacing.sm - 2),
            Text(indexed, style: text.bodyMedium?.copyWith(color: AppColors.ink80)),
          ],
        ),
        nodes: [
          for (var i = 0; i < 3; i++)
            _Node(
              key: _nodeKeys[i],
              finishIndex: i,
              state: states[i],
              spinning: spinning[i],
              still: stopped,
              arc: arcs[i],
              arcColor: i == 1 ? AppColors.faceAccent : AppColors.primary,
              arcShow: _morph,
              icon: icons[i],
              inside: inside[i],
              finish: _finish,
              hand: _hand,
              role: _roleOf(i),
            ),
        ],
        titles: [for (var i = 0; i < 3; i++) Text(titles[i], style: railTitle[i])],
        details: [for (var i = 0; i < 3; i++) Text(details[i], style: railDetail)],
        extras: [
          for (var i = 0; i < 3; i++)
            SmoothSize(
              child: extras[i] == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: extras[i]),
            ),
        ],
        rowTitles: [
          for (final t in rowTitles)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(t, style: rowTitle, maxLines: 1)),
            ),
        ],
        rowDetails: [for (final d in rowDetails) Text(d, style: rowDetail, textAlign: TextAlign.center)],
        edges: [
          for (var i = 0; i < 2; i++)
            _Rail(on: lineOn[i], segment: i, finish: _finish, flow: i == 0 && _handing ? _hand : null, flowUp: _shown == 1),
        ],
      ),
    );

    final glowAt = _glowAt == null ? null : _centers[_glowAt!];
    final flood = _centers[2];
    final body = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedOpacity(
                  opacity: _glowAt == null || !_onRail ? 0 : 1,
                  duration: const Duration(milliseconds: 600),
                  child: glowAt == null || !_onRail
                      ? const SizedBox.shrink()
                      : TweenAnimationBuilder<Offset>(
                          tween: Tween(end: glowAt),
                          duration: calm(context) ? Duration.zero : const Duration(milliseconds: 800),
                          curve: const Cubic(0.3, 0, 0.2, 1),
                          builder: (context, at, _) => AnimatedBuilder(
                            animation: _breath,
                            builder: (context, _) => CustomPaint(painter: _GlowPainter(at, _breath.value)),
                          ),
                        ),
                ),
              ),
            ),
          ),
          steps,
          if (flood != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _finish,
                  builder: (context, _) => _finish.isAnimating ? CustomPaint(painter: _FloodPainter(_finish.value, flood)) : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: w.semanticsLabel,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
          animation: _finish,
          child: body,
          builder: (context, child) {
            final flash = _finish.isAnimating ? math.sin(math.pi * _seg(_finish.value, _Finish.lastCheck, _Finish.flashEnd)) : 0.0;
            return DecoratedBox(
              key: _cardKey,
              decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
              position: DecorationPosition.background,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: flash > 0.01 ? Border.all(color: AppColors.primary.withValues(alpha: 0.38 * flash), width: 3) : null,
                ),
                position: DecorationPosition.foreground,
                child: child,
              ),
            );
          },
          ),
        ),
      ),
    );
  }
}

/// A thin line of text under a step, with its own bar.
class _Extra extends StatelessWidget {
  const _Extra({required this.bar, this.text});

  final Widget bar;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        if (text != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(text!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink48)),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.height});

  final double? value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        color: color,
        backgroundColor: AppColors.hairline,
      ),
    );
  }
}

/// The edge between two steps: grey, filled with teal once the next step has begun. While the work is handed along it,
/// bright dashes flow towards the next step, and at the end of a scan a bright dot runs down it.
class _Rail extends StatelessWidget {
  const _Rail({required this.on, required this.segment, required this.finish, this.flow, this.flowUp = false});

  final bool on;

  /// Which edge this is, from the top.
  final int segment;
  final Animation<double> finish;
  final Animation<double>? flow;
  final bool flowUp;

  @override
  Widget build(BuildContext context) {
    final fill = TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1 : 0),
      duration: calm(context) ? Duration.zero : const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: v,
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
      child: AnimatedBuilder(
        animation: Listenable.merge([finish, if (flow != null) flow!]),
        builder: (context, _) {
          final flowing = flow != null && flow!.isAnimating && flow!.value < _handFlowEnd;
          final travel = finish.isAnimating ? Curves.easeInOut.transform(_seg(finish.value, 0, _Finish.dotEnd)) : 0.0;
          final along = travel * 2 - segment;
          return Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Opacity(opacity: flowing ? 0 : 1, child: fill),
              if (flowing) CustomPaint(painter: _DashPainter(flow!.value, flowUp)),
              if (travel > 0 && travel < 1 && along > 0 && along < 1)
                CustomPaint(painter: _DotPainter(along, _seg(travel, 0, 0.1) * (1 - _seg(travel, 0.9, 1)))),
            ],
          );
        },
      ),
    );
  }
}

/// The circle of a step: a ring with the step's picture or sign inside. [inside] is the picture that fills it while the
/// step works, such as the photos showing one after another.
///
/// At the end of a scan, [finish] turns the first two circles into checks for a moment as a dot passes, and makes the
/// last one pop its check with a ring spreading from it. In a handoff, [hand] has the circle that lets go send out a ring
/// and the one that takes the work up have a ring close onto it, and then it gives a small bump as it starts to turn.
/// With motion off none of this plays.
class _Node extends StatefulWidget {
  const _Node({
    super.key,
    required this.finishIndex,
    required this.state,
    required this.spinning,
    required this.icon,
    this.inside,
    this.finish,
    this.hand,
    this.role = _Role.none,
    this.still = false,
    this.arc,
    this.arcColor = AppColors.primary,
    this.arcShow,
  });

  static const size = StepsMorph.nodeSize;

  /// The room inside the ring for the picture or the check.
  static const inner = 34.0;

  final int finishIndex;
  final _StepState state;
  final bool spinning;
  final IconData icon;
  final Widget? inside;
  final Animation<double>? finish;
  final Animation<double>? hand;
  final _Role role;

  /// Set while the scan is stopped, so the ring does not breathe.
  final bool still;

  /// How much of the ring to fill in [arcColor], from 0 to 1, once [arcShow] has run towards 1. The ring is then a track
  /// that the arc fills round from the top.
  final double? arc;
  final Color arcColor;
  final Animation<double>? arcShow;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> with TickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  /// A slow, faint breath of the ring while the step is held, in step with the pause sign inside.
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  /// The small bump as a circle takes up the work.
  late final AnimationController _bump = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(covariant _Node old) {
    super.didUpdateWidget(old);
    _follow();
    if (old.state == _StepState.busy && widget.state == _StepState.busy && !old.spinning && widget.spinning && !calm(context)) {
      _bump.forward(from: 0);
    }
  }

  void _follow() {
    final run = widget.state == _StepState.busy && widget.spinning;
    if (run) {
      loopUnlessCalm(context, _turn);
    } else {
      _turn.stop();
    }
    if (widget.state == _StepState.busy && !widget.spinning && !widget.still) {
      loopUnlessCalm(context, _hold, reverse: true);
    } else {
      _hold.stop();
      _hold.value = 0;
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _hold.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finish = widget.finish;
    final hand = widget.hand;
    return AnimatedBuilder(
      animation: Listenable.merge([_hold, _bump, if (finish != null) finish, if (hand != null) hand, if (widget.arcShow != null) widget.arcShow!]),
      builder: (context, _) => _node(),
    );
  }

  Widget _node() {
    final state = widget.state;
    final finish = widget.finish;
    final index = widget.finishIndex;
    final last = index == 2;
    final fv = finish?.value ?? 0.0;
    final finishing = finish?.isAnimating ?? false;
    final played = fv > 0;
    final beforeCheck = last && finishing && fv < _Finish.lastCheck;
    final done = state == _StepState.done && !beforeCheck;
    final pop = last && played ? _seg(fv, _Finish.lastCheck, _Finish.lastCheck + 0.17) : 1.0;
    final breath = Curves.easeInOut.transform(_hold.value);
    final arcAmount = widget.arc == null ? 0.0 : Curves.easeOut.transform(_seg(widget.arcShow?.value ?? 0, 0.5, 1));
    final ringColor = Color.lerp(
      done
          ? Color.lerp(AppColors.hairline, AppColors.primary, last && played ? pop : 1)!
          : Color.lerp(AppColors.hairline, AppColors.primary.withValues(alpha: 0.5), breath * 0.7)!,
      AppColors.hairline,
      arcAmount,
    )!;

    final checkAt = index == 0 ? _Finish.firstCheck : _Finish.secondCheck;
    final checkProgress = finishing && !last ? _seg(fv, checkAt, checkAt + 0.12) : 0.0;
    final checkFade = 1 - _seg(fv, _Finish.release, _Finish.releaseEnd);

    final rippleStart = last ? _Finish.lastCheck : checkAt;
    final rippleLength = last ? 0.346 : 0.27;
    final handing = widget.hand?.isAnimating ?? false;
    final handT = widget.hand?.value ?? 0.0;

    return Transform.scale(
      scale: 1 + 0.14 * math.sin(math.pi * _bump.value),
      child: SizedBox(
        width: _Node.size,
        height: _Node.size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.canvas,
                border: Border.all(color: ringColor, width: 2.5),
                boxShadow: !done && breath > 0 ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12 * breath), blurRadius: 6)] : null,
              ),
              child: const SizedBox.expand(),
            ),
            if (arcAmount > 0 && widget.arc! > 0)
              CustomPaint(
                size: Size.square(_Node.size),
                painter: _ArcPainter(widget.arcColor, sweep: math.pi * 2 * widget.arc!.clamp(0.0, 1.0) * arcAmount, from: -math.pi / 2),
              ),
            if (state == _StepState.busy && widget.spinning)
              RepaintBoundary(
                child: RotationTransition(
                  turns: _turn,
                  child: const CustomPaint(size: Size.square(_Node.size), painter: _ArcPainter(AppColors.primary)),
                ),
              ),
            if (done)
              last && played
                  ? _CheckDisc(
                      size: _Node.inner,
                      scale: Curves.easeOutBack.transform(pop),
                      draw: Curves.easeOut.transform(_seg(fv, _Finish.lastCheck + 0.05, _Finish.lastCheck + 0.2)),
                    )
                  : const _CheckDisc(size: _Node.inner)
            else if (state == _StepState.busy && widget.inside != null)
              ClipOval(child: SizedBox.square(dimension: _Node.inner, child: widget.inside))
            else
              Icon(widget.icon, size: 20, color: state == _StepState.busy ? AppColors.primary : AppColors.ink48),
            if (checkProgress > 0 && checkFade > 0)
              Opacity(
                opacity: checkFade,
                child: _CheckDisc(
                  size: _Node.inner,
                  scale: Curves.easeOutBack.transform(checkProgress),
                  draw: Curves.easeOut.transform(_seg(fv, checkAt + 0.04, checkAt + 0.16)),
                ),
              ),
            CustomPaint(
              size: Size.square(_Node.size),
              painter: _NodeFxPainter(
                send: handing && widget.role == _Role.from ? _seg(handT, 0, 0.464) : 0,
                receive: handing && widget.role == _Role.to ? _seg(handT, _handReceiveFrom, 1) : 0,
                ripple: finishing ? _seg(fv, rippleStart, rippleStart + rippleLength) : 0,
                big: last,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rings around a circle: the one it sends out as it lets go of the work, the one that closes onto it as it takes the
/// work up, and the ripple of a check at the end of a scan.
class _NodeFxPainter extends CustomPainter {
  const _NodeFxPainter({required this.send, required this.receive, required this.ripple, required this.big});

  final double send, receive, ripple;
  final bool big;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    void ring(double radius, double alpha, double width) {
      if (alpha <= 0.005) return;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = AppColors.primary.withValues(alpha: alpha),
      );
    }

    if (send > 0 && send < 1) {
      final e = Curves.easeOut.transform(send);
      ring(r * (1 + 1.4 * e), 0.65 * (1 - e), 2);
    }
    if (receive > 0 && receive < 1) {
      final e = Curves.easeIn.transform(receive);
      final alpha = receive < 0.4 ? 0.7 * receive / 0.4 : 0.7 * (1 - (receive - 0.4) / 0.6);
      ring(r * (2.1 - 1.1 * e), alpha, 2);
      ring(r + 2, 0.18, 4);
    }
    if (ripple > 0 && ripple < 1) {
      final e = Curves.easeOut.transform(ripple);
      ring(r * (1 + (big ? 1.6 : 0.9) * e), 0.65 * (1 - e), 2);
    }
  }

  @override
  bool shouldRepaint(_NodeFxPainter old) => old.send != send || old.receive != receive || old.ripple != ripple || old.big != big;
}

/// The bright dashes that flow along an edge while the work is handed over, towards the next circle. They move 16 dp
/// every half second.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.t, this.up);

  final double t;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final shift = t * 40.7 * (up ? -1 : 1);
    final paint = Paint()..color = AppColors.primary.withValues(alpha: 0.9);
    for (var y = (shift % 16) - 16; y < size.height; y += 16) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y + 5, size.width, 6), const Radius.circular(1)), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.t != t || old.up != up;
}

/// The bright dot that runs down the edges at the end of a scan. [along] is how far down this edge it is.
class _DotPainter extends CustomPainter {
  const _DotPainter(this.along, this.alpha);

  final double along, alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final at = Offset(size.width / 2, along * size.height);
    const radius = 9.0;
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.mediaAccent.withValues(alpha: 0.95 * alpha), AppColors.mediaAccent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.along != along || old.alpha != alpha;
}

/// The soft light behind the card while a scan works: the whole card breathes a little towards teal, and a glow sits
/// behind the circle that is working. [breath] runs from 0 to 1 and round again.
class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.at, this.breath);

  final Offset at;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final b = 0.5 - 0.5 * math.cos(2 * math.pi * breath);
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = AppColors.primaryGlow.withValues(alpha: 0.07 * b));
    final glow = 0.45 + 0.55 * b;
    final far = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]
        .map((corner) => (corner - at).distance)
        .reduce(math.max);
    final radius = far * 0.62;
    canvas.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.mediaAccent.withValues(alpha: 0.34 * glow), AppColors.mediaAccent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.at != at || old.breath != breath;
}

/// The teal tint that floods the card from the last circle as its check pops, and drains away.
class _FloodPainter extends CustomPainter {
  const _FloodPainter(this.t, this.at);

  final double t;
  final Offset at;

  @override
  void paint(Canvas canvas, Size size) {
    final local = _seg(t, _Finish.lastCheck, _Finish.lastCheck + _Finish.floodLength);
    if (local <= 0 || local >= 1) return;
    final reach = math.sqrt(size.width * size.width + size.height * size.height) * 1.1;
    final grow = Curves.easeOut.transform(_seg(local, 0, 0.55));
    final radius = 10 + (reach - 10) * grow;
    final opacity = local < 0.55 ? 1 - 0.1 * (local / 0.55) : 0.9 * (1 - (local - 0.55) / 0.45);
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.primaryGlow.withValues(alpha: 0.30 * opacity), AppColors.primaryGlow.withValues(alpha: 0)],
          stops: const [0, 0.7],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_FloodPainter old) => old.t != t || old.at != at;
}

/// A teal disc with a check. By itself it pops in and the check draws itself, and [scale] and [draw] put it in charge of
/// something else that does that.
class _CheckDisc extends StatelessWidget {
  const _CheckDisc({required this.size, this.scale, this.draw});

  final double size;
  final double? scale, draw;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: calm(context) ? Duration.zero : const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, t, _) => Transform.scale(
        scale: scale ?? 0.6 + 0.4 * t,
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            child: CustomPaint(painter: _CheckPainter((draw ?? t).clamp(0.0, 1.0))),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color, {this.sweep = math.pi * 0.7, this.from = 0});

  final Color color;

  /// Where the arc starts and how far it runs, in radians.
  final double sweep, from;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.25);
    canvas.drawArc(
      rect,
      from,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color || old.sweep != sweep || old.from != from;
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(w * .28, w * .52)
      ..lineTo(w * .44, w * .67)
      ..lineTo(w * .73, w * .35);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width > 40 ? 3 : 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.onPrimary,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// What a circle shows while its step works: each new item (a photo just indexed, a face just found) shown once, in the
/// order they came, and the last one kept while nothing new has come. [ids] is newest first, as the scan reports them.
///
/// The items come in bursts, a few every half second or so, so showing each as it arrives would stop and start. They are
/// queued and shown at an even pace instead, the pace they arrive at on average, one slightly behind what is happening.
/// A short queue slows the pace and a long one speeds it up, so the circle seldom runs dry and does not fall behind. One
/// picture fades into the next, so the change flows.
///
/// While [held] the circle does not change. The picture fades and a pause sign pulses over it, and with nothing to show
/// yet the sign is alone. With motion off a new item appears at once, and the sign does not pulse.
class _FlipNew<K extends Object> extends StatefulWidget {
  const _FlipNew({required this.ids, required this.load, required this.held, required this.fallback, this.stopped = false});

  final List<K> ids;
  final Future<Uint8List> Function(K id) load;
  final bool held;

  /// Set while the scan is stopped: the pause sign fades away and the picture is simply dimmed.
  final bool stopped;

  /// Shown until the first picture has been read.
  final IconData fallback;

  @override
  State<_FlipNew<K>> createState() => _FlipNewState<K>();
}

class _FlipNewState<K extends Object> extends State<_FlipNew<K>> with SingleTickerProviderStateMixin {
  static const _waiting = 12;
  static const _atOnce = 3;

  /// How many items should wait in the queue, and the quickest and slowest the pictures follow each other, in
  /// milliseconds. Scan progress is reported every half second, so something new is nearly always on its way.
  static const _targetDepth = 3;
  static const _quickest = 90.0;
  static const _slowest = 500.0;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  final Map<K, Uint8List> _bytes = {};
  final Set<K> _loading = {};
  final Set<K> _seen = {};
  final List<K> _queue = [];
  Timer? _timer;
  bool _flipping = false;
  K? _shown;

  /// How many items arrive per second, smoothed, and when the last ones came.
  double _rate = 0;
  DateTime? _arrivedAt;
  Duration _fade = const Duration(milliseconds: 160);

  @override
  void initState() {
    super.initState();
    _enqueue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(covariant _FlipNew<K> old) {
    super.didUpdateWidget(old);
    _enqueue();
    _follow();
  }

  void _enqueue() {
    var added = 0;
    for (final id in widget.ids.reversed) {
      if (_seen.add(id)) {
        _queue.add(id);
        added++;
      }
    }
    if (_queue.length > _waiting) _queue.removeRange(0, _queue.length - _waiting);
    if (added > 0) _noteArrival(added);
    _fetch();
  }

  void _noteArrival(int count) {
    final now = DateTime.now();
    final before = _arrivedAt;
    _arrivedAt = now;
    if (before == null) return;
    final seconds = now.difference(before).inMilliseconds / 1000;
    if (seconds < 0.05) return;
    final instant = count / seconds;
    _rate = _rate == 0 ? instant : _rate * 0.6 + instant * 0.4;
  }

  void _fetch() {
    for (final id in List.of(_queue)) {
      if (_loading.length >= _atOnce) break;
      if (_bytes.containsKey(id) || _loading.contains(id)) continue;
      _loading.add(id);
      widget.load(id).then<void>((bytes) {
        if (!mounted) return;
        _bytes[id] = bytes;
        if (calm(context) || (widget.held && _shown == null)) {
          setState(_showNewest);
        } else if (_shown == null) {
          setState(_showNext);
        }
      }).catchError((_) {}).whenComplete(() {
        _loading.remove(id);
        if (mounted) _fetch();
      });
    }
  }

  void _follow() {
    final flip = !widget.held && TickerMode.of(context) && !calm(context);
    _flipping = flip;
    if (flip && _timer == null) {
      _schedule();
    } else if (!flip) {
      _timer?.cancel();
      _timer = null;
    }
    if (widget.held && !widget.stopped) {
      loopUnlessCalm(context, _pulse, reverse: true, rest: 1);
    } else {
      _pulse.stop();
    }
  }

  /// How long until the next picture: the pace the items arrive at, stretched when few are waiting and squeezed when
  /// many are.
  Duration _delay() {
    final pace = _rate > 0 ? 1000 / _rate : 250.0;
    final crowd = (_targetDepth / math.max(_queue.length, 1)).clamp(0.5, 2.0);
    return Duration(milliseconds: (pace * crowd).clamp(_quickest, _slowest).round());
  }

  void _schedule() {
    final delay = _delay();
    _fade = Duration(milliseconds: delay.inMilliseconds.clamp(120, 260));
    _timer = Timer(delay, () {
      _timer = null;
      if (!mounted) return;
      if (_showNext()) setState(() {});
      if (_flipping) _schedule();
    });
  }

  bool _showNext() {
    final at = _queue.indexWhere(_bytes.containsKey);
    if (at < 0) return false;
    _take(_queue[at], at);
    return true;
  }

  void _showNewest() {
    final at = _queue.lastIndexWhere(_bytes.containsKey);
    if (at < 0) return;
    _take(_queue[at], at);
  }

  void _take(K id, int at) {
    _shown = id;
    _queue.removeRange(0, at + 1);
    _bytes.removeWhere((key, _) => key != id && !_queue.contains(key));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final bytes = shown == null ? null : _bytes[shown];
    if (!widget.held) {
      if (bytes == null) return Center(child: Icon(widget.fallback, size: 20, color: AppColors.primary));
      if (calm(context)) return _Picture(bytes);
      return AnimatedSwitcher(
        duration: _fade,
        child: KeyedSubtree(key: ValueKey<K?>(shown), child: _Picture(bytes)),
      );
    }
    final sign = FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: const Icon(Icons.pause_rounded, size: 22, color: AppColors.primary),
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        if (bytes != null) Positioned.fill(child: Opacity(opacity: 0.4, child: _Picture(bytes))),
        if (bytes == null && widget.stopped) Icon(widget.fallback, size: 20, color: AppColors.ink48),
        AnimatedOpacity(
          opacity: widget.stopped ? 0 : 1,
          duration: calm(context) ? Duration.zero : const Duration(milliseconds: 300),
          child: sign,
        ),
      ],
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture(this.bytes);

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: 120,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.parchment),
      ),
    );
  }
}
