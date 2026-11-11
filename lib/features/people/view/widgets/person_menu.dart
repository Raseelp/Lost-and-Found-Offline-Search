import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/export/controllers/export_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/export/view/export_zip_screen.dart';
import 'package:lost_and_found/features/people/view/face_review_screen.dart';
import 'package:lost_and_found/features/people/features/merge/view/split_person_screen.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/view/widgets/person_demo.dart';
import 'package:lost_and_found/features/people/models/person.dart';
part 'person_menu/show_person_menu.dart';
part 'person_menu/show_merge_picker.dart';
part 'person_menu/orbit.dart';
part 'person_menu/orbit_button.dart';
part 'person_menu/bubble.dart';

/// The five everyday actions (everything but rename, which sits under the name with its own pencil icon) as small
/// round buttons floating around the person's photo, because a "⋯" tap was too easy to miss. Same actions and calls as
/// [showPersonMenu]. They pop in with a light, staggered bounce the moment the page opens, so there is nothing to
/// discover.
class PersonHeadActions extends StatefulWidget {
  const PersonHeadActions({super.key, required this.faces, required this.person, this.size = 104});

  final FacesController faces;
  final Person person;
  final double size;

  @override
  State<PersonHeadActions> createState() => _PersonHeadActionsState();
}

class _PersonHeadActionsState extends State<PersonHeadActions> with TickerProviderStateMixin {
  /// Not forward()ed here, see initState, which waits out the page's own transition first so the pop-in plays on a
  /// screen that sits still. It is slow (620ms) on purpose: started any earlier it was mostly done before that
  /// transition settled.
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) _in.forward();
    });
    _loadCast();
  }

  @override
  void didUpdateWidget(covariant PersonHeadActions old) {
    super.didUpdateWidget(old);
    if (old.person.id != widget.person.id) {
      _moreFaces = const [];
      _loadCast();
    }
  }

  /// More of the person's faces than their tile's three, so the demos' grids look like theirs.
  List<int> _moreFaces = const [];

  /// Fetched once, quietly, and the pictures made ahead, so a demo never starts on blank circles.
  Future<void> _loadCast() async {
    final faces = widget.faces;
    final asked = widget.person.id;
    try {
      final found = await faces.facesOf(widget.person);
      if (!mounted || widget.person.id != asked) return;
      _moreFaces = [for (final f in found) if (f.good) f.faceId].take(12).toList();
    } catch (_) {
      // The tile's faces are enough.
    }
    final cast = _cast();
    for (final pic in [...cast.me, for (final (p, _) in cast.others) p]) {
      final id = pic.faceId;
      if (id != null && faces.cachedCrop(id) == null) faces.crop(id).whenComplete(() => faces.releaseCrop(id));
    }
  }

  /// The tour's demo people, standing in for others when the library has fewer than four.
  static const _standIns = [
    ('assets/tour/faces/maya.jpg', 'Maya'),
    ('assets/tour/faces/sam.jpg', 'Sam'),
    ('assets/tour/faces/noor.jpg', 'Noor'),
    ('assets/tour/faces/leo.jpg', 'Dev'),
  ];

  DemoCast _cast() {
    final person = widget.person;
    final faces = widget.faces;
    final mine = <int>{person.coverFaceId, ...person.stackFaceIds, ..._moreFaces}.take(10).toList();
    final others = <(DemoPic, String)>[
      for (final p in faces.people)
        if (p.id != person.id && !p.hidden) (DemoPic.face(p.coverFaceId), p.name ?? ''),
    ].take(4).toList();
    for (final (asset, name) in _standIns) {
      if (others.length >= 4) break;
      others.add((DemoPic.asset(asset), name));
    }
    final photos = <DemoPic>[];
    if (faces.active?.id == person.id) {
      for (final item in faces.photos) {
        final bytes = faces.photoThumbs[FacesController.thumbKey(item)];
        if (bytes != null) photos.add(DemoPic.bytes(bytes));
        if (photos.length == 6) break;
      }
    }
    for (var i = 0; photos.length < 6; i++) {
      photos.add(DemoPic.face(mine[i % mine.length]));
    }
    return DemoCast(
      me: [for (final id in mine) DemoPic.face(id)],
      name: person.name,
      photoCount: person.photoCount,
      others: others,
      photos: photos,
    );
  }

  /// The button that was tapped, waiting to be confirmed. Null: showing the orbit as normal. Three animations play one
  /// after another: _burst pulls the other four buttons into the tapped one, which turns into a glowing badge; _travel
  /// flies the badge to where the photo was; then the explanation opens as a speech bubble in its own overlay (see
  /// _bubbleEntry), so it never resizes this page's scroll content and jostles the photo grid. Cancelling or
  /// confirming folds the bubble away and reverses the rest, except on confirm, when the page is leaving anyway.
  _Orbit? _pending;
  int _pendingIndex = 0;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final AnimationController _travel = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  /// 0: the fixes are folded into "Fix mistakes" at the bottom; 1: they are out, completing the ring.
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 360),
  );

  void _toggleFixes() {
    HapticFeedback.selectionClick();
    _fan.isForwardOrCompleted ? _fan.reverse() : _fan.forward();
  }

  /// Anchors the floating bubble to wherever the badge ends up, so it tracks it with no
  /// layout coupling at all between the two.
  final LayerLink _badgeLink = LayerLink();
  OverlayEntry? _bubbleEntry;
  late final AnimationController _bubbleFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  /// Gap between the badge's edge and the bubble's tail: half the badge's biggest size plus a little breathing room.
  static const _bubbleGap = _bigBadge / 2 + 8;

  void _ask(int index, _Orbit action) {
    HapticFeedback.selectionClick();
    setState(() {
      _pending = action;
      _pendingIndex = index;
    });
    _burst.forward(from: 0).whenComplete(() {
      if (!mounted || _pending != action) return;
      HapticFeedback.selectionClick();
      _travel.forward(from: 0).whenComplete(() {
        if (mounted && _pending == action) _showBubbleOverlay();
      });
    });
  }

  void _showBubbleOverlay() {
    final action = _pending;
    if (action == null) return;
    _removeBubbleOverlay();
    _bubbleEntry = OverlayEntry(
      builder: (overlayContext) {
        final bubbleWidth = math.min(MediaQuery.sizeOf(overlayContext).width - AppSpacing.xxxl, 320.0);
        return CompositedTransformFollower(
          link: _badgeLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, _bubbleGap),
          // The Overlay gives top-level entries a full-screen box, which the bubble's Stack would fill.
          // UnconstrainedBox lets it shrink to its content.
          child: UnconstrainedBox(
            alignment: Alignment.topCenter,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: _bubbleFade,
                builder: (context, child) => Opacity(
                  opacity: _bubbleFade.value,
                  child: Transform.translate(offset: Offset(0, (1 - _bubbleFade.value) * -8), child: child),
                ),
                child: _Bubble(
                  width: bubbleWidth,
                  action: action,
                  cast: _cast(),
                  onCancel: _close,
                  onConfirm: _confirm,
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_bubbleEntry!);
    _bubbleFade.forward(from: 0);
  }

  void _removeBubbleOverlay() {
    final entry = _bubbleEntry;
    if (entry == null) return;
    _bubbleEntry = null;
    entry.remove();
  }

  void _close() {
    _bubbleFade.reverse().whenComplete(_removeBubbleOverlay);
    _travel.reverse().whenComplete(() {
      if (!mounted || _pending == null) return;
      _burst.reverse().whenComplete(() {
        if (mounted) setState(() => _pending = null);
      });
    });
  }

  /// The bubble stays visible, fading out, for a beat after this runs (see the 140ms delay below), so a fast
  /// double-tap on Confirm could land twice and run the action twice. _confirming guards against that without touching
  /// the timing anything else relies on.
  bool _confirming = false;

  void _confirm() {
    final action = _pending;
    if (_confirming || action == null) return;
    _confirming = true;
    _bubbleFade.reverse().whenComplete(() {
      _removeBubbleOverlay();
      _confirming = false;
    });
    Future.delayed(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      setState(() => _pending = null);
      action.onTap();
    });
  }

  @override
  void dispose() {
    _removeBubbleOverlay();
    _in.dispose();
    _burst.dispose();
    _travel.dispose();
    _fan.dispose();
    _bubbleFade.dispose();
    super.dispose();
  }

  List<_Orbit> _actions(BuildContext context) {
    final name = widget.person.name;
    return [
      _Orbit(
        icon: Icons.groups_rounded,
        label: 'With someone',
        title: name == null ? 'See them with someone?' : 'See $name with someone?',
        message: 'Pick a person. You get the photos they are both in.',
        confirmLabel: 'Choose someone',
        demo: PersonDemoKind.together,
        onTap: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          Get.find<NativeController>().setHomeTab(3);
          widget.faces.startSelecting(widget.person);
        },
      ),
      _Orbit(
        icon: Icons.folder_zip_outlined,
        label: 'Save photos',
        title: name == null ? 'Save all their photos?' : "Save all of $name's photos?",
        message: 'Every photo and video of ${name ?? 'them'} in one zip file.',
        confirmLabel: 'Save',
        demo: PersonDemoKind.save,
        onTap: () => openExportZip(context, select: {ExportController.personKey(widget.person.id)}),
      ),
      _Orbit(
        icon: Icons.visibility_off_outlined,
        label: 'Hide',
        title: name == null ? 'Hide this person?' : 'Hide $name?',
        message: '${name ?? 'They'} ${name == null ? 'move' : 'moves'} to Hidden people in Settings. Nothing is deleted.',
        confirmLabel: 'Hide',
        demo: PersonDemoKind.hide,
        danger: true,
        onTap: () => widget.faces.setHidden(widget.person, true),
      ),
      _Orbit(
        icon: Icons.grid_view_rounded,
        label: 'Not them',
        fix: true,
        title: name == null ? "Faces that aren't this person?" : "Faces that aren't $name?",
        message: "Tap any face that isn't ${name ?? 'them'} to take it out.",
        confirmLabel: 'Check faces',
        demo: PersonDemoKind.check,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FaceReviewScreen(person: widget.person)),
        ),
      ),
      _Orbit(
        icon: Icons.merge_type_rounded,
        label: 'Shown twice',
        fix: true,
        title: name == null ? 'Is this person here twice?' : 'Is $name here twice?',
        message: 'Join the two into one. Every photo of both is kept.',
        confirmLabel: 'Choose the other',
        demo: PersonDemoKind.merge,
        onTap: () => showMergePicker(context, widget.faces, widget.person),
      ),
      _Orbit(
        icon: Icons.call_split_rounded,
        label: 'Mixed up',
        fix: true,
        title: name == null ? 'Two people mixed up here?' : 'Two people mixed up as $name?',
        message: 'Pull them apart into two people.',
        confirmLabel: 'Separate them',
        demo: PersonDemoKind.separate,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SplitPersonScreen(person: widget.person)),
        ),
      ),
    ];
  }

  /// Degrees, 0 = straight up, clockwise. Folded, four circles a quarter apart: the everyday three at the
  /// left, top and right, "Fix mistakes" at the bottom. Opened, six a sixth apart: the everyday three move
  /// up round the ring to make room, "Fix mistakes" turns into Shown twice where it is, and the other two
  /// fixes come out of it either side. The name sits below this whole box.
  static const _foldedAngles = [-90.0, 0.0, 90.0, 180.0, 180.0, 180.0];
  static const _openAngles = [-60.0, 0.0, 60.0, 240.0, 180.0, 120.0];
  static const _doorAngle = 180.0;

  /// Where the circle [i] is on the ring with the fixes [fan] of the way out.
  double _angleOf(int i, double fan) {
    final t = i < 3 ? Curves.easeInOutCubic.transform(fan) : Curves.easeOutCubic.transform(_emerge(i, fan));
    return _foldedAngles[i] + (_openAngles[i] - _foldedAngles[i]) * t;
  }

  /// How far out a fix is: Shown twice is there at once (it is "Fix mistakes" turned over); the other
  /// two leave it a moment later, one after the other.
  static double _emerge(int i, double fan) => switch (i) {
    4 => const Interval(0, 0.45).transform(fan),
    3 => const Interval(0.18, 0.9).transform(fan),
    5 => const Interval(0.28, 1).transform(fan),
    _ => fan,
  };

  /// Each button lives in a box this big, centred on its orbit point. The size is fixed rather than measured from the
  /// icon and label, so the tap target is exactly where it is drawn.
  static const _slot = 72.0;

  /// How big the badge gets once it's finished travelling to the photo's spot.
  static const _bigBadge = 88.0;

  Widget _headStack(BuildContext context, List<_Orbit> actions) {
    final avatarRadius = widget.size / 2;
    const iconSize = 40.0;
    final orbitRadius = avatarRadius + iconSize / 2 + 32;
    final boxSize = math.max(orbitRadius * 2 + iconSize + 36, _bigBadge + 40);
    final center = boxSize / 2;

    final pendingIndex = _pending == null ? null : _pendingIndex;
    Offset at(double degrees) {
      final angle = degrees * math.pi / 180;
      return Offset(orbitRadius * math.sin(angle), -orbitRadius * math.cos(angle));
    }

    Offset offsetOf(int i) => at(_angleOf(i, _fan.value));

    final tappedOffset = pendingIndex == null ? Offset.zero : offsetOf(pendingIndex);
    final doorOffset = at(_doorAngle);

    final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: center - avatarRadius,
              top: center - avatarRadius,
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _travel,
                builder: (context, child) => Opacity(opacity: 1 - _travel.value, child: child),
                child: FaceAvatar(faceId: widget.person.coverFaceId, size: widget.size),
              ),
            ),
            for (var i = 0; i < actions.length; i++)
              if (pendingIndex != i)
                Builder(
                  builder: (context) {
                    final fix = actions[i].fix;
                    final start = (fix ? 3 : i) / 4 * 0.35;
                    return Positioned(
                      left: center - _slot / 2,
                      top: center - _slot / 2,
                      width: _slot,
                      height: _slot,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_in, _burst, _fan]),
                        builder: (context, child) {
                          final ownOffset = offsetOf(i);
                          final entrance = Curves.easeOutBack.transform(
                            Interval(start, start + 0.55, curve: Curves.linear).transform(_in.value),
                          );
                          final burstT = pendingIndex == null ? 0.0 : Curves.easeInOutCubic.transform(_burst.value);
                          final delta = ownOffset + (tappedOffset - ownOffset) * burstT;
                          var opacity = (1.0 - burstT) * entrance.clamp(0.0, 1.0);
                          var scale = (1.0 - 0.55 * burstT) * entrance.clamp(0.0, 1.4);
                          if (fix) {
                            final out = _emerge(i, _fan.value);
                            if (i == 4) {
                              opacity *= out;
                              scale *= 1 + 0.14 * math.sin(math.pi * const Interval(0, 0.6).transform(_fan.value));
                            } else {
                              opacity *= (out * 2.5).clamp(0.0, 1.0);
                              scale *= 0.35 + 0.65 * Curves.easeOutBack.transform(out);
                            }
                          }
                          return Transform.translate(
                            offset: delta,
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: Transform.scale(scale: scale.clamp(0.0, 1.4), child: child),
                            ),
                          );
                        },
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _fan,
                            builder: (context, _) => _OrbitButton(
                              action: actions[i],
                              onTap: _pending == null && (!fix || _fan.value > 0.6) ? () => _ask(i, actions[i]) : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            Positioned(
              left: center + doorOffset.dx - _slot / 2,
              top: center + doorOffset.dy - _slot / 2,
              width: _slot,
              height: _slot,
              child: AnimatedBuilder(
                animation: Listenable.merge([_in, _burst, _fan]),
                builder: (context, child) {
                  final entrance = Curves.easeOutBack.transform(
                    const Interval(0.26, 0.81, curve: Curves.linear).transform(_in.value),
                  );
                  final burstT = pendingIndex == null ? 0.0 : Curves.easeInOutCubic.transform(_burst.value);
                  final turn = _emerge(4, _fan.value);
                  final swell = 1 + 0.14 * math.sin(math.pi * const Interval(0, 0.6).transform(_fan.value));
                  final opacity = entrance.clamp(0.0, 1.0) * (1 - turn) * (1 - burstT);
                  return IgnorePointer(
                    ignoring: _fan.value > 0.3 || _pending != null,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(scale: entrance.clamp(0.0, 1.4) * swell, child: child),
                    ),
                  );
                },
                child: Center(
                  child: _OrbitButton(
                    action: _Orbit(
                      icon: Icons.build_outlined,
                      label: 'Fix mistakes',
                      title: '',
                      message: '',
                      confirmLabel: '',
                      demo: PersonDemoKind.check,
                      fix: true,
                      onTap: _toggleFixes,
                    ),
                    onTap: _toggleFixes,
                  ),
                ),
              ),
            ),
            Positioned(
              left: center - 22,
              top: center + avatarRadius - 22,
              width: 44,
              height: 44,
              child: AnimatedBuilder(
                animation: Listenable.merge([_burst, _fan]),
                builder: (context, child) {
                  final burstT = pendingIndex == null ? 0.0 : _burst.value;
                  final shown = Curves.easeOutBack.transform(const Interval(0.4, 1).transform(_fan.value));
                  return IgnorePointer(
                    ignoring: _fan.value < 0.6 || _pending != null,
                    child: Opacity(
                      opacity: (shown * (1 - burstT)).clamp(0.0, 1.0),
                      child: Transform.scale(scale: shown.clamp(0.0, 1.3), child: child),
                    ),
                  );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleFixes,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 30,
                      child: Semantics(
                  button: true,
                  label: 'Fold the fixes away',
                  child: Material(
                    color: AppColors.canvas,
                    shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
                    elevation: 2,
                    shadowColor: AppColors.ink.withValues(alpha: 0.3),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _toggleFixes,
                      child: const Icon(Icons.close_rounded, size: 16, color: AppColors.ink48),
                    ),
                  ),
                ),
                    ),
                  ),
                ),
              ),
            ),
            if (pendingIndex != null)
              Builder(
                builder: (context) {
                  final accent = actions[pendingIndex].danger ? AppColors.danger : AppColors.primary;
                  return AnimatedBuilder(
                    animation: Listenable.merge([_burst, _travel]),
                    builder: (context, _) {
                      final burstT = Curves.easeInOutCubic.transform(_burst.value);
                      final travelT = Curves.easeInOutCubic.transform(_travel.value);
                      final pos = Offset.lerp(tappedOffset, Offset.zero, travelT)!;
                      final pulse = 1.0 + 0.18 * math.sin(burstT * math.pi) * (1 - travelT);
                      final diameter = (iconSize + (_bigBadge - iconSize) * travelT) * pulse;
                      return Positioned(
                        left: center + pos.dx - diameter / 2,
                        top: center + pos.dy - diameter / 2,
                        width: diameter,
                        height: diameter,
                        child: _TravelBadge(icon: actions[pendingIndex].icon, color: accent),
                      );
                    },
                  );
                },
              ),
            if (pendingIndex != null)
              Positioned(
                left: center + tappedOffset.dx - 45,
                top: center + tappedOffset.dy - 45,
                width: 90,
                height: 90,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_burst, _travel]),
                    builder: (context, _) => Opacity(
                      opacity: (1 - _travel.value).clamp(0.0, 1.0),
                      child: CustomPaint(
                        painter: _BurstPainter(
                          _burst.value,
                          actions[pendingIndex].danger ? AppColors.danger : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

    // A fixed size, always: the badge growing or the bubble opening must not change this box's footprint in the page's
    // scroll content and push the photo grid.
    return RepaintBoundary(
      child: CompositedTransformTarget(
        link: _badgeLink,
        child: SizedBox(width: boxSize, height: boxSize, child: stack),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _headStack(context, _actions(context));
}

/// The pulse the tapped button gathers while the others converge into it: a soft glow at its centre and a couple of
/// rings spreading outward and fading, the same "something is happening here" language the rest of the app uses.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);

  /// Progress from 0 to 1.
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final center = size.center(Offset.zero);
    final glow = Curves.easeOut.transform(t);
    canvas.drawCircle(
      center,
      26,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: 0.38 * glow), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: 26)),
    );
    for (var k = 0; k < 2; k++) {
      final p = ((t - k * 0.24) / 0.6).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final radius = 8 + 28 * Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t || old.color != color;
}

/// What the tapped orbit button becomes: a solid, glowing circle carrying just its icon. It has no label because by
/// the time it has grown it sits where the photo was and speaks for itself.
class _TravelBadge extends StatelessWidget {
  const _TravelBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: -2),
          BoxShadow(color: AppColors.ink.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.none,
        child: Icon(icon, color: AppColors.onPrimary, size: 22),
      ),
    );
  }
}
