import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/export_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/export_zip_screen.dart';
import 'package:lost_and_found/view/face_review_screen.dart';
import 'package:lost_and_found/view/split_person_screen.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/person_demo.dart';

/// Everything you can do with one person, in one menu - opened by holding a face in
/// the People tab. (Their own page shows these as [PersonHeadActions] instead - the
/// same five actions, floating round their head rather than hidden behind a tap.)
void showPersonMenu(
  BuildContext context,
  FacesController faces,
  Person person,
) {
  showFacesSheet<void>(
    context,
    title: person.name ?? 'This person',
    // Everyday things first; the three that fix the app's mistakes after, under their own heading, each
    // saying which mistake it is for (so they are not confused with one another). Scrolls on a short screen.
    builder: (sheet) => SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetRow(
          icon: Icons.edit_outlined,
          label: person.name == null ? 'Add a name' : 'Rename',
          subtitle: person.name == null ? 'So you can search for them by name' : 'Change the name shown everywhere',
          onTap: () async {
            Navigator.of(sheet).pop();
            final name = await showRenamePersonDialog(context, person.name);
            if (name != null) faces.rename(person, name);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.folder_zip_outlined,
          label: 'Save all their photos',
          subtitle: '${person.name == null ? 'Their' : "${person.name}'s"} photos and videos in one zip file',
          onTap: () {
            Navigator.of(sheet).pop();
            openExportZip(context, select: {ExportController.personKey(person.id)});
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.groups_rounded,
          label: 'Photos with someone else',
          subtitle: "Pick a person to see photos they're both in",
          onTap: () {
            Navigator.of(sheet).pop();
            // To the People tab, in "choose people" mode with this one ticked
            // (from a person's own page that means going back to it first).
            Navigator.of(context).popUntil((route) => route.isFirst);
            Get.find<NativeController>().setHomeTab(3);
            faces.startSelecting(person);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.visibility_off_outlined,
          label: 'Hide this person',
          subtitle: 'They move to Hidden people in Settings',
          onTap: () {
            Navigator.of(sheet).pop();
            faces.setHidden(person, true);
          },
        ),
        const _MenuHeading('Fix mistakes'),
        SheetRow(
          icon: Icons.merge_type_rounded,
          label: 'Merge duplicates',
          subtitle: 'A person appears more than once? Join them',
          onTap: () {
            Navigator.of(sheet).pop();
            showMergePicker(context, faces, person);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.call_split_rounded,
          label: 'Separate two people',
          subtitle: 'Use this when this card has two different people in it',
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SplitPersonScreen(person: person)),
            );
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.grid_view_rounded,
          label: 'Check their faces',
          subtitle: 'Remove any face that belongs to someone else',
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FaceReviewScreen(person: person),
              ),
            );
          },
        ),
      ],
      ),
    ),
  );
}

/// A small heading over a group of the menu's rows, in the style of the app's other list headings.
class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: .5,
          ),
        ),
      ),
    );
  }
}

/// Everyone else, the likeliest matches first; tapping one asks to confirm the merge.
void showMergePicker(
  BuildContext context,
  FacesController faces,
  Person person,
) {
  final others = faces.people.where((p) => p.id != person.id).toList()
    ..sort((x, y) {
      final sx = faces.suggestionScoreFor(person, x) ?? -1;
      final sy = faces.suggestionScoreFor(person, y) ?? -1;
      if (sx != sy) return sy.compareTo(sx);
      return y.photoCount.compareTo(x.photoCount);
    });

  showFacesSheet<void>(
    context,
    title: 'Merge ${person.name ?? 'this person'} with...',
    builder: (sheet) => others.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text('There is nobody else to merge with yet.'),
          )
        : ListView.separated(
            shrinkWrap: true,
            itemCount: others.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.dividerSoft),
            itemBuilder: (_, i) {
              final other = others[i];
              final suggested = faces.suggestionScoreFor(person, other) != null;
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  Navigator.of(sheet).pop();
                  confirmMerge(context, faces, keep: person, other: other);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      FaceAvatar(faceId: other.coverFaceId, size: 44),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          other.name ??
                              'Unnamed  ·  ${other.photoCount} photos',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
      if (suggested)
                        Text(
                          'Looks similar',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.primary),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

/// The five everyday actions (everything but rename, which sits under the name with its
/// own pencil icon) as small round buttons floating around the person's photo instead of
/// behind a "⋯" tap - the dots were too easy to miss. Same actions, same calls, as
/// [showPersonMenu]. They pop in with a light, staggered bounce the moment the page opens,
/// so there's nothing to discover - they're just there.
class PersonHeadActions extends StatefulWidget {
  const PersonHeadActions({super.key, required this.faces, required this.person, this.size = 104});

  final FacesController faces;
  final Person person;
  final double size;

  @override
  State<PersonHeadActions> createState() => _PersonHeadActionsState();
}

class _Orbit {
  const _Orbit({
    required this.icon,
    required this.label,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.demo,
    required this.onTap,
    this.danger = false,
    this.fix = false,
  });

  final IconData icon;
  final String label; // the short caption under the button: the situation it is for
  final String title; // the bubble's heading, asked as a question about the person
  final String message; // one short line under the demo
  final String confirmLabel; // the bubble's action button
  final PersonDemoKind demo; // the little film the bubble plays of what it does
  final bool fix; // one of the three that fix the app's mistakes, kept behind "Fix mistakes"
  final VoidCallback onTap;
  final bool danger;
}

class _PersonHeadActionsState extends State<PersonHeadActions> with TickerProviderStateMixin {
  // Not forward()'d here - see initState. Slower than it was (620ms), too: at that speed and
  // starting the instant this widget existed, it was mostly done before the page's own push
  // transition had even settled, so it came and went before anyone was looking at it.
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    // Waits out the page's own transition first, so the pop-in plays on a screen that's already
    // sitting still in front of the user rather than racing their arrival.
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) _in.forward();
    });
    _loadCast();
  }

  @override
  void didUpdateWidget(covariant PersonHeadActions old) {
    super.didUpdateWidget(old);
    // Another person shown here (after a merge, say): their faces, not the last one's.
    if (old.person.id != widget.person.id) {
      _moreFaces = const [];
      _loadCast();
    }
  }

  // ---- What the bubbles' demos are made of (see PersonDemo) ----

  // More of the person's faces than their tile's three, so the demos' grids look like theirs.
  List<int> _moreFaces = const [];

  // Fetched once, quietly, and the pictures made ahead, so a demo never starts on blank circles.
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

  // The tour's demo people, standing in for others when the library has fewer than four.
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
    // Their photos already on this page; their faces fill in for any not loaded yet.
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

  // The button that was tapped, waiting to be confirmed. Null: showing the orbit as normal.
  // The whole sequence is three animations played one after another:
  //   1. _burst (0->1): the other four buttons are pulled in toward the tapped one and fade
  //      out, while it turns into a solid glowing badge and pulses - gathering everything
  //      into one point.
  //   2. _travel (0->1): that badge then flies from its spot in the orbit to the middle,
  //      growing as it goes, until it's sitting where the photo was.
  //   3. the explanation opens as a speech bubble underneath it, floating in its own overlay
  //      (see _bubbleEntry) rather than as another widget in this column - so it can appear
  //      and disappear without ever resizing this page's scroll content, which would jostle
  //      the photo grid below every time.
  // Cancelling or confirming folds the bubble away, then reverses 2 and 1 to bring
  // everything back (skipped on confirm, since the page is about to leave anyway).
  _Orbit? _pending;
  int _pendingIndex = 0;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final AnimationController _travel = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  // 0: the fixes are folded into "Fix mistakes" at the bottom; 1: they are out, completing the ring.
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 360),
  );

  void _toggleFixes() {
    HapticFeedback.selectionClick();
    _fan.isForwardOrCompleted ? _fan.reverse() : _fan.forward();
  }

  // Anchors the floating bubble to wherever the badge ends up, so it tracks it with no
  // layout coupling at all between the two.
  final LayerLink _badgeLink = LayerLink();
  OverlayEntry? _bubbleEntry;
  late final AnimationController _bubbleFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  // Gap between the badge's edge and the bubble's tail - half the badge's biggest size,
  // plus a little breathing room.
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
          // Between the badge and the photos below it, tail pointing up at the badge.
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, _bubbleGap),
          // The Overlay always hands its top-level entries a full-screen-sized box to fill,
          // same as it would a route's page. Without this, the bubble's Stack (and its
          // Positioned.fill background) would inherit that full height instead of shrinking
          // to its own content - UnconstrainedBox is what lets it ignore that and size (and
          // paint) itself only as large as it actually needs to be.
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
    // The bubble fading away, the badge setting off on its way back, and the orbit
    // reassembling all start together - one fold-away motion, not one thing waiting on
    // another.
    _bubbleFade.reverse().whenComplete(_removeBubbleOverlay);
    _travel.reverse().whenComplete(() {
      if (!mounted || _pending == null) return;
      _burst.reverse().whenComplete(() {
        if (mounted) setState(() => _pending = null);
      });
    });
  }

  // The bubble stays visible (fading out) for a beat after this runs - see the 140ms delay
  // below - so a fast double-tap on Confirm could otherwise land twice and run the action
  // twice (pushing Split/Review's screen twice, for instance). _confirming guards against
  // that without touching the timing anything else here relies on.
  bool _confirming = false;

  void _confirm() {
    final action = _pending;
    if (_confirming || action == null) return;
    _confirming = true;
    // Ready for the next time once the bubble is gone (it stays set until then, for the double-tap).
    _bubbleFade.reverse().whenComplete(() {
      _removeBubbleOverlay();
      _confirming = false;
    });
    // Snappy on purpose: the page is about to leave (or another sheet is about to open) -
    // watching everything fly back first would just be a delay.
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
    // Each caption names the situation it is for; each bubble asks it about this person, plays a
    // short film of what happens, and says it in one line. The everyday three go round the top; the
    // three that fix the app's mistakes wait behind "Fix mistakes" at the bottom (see _fan).
    return [
      _Orbit(
        icon: Icons.groups_rounded,
        label: 'With someone',
        title: name == null ? 'See them with someone?' : 'See $name with someone?',
        message: 'Pick a person. You get the photos they are both in.',
        confirmLabel: 'Choose someone',
        demo: PersonDemoKind.together,
        onTap: () {
          // To the People tab, in "choose people" mode with this one ticked.
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
      // The fixes, named by what looks wrong.
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

  // Degrees, 0 = straight up, clockwise. Folded, four circles a quarter apart: the everyday three at the
  // left, top and right, "Fix mistakes" at the bottom. Opened, six a sixth apart: the everyday three move
  // up round the ring to make room, "Fix mistakes" turns into Shown twice where it is, and the other two
  // fixes come out of it either side. The name sits below this whole box.
  static const _foldedAngles = [-90.0, 0.0, 90.0, 180.0, 180.0, 180.0];
  static const _openAngles = [-60.0, 0.0, 60.0, 240.0, 180.0, 120.0];
  static const _doorAngle = 180.0;

  // Where the circle [i] is on the ring with the fixes [fan] of the way out.
  double _angleOf(int i, double fan) {
    final t = i < 3 ? Curves.easeInOutCubic.transform(fan) : Curves.easeOutCubic.transform(_emerge(i, fan));
    return _foldedAngles[i] + (_openAngles[i] - _foldedAngles[i]) * t;
  }

  // How far out a fix is: Shown twice is there at once (it is "Fix mistakes" turned over); the other
  // two leave it a moment later, one after the other.
  static double _emerge(int i, double fan) => switch (i) {
    4 => const Interval(0, 0.45).transform(fan),
    3 => const Interval(0.18, 0.9).transform(fan),
    5 => const Interval(0.28, 1).transform(fan),
    _ => fan,
  };

  // Each button lives in a box this big, centred on its orbit point - a fixed size (not
  // whatever its icon+label happen to measure) so its tap target is exactly where it's
  // drawn, with no ambiguity for Stack/Positioned to get wrong.
  static const _slot = 72.0;

  // How big the badge gets once it's finished travelling to the photo's spot.
  static const _bigBadge = 88.0;

  Widget _headStack(BuildContext context, List<_Orbit> actions) {
    final avatarRadius = widget.size / 2;
    const iconSize = 40.0;
    // Far enough out that no caption touches the photo.
    final orbitRadius = avatarRadius + iconSize / 2 + 32;
    // Generous enough that no button, or the badge at its biggest, ever clips.
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
              // Fades out as the badge arrives and takes its place.
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
                    // The everyday ones pop in one after another, with a small overshoot.
                    final start = (fix ? 3 : i) / 4 * 0.35;
                    // Each sits in a slot centred on the photo and is carried round the ring from there,
                    // so it travels along the circle rather than across it.
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
                          // Pulled in toward wherever the tapped button is, and faded out -
                          // as though being gathered up into it.
                          final delta = ownOffset + (tappedOffset - ownOffset) * burstT;
                          var opacity = (1.0 - burstT) * entrance.clamp(0.0, 1.0);
                          var scale = (1.0 - 0.55 * burstT) * entrance.clamp(0.0, 1.4);
                          if (fix) {
                            final out = _emerge(i, _fan.value);
                            if (i == 4) {
                              // "Fix mistakes" turning over into this one, swelling with it.
                              opacity *= out;
                              scale *= 1 + 0.14 * math.sin(math.pi * const Interval(0, 0.6).transform(_fan.value));
                            } else {
                              // Budding out of it: small and faint at first, full size once clear.
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
                              // A fix can only be tapped once it is out.
                              onTap: _pending == null && (!fix || _fan.value > 0.6) ? () => _ask(i, actions[i]) : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            // "Fix mistakes", completing the ring at the bottom. Tapped, it swells a little and turns over
            // into Shown twice, while the other two fixes come out of it.
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
            // Folds the fixes back: a small close on the photo's lower edge, there while they are out.
            // Drawn 30 across, touched anywhere in 44.
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
            // The tapped button: a solid glowing badge from the moment it's tapped, that
            // then travels from its orbit spot to the middle and grows, ending up sitting
            // where the photo was.
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
            // The glow the badge gathers as everyone converges into it, fading away once
            // it sets off on its journey.
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

    // A fixed size, always - this box's footprint in the page's scroll content never
    // changes, no matter what's happening inside it (badge growing, bubble opening and
    // closing). The bubble floats in its own overlay instead of living in this layout, so
    // none of that ever pushes the photo grid below around.
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

class _OrbitButton extends StatelessWidget {
  const _OrbitButton({required this.action, required this.onTap});

  final _Orbit action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The fixes (and "Fix mistakes") are quieter than the everyday ones: no shadow, greyer.
    final quiet = action.fix;
    final color = action.danger ? AppColors.danger : (quiet ? AppColors.ink48 : AppColors.ink80);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: quiet ? AppColors.canvas : AppColors.pearl,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
                boxShadow: quiet
                    ? null
                    : [BoxShadow(color: AppColors.ink.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(action.icon, size: 18, color: color),
            ),
          ),
        ),
        const SizedBox(height: 3),
        // On one line, even where it runs a little wider than the button's slot. Tapping the words
        // works too.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            action.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: action.danger ? AppColors.danger : AppColors.ink48),
          ),
        ),
      ],
    );
  }
}

/// The pulse the tapped button gathers while the others converge into it: a soft glow at
/// its centre, and a couple of rings spreading outward and fading - the same "something is
/// happening here" language the rest of the app uses (the People button's pulse, the glow
/// around a recognised face), so this reads as one visual system rather than a one-off.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);

  final double t; // 0..1
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

/// What the tapped orbit button becomes: a solid, glowing circle carrying just its icon -
/// no label, since by the time it's grown large it's sitting where the photo was and
/// speaks for itself.
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

/// The explanation, as a speech bubble opening underneath the badge once it's arrived -
/// the badge is "speaking" it, rather than a boxy alert appearing out of nowhere. Cancel
/// sends the badge back on its way to the orbit; confirming runs the action once it's gone.
///
/// No Center wrapper here - this widget is sized by a CompositedTransformFollower, which
/// gives it the full overlay's loose-but-finite constraints; Center/Align would expand to
/// fill those rather than shrink to content the way they would inside a Column. A plain
/// SizedBox(width: ...) with no height set lets the Stack below size itself to its content.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.width,
    required this.action,
    required this.cast,
    required this.onCancel,
    required this.onConfirm,
  });

  final double width;
  final _Orbit action;
  final DemoCast cast;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  static const _tailHeight = 10.0;
  static const _tailWidth = 20.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = action.danger ? AppColors.danger : AppColors.primary;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _BubbleShapePainter(radius: AppRadius.xl, tailHeight: _tailHeight, tailWidth: _tailWidth),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, _tailHeight + AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action.title, textAlign: TextAlign.center, style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                // What it does, shown with this person's own faces and photos.
                PersonDemo(kind: action.demo, cast: cast),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  action.message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink80, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _BubbleButton(label: 'Cancel', color: AppColors.ink48, onTap: onCancel)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _BubbleButton(label: action.confirmLabel, color: accent, filled: true, onTap: onConfirm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bubble's background: a rounded rectangle with a small triangular notch at the top,
/// centre, pointing up at the badge it belongs to - one shape, one shadow, so the notch
/// never looks stuck on.
class _BubbleShapePainter extends CustomPainter {
  _BubbleShapePainter({required this.radius, required this.tailHeight, required this.tailWidth});

  final double radius;
  final double tailHeight;
  final double tailWidth;

  Path _shape(Size size) {
    final path = Path()
      ..addRRect(RRect.fromLTRBR(0, tailHeight, size.width, size.height, Radius.circular(radius)));
    final cx = size.width / 2;
    path
      ..moveTo(cx - tailWidth / 2, tailHeight)
      ..lineTo(cx, 0)
      ..lineTo(cx + tailWidth / 2, tailHeight)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _shape(size);
    canvas.drawShadow(path, AppColors.ink.withValues(alpha: 0.18), 8, false);
    canvas.drawPath(path, Paint()..color = AppColors.parchment);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.hairline,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleShapePainter old) => false;
}

class _BubbleButton extends StatelessWidget {
  const _BubbleButton({required this.label, required this.color, required this.onTap, this.filled = false});

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : AppColors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.hairline),
                ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: filled ? AppColors.onPrimary : color),
          ),
        ),
      ),
    );
  }
}
