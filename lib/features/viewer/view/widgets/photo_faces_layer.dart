import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/viewer/view/widgets/face_palette.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/models/person.dart';
import 'package:lost_and_found/features/people/models/photo_face.dart';
part 'photo_faces_layer/shared.dart';
part 'photo_faces_layer/flow_text.dart';
part 'photo_faces_layer/photo_scan_glow.dart';
part 'photo_faces_layer/person_chip.dart';
part 'photo_faces_layer/ring_painter.dart';
part 'photo_faces_layer/hint_painter.dart';
part 'photo_faces_layer/edge_glow_painter.dart';
part 'photo_faces_layer/face_flight_overlay.dart';

/// Lets you tap the people in a photo. Every recognised face is a tap target. Tapping one dims the rest, draws a
/// glowing ring that sweeps round the head and pops up that person's picture, which goes to their page when tapped. A
/// brief ripple on first showing hints that faces can be tapped.
///
/// It sits over the zoomable photo and follows its transform, so it stays on the head while pinching and panning, and
/// the ring keeps its thickness at any zoom.
class PhotoFacesLayer extends StatefulWidget {
  const PhotoFacesLayer({
    super.key,
    required this.faces,
    required this.transform,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    this.bottomInset = 0,
    this.entry,
  });

  /// Set when the face is already picked as this appears and a flight is landing on it: the
  /// outline then starts fully drawn, in the flight's own look, instead of drawing itself in.
  final RingEntry? entry;

  /// Extra room kept clear along the bottom (the caption sits above it): a video's controls.
  final double bottomInset;

  final List<PhotoFace> faces;
  final TransformationController transform;
  final PhotoFace? selected;
  final ValueChanged<PhotoFace?> onSelect;
  final ValueChanged<Person> onOpen;

  @override
  State<PhotoFacesLayer> createState() => _PhotoFacesLayerState();
}

class _PhotoFacesLayerState extends State<PhotoFacesLayer> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 7000));
  /// Kept at its own pace with the phone's animations off: it is also how long "Tap a face to see who" stays up.
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
    animationBehavior: AnimationBehavior.preserve,
  );

  /// What is drawn: kept while the ring animates out after a deselect.
  PhotoFace? _shown;

  final math.Random _rng = math.Random();
  _Roll _selRoll = _Roll(math.Random());
  /// Whether the outline arrived from a flight, so there is nothing to draw in.
  bool _ringSettled = false;
  List<_Roll> _hintRolls = const [];

  /// Starts the hint and the ring. A layer shown with a face already picked, for example from the video's people
  /// strip, draws round that head at once with no hint first. Once the photo has settled, the faces are faintly traced
  /// and each gets a small sparkle, the sign that it can be tapped, and a line says what it means. It is different
  /// every time and gone again within a few seconds. The ring starts turning in didChangeDependencies, where the
  /// motion setting can be read.
  @override
  void initState() {
    super.initState();
    final initial = widget.selected;
    if (initial != null) {
      _shown = initial;
      if (widget.entry != null) {
        _selRoll = _Roll.fixed(widget.entry!);
        _ringSettled = true;
      }
      _hint.value = 1;
      _enter.forward();
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || widget.selected != null) return;
      _hintRolls = List.generate(widget.faces.length, (_) => _Roll(_rng));
      _hint.forward();
    });
  }

  /// Reacts to a change of the picked face. The same face with refreshed details, such as a rename, is updated in
  /// place with no fresh animation. A face picked from outside with a flight landing on it uses the flight's own band
  /// as its outline. The hint ripple is done once a face has been found.
  @override
  void didUpdateWidget(covariant PhotoFacesLayer old) {
    super.didUpdateWidget(old);
    final now = widget.selected;
    if (identical(now, old.selected)) return;
    if (now != null && old.selected != null && now.faceId == old.selected!.faceId) {
      _shown = now;
      return;
    }
    if (now != null) {
      _shown = now;
      final entry = widget.entry;
      if (entry != null && old.selected == null) {
        _selRoll = _Roll.fixed(entry);
        _ringSettled = true;
      } else {
        _ringSettled = false;
        _selRoll = _Roll(_rng);
      }
      _hint.stop();
      _hint.value = 1;
      _enter.forward(from: 0);
      if (!_spin.isAnimating && !calm(context)) _spin.repeat();
    } else {
      _enter.reverse().whenComplete(() {
        if (!mounted || widget.selected != null) return;
        _spin.stop();
        setState(() => _shown = null);
      });
    }
  }

  /// With motion off the ring round the picked face stays still.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (calm(context)) {
      _spin
        ..stop()
        ..value = 0;
    } else if (widget.selected != null && !_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _spin.dispose();
    _hint.dispose();
    super.dispose();
  }

  /// The latest details of a person (a rename made elsewhere shows at once): the
  /// Faces list is kept up to date; someone not listed there keeps what was looked up.
  Person _live(Person p) {
    final faces = Get.find<FacesController>();
    for (final listed in faces.people) {
      if (listed.id == p.id) return listed;
    }
    return p;
  }

  /// Where a face sits on screen. The photo is shown contain-fitted inside the viewer, and the circle is round the
  /// whole head rather than the face box, a little bigger and a little higher.
  _Head? _headOf(PhotoFace f, Size size) {
    if (f.photoW <= 0 || f.photoH <= 0) return null;

    final aspect = f.photoW / f.photoH;
    final double w, h;
    if (size.width / size.height > aspect) {
      h = size.height;
      w = h * aspect;
    } else {
      w = size.width;
      h = w / aspect;
    }
    final origin = Offset((size.width - w) / 2, (size.height - h) / 2);

    final faceW = (f.right - f.left) * w;
    final faceH = (f.bottom - f.top) * h;
    final scene = origin + Offset((f.left + f.right) / 2 * w, (f.top + f.bottom) / 2 * h - faceH * 0.06);
    final sceneRadius = math.max(faceW, faceH) * 0.5 * 1.4;

    final m = widget.transform.value;
    return _Head(MatrixUtils.transformPoint(m, scene), sceneRadius * m.getMaxScaleOnAxis());
  }

  /// Where every face is.
  Map<PhotoFace, _Head> _headsFor(Size size) {
    final heads = <PhotoFace, _Head>{};
    for (final f in widget.faces) {
      final head = _headOf(f, size);
      if (head != null) heads[f] = head;
    }
    return heads;
  }

  /// The things that animate every frame, the hint and the ring, are painted by painters that repaint themselves, so
  /// the widgets around them are not rebuilt per frame. That matters in a big group photo, where rebuilding dozens of
  /// tap targets sixty times a second made the moment the outlines appear stutter. With motion off there are no
  /// sparkles. The tap targets are at least a fingertip wide and only move with the photo. Positioned widgets must sit
  /// directly in a Stack, hence the fill and the inner Stack.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final shown = _shown;

        return Stack(
          fit: StackFit.expand,
          children: [
            if (widget.selected == null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _LivePainter(
                    repaint: Listenable.merge([_hint, widget.transform]),
                    draw: (canvas, size) {
                      if (!_hint.isAnimating || calm(context)) return;
                      _HintPainter(_headsFor(size).values.toList(), _hintRolls, _hint.value).paint(canvas, size);
                    },
                  ),
                ),
              ),

            if (shown != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _LivePainter(
                    repaint: Listenable.merge([_enter, _spin, widget.transform]),
                    draw: (canvas, size) {
                      final head = _headOf(shown, size);
                      if (head == null) return;
                      _RingPainter(
                        center: head.center,
                        radius: head.radius,
                        progress: _enter.value,
                        spin: _spin.value * 2 * math.pi,
                        roll: _selRoll,
                        settled: _ringSettled,
                      ).paint(canvas, size);
                    },
                  ),
                ),
              ),

            AnimatedBuilder(
              animation: widget.transform,
              builder: (context, _) {
                final heads = _headsFor(size);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final entry in heads.entries)
                      Positioned(
                        left: entry.value.center.dx - math.max(entry.value.radius, 26),
                        top: entry.value.center.dy - math.max(entry.value.radius, 26),
                        width: math.max(entry.value.radius, 26) * 2,
                        height: math.max(entry.value.radius, 26) * 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (identical(widget.selected, entry.key)) {
                              widget.onOpen(_live(entry.key.person));
                            } else {
                              HapticFeedback.selectionClick();
                              widget.onSelect(entry.key);
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),

            if (widget.selected == null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _hint,
                  builder: (context, _) => Stack(children: [_captionPill()]),
                ),
              ),

            if (shown != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_enter, widget.transform]),
                  builder: (context, _) {
                    final head = _headOf(shown, size);
                    return Stack(children: [if (head != null) _chip(shown, head, size)]);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// "Tap a face to see who": fades in and out with the hint, low on the screen, in the
  /// same frosted glass as the viewer's other floating controls.
  /// With motion off it is simply there for the same while, with no fading or rising.
  Widget _captionPill() {
    final p = _hint.value;
    final opacity = calm(context)
        ? (p > 0.08 && p < 0.95 ? 1.0 : 0.0)
        : (Interval(0.08, 0.22).transform(p) * (1 - Interval(0.78, 0.95).transform(p))).clamp(0.0, 1.0);
    if (opacity <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xxl + widget.bottomInset,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, AppSpacing.xs * (1 - opacity)),
              child: const _FlowText(
                'Tap a face to see who',
                leading: Icon(Icons.face_outlined, size: 20, color: FacePalette.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The person's picture and name, under the head (above it near the bottom).
  /// Centred under the head, but never off the screen.
  Widget _chip(PhotoFace face, _Head head, Size size) {
    const chipHeight = 64.0;
    var y = head.center.dy + head.radius + 14;
    if (y + chipHeight > size.height - 28) y = head.center.dy - head.radius - 14 - chipHeight;
    y = y.clamp(76.0, math.max(76.0, size.height - chipHeight - 28));

    final x = (head.center.dx / size.width * 2 - 1).clamp(-1.0, 1.0);

    final t = Curves.easeOutBack.transform(Interval(0.3, 1.0).transform(_enter.value));
    final opacity = Interval(0.3, 0.75, curve: Curves.easeOut).transform(_enter.value);

    return Positioned(
      left: 12,
      right: 12,
      top: y,
      child: Align(
        alignment: Alignment(x, -1),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            alignment: Alignment.topCenter,
            child: GetBuilder<FacesController>(
              builder: (_) {
                final person = _live(face.person);
                return _PersonChip(person: person, onTap: () => widget.onOpen(person));
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints whatever [draw] does, and repaints whenever [repaint] fires, so an animation can redraw every frame without
/// its widget tree being rebuilt.
class _LivePainter extends CustomPainter {
  _LivePainter({required Listenable repaint, required this.draw}) : super(repaint: repaint);

  final void Function(Canvas canvas, Size size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(covariant _LivePainter old) => true;
}
