import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';
import 'package:lost_and_found/view/widget/photo_faces_layer.dart';

/// One face in the demo's picture: where it is (as shares of the picture's width and height) and who it is.
class _DemoFace {
  const _DemoFace(this.rect, this.name, this.photos, this.avatar);

  final Rect rect;

  /// Null for a face that is found but not tapped.
  final String? name;
  final int photos;
  final String? avatar;
}

/// What happens when a photo is opened full screen, on a bundled picture: the faces are traced with their
/// squiggly outlines and a sparkle, "Tap a face to see who" shows, then a face is tapped: the photo dims round the
/// head, the outline draws itself and keeps turning, and the person's chip pops up; then the next named face is tapped.
/// Drawn by the same code as the real viewer (see [FaceOutlineDemo]); it only shows, nothing here can be touched.
/// Plays while its page shows.
class TourFaceDemo extends StatefulWidget {
  const TourFaceDemo({super.key, required this.active});

  final bool active;

  @override
  State<TourFaceDemo> createState() => _TourFaceDemoState();
}

class _TourFaceDemoState extends State<TourFaceDemo>
    with TickerProviderStateMixin {
  static const String _photo = 'assets/tour/photos/supercup.jpg';
  static const Size _photoSize = Size(900, 601);

  // Every face the viewer finds in the picture (all of them are traced), left to right. Only the ones with a
  // name are tapped, in this order: Messi, then Suárez. Iniesta, soft behind them, is found but left alone.
  static const List<_DemoFace> _faces = [
    _DemoFace(Rect.fromLTRB(0.159, 0.233, 0.206, 0.316), null, 0, null),
    _DemoFace(
      Rect.fromLTRB(0.302, 0.092, 0.361, 0.213),
      'Suárez',
      9,
      'assets/tour/faces/suarez.jpg',
    ),
    _DemoFace(
      Rect.fromLTRB(0.556, 0.100, 0.620, 0.250),
      'Messi',
      7,
      'assets/tour/faces/messi.jpg',
    ),
  ];

  // The order the taps go in (positions in [_faces]).
  static const List<int> _taps = [2, 1];

  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7000),
  );
  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  int _generation = 0;
  bool _selected = false;

  // Which face is tapped (or was last).
  int _current = 2;

  // When the phone asks for no animations the demo is one still picture (Messi picked), not a loop.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still != _still || !_started) {
      _still = still;
      _started = true;
      _sync();
    }
  }

  bool _started = false;

  @override
  void didUpdateWidget(covariant TourFaceDemo old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  void _sync() {
    _generation++;
    if (_still) {
      _reset();
      _selected = true;
      _open.value = 1;
      _enter.value = 1;
    } else if (widget.active) {
      unawaited(_loop(_generation));
    } else {
      _reset();
    }
  }

  void _reset() {
    _selected = false;
    _current = _taps.first;
    _open.value = 0;
    _hint.value = 0;
    _enter.value = 0;
    _tap.value = 0;
    _spin.stop();
  }

  bool _stale(int generation) => !mounted || generation != _generation;

  Future<void> _wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _loop(int generation) async {
    while (!_stale(generation)) {
      setState(_reset);
      // The photo opens.
      await _wait(500);
      if (_stale(generation)) return;
      unawaited(_open.forward(from: 0));
      await _wait(900);
      if (_stale(generation)) return;
      // The faces are traced.
      unawaited(_hint.forward(from: 0));
      await _wait(3300);
      if (_stale(generation)) return;
      // Each face in turn is tapped, shown, and let go.
      for (var k = 0; k < _taps.length; k++) {
        setState(() => _current = _taps[k]);
        unawaited(_tap.forward(from: 0));
        await _wait(260);
        if (_stale(generation)) return;
        setState(() => _selected = true);
        unawaited(_enter.forward(from: 0));
        if (!_spin.isAnimating) _spin.repeat();
        await _wait(2900);
        if (_stale(generation)) return;
        setState(() => _selected = false);
        await _enter.reverse();
        if (_stale(generation)) return;
        await _wait(k == _taps.length - 1 ? 700 : 350);
      }
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _generation++;
    _open.dispose();
    _hint.dispose();
    _enter.dispose();
    _spin.dispose();
    _tap.dispose();
    super.dispose();
  }

  // Where the picture sits, "contain"-fitted in [size] (as the viewer shows a photo), and so where a head is: round
  // the whole head, a little bigger and higher than the face box, as the viewer works it out.
  HeadSpot _head(Size size, _DemoFace face) {
    final aspect = _photoSize.width / _photoSize.height;
    final double w, h;
    if (size.width / size.height > aspect) {
      h = size.height;
      w = h * aspect;
    } else {
      w = size.width;
      h = w / aspect;
    }
    final origin = Offset((size.width - w) / 2, (size.height - h) / 2);
    final r = face.rect;
    final faceW = r.width * w;
    final faceH = r.height * h;
    final centre =
        origin +
        Offset(
          (r.left + r.right) / 2 * w,
          (r.top + r.bottom) / 2 * h - faceH * 0.06,
        );
    return HeadSpot(centre, math.max(faceW, faceH) * 0.5 * 1.4);
  }

  @override
  Widget build(BuildContext context) {
    // One line for a screen reader instead of the chips and labels coming and going.
    return Semantics(
      label:
          'Demo: a photo is opened, the faces in it are outlined, and tapping one shows who it is',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: FixedTextScale(
            child: AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: ColoredBox(
                  color: TourPalette.black,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = box.biggest;
                      final heads = [for (final f in _faces) _head(size, f)];
                      final head = heads[_current];
                      final face = _faces[_current];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedBuilder(
                            animation: _open,
                            builder: (context, child) {
                              final t = Curves.easeOutCubic.transform(
                                _open.value,
                              );
                              return Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.9 + 0.1 * t,
                                  child: child,
                                ),
                              );
                            },
                            child: Image.asset(_photo, fit: BoxFit.contain),
                          ),
                          // The hint: every face traced, with a sparkle.
                          CustomPaint(
                            painter: _Live(
                              repaint: _hint,
                              draw: (canvas, size) {
                                if (_selected || !_hint.isAnimating) return;
                                FaceOutlineDemo.paintHint(
                                  canvas,
                                  size,
                                  heads,
                                  _hint.value,
                                );
                              },
                            ),
                          ),
                          // The tapped head: dimmed photo and the turning outline.
                          CustomPaint(
                            painter: _Live(
                              repaint: Listenable.merge([_enter, _spin]),
                              draw: (canvas, size) {
                                if (_enter.value <= 0) return;
                                FaceOutlineDemo.paintRing(
                                  canvas,
                                  size,
                                  head,
                                  progress: _enter.value,
                                  spin: _spin.value * 2 * math.pi,
                                  seed: 7 + _current * 5,
                                );
                              },
                            ),
                          ),
                          // "Tap a face to see who", fading in and out with the hint.
                          AnimatedBuilder(
                            animation: _hint,
                            builder: (context, _) {
                              final p = _hint.value;
                              final o =
                                  (const Interval(0.08, 0.22).transform(p) *
                                          (1 -
                                              const Interval(
                                                0.78,
                                                0.95,
                                              ).transform(p)))
                                      .clamp(0.0, 1.0);
                              if (o <= 0 || _selected) {
                                return const SizedBox.shrink();
                              }
                              return Positioned(
                                left: 0,
                                right: 0,
                                bottom: 18,
                                child: Center(
                                  child: Opacity(
                                    opacity: o,
                                    child: Transform.translate(
                                      offset: Offset(0, 4 * (1 - o)),
                                      child: const FaceHintLabel(),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // A fingertip landing on the face.
                          AnimatedBuilder(
                            animation: _tap,
                            builder: (context, _) {
                              final t = _tap.value;
                              if (t <= 0 || t >= 1) {
                                return const SizedBox.shrink();
                              }
                              final grow = Curves.easeOut.transform(t);
                              final d = 26 + 30 * grow;
                              return Positioned(
                                left: head.center.dx - d / 2,
                                top: head.center.dy - d / 2,
                                width: d,
                                height: d,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: TourPalette.white.withValues(
                                      alpha: 0.35 * (1 - t),
                                    ),
                                    border: Border.all(
                                      color: TourPalette.white.withValues(
                                        alpha: 0.8 * (1 - t),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // The person's chip, under the head.
                          AnimatedBuilder(
                            animation: _enter,
                            builder: (context, _) {
                              if (_enter.value <= 0) {
                                return const SizedBox.shrink();
                              }
                              const chipHeight = 64.0;
                              var y = head.center.dy + head.radius + 14;
                              if (y + chipHeight > size.height - 14) {
                                y =
                                    head.center.dy -
                                    head.radius -
                                    14 -
                                    chipHeight;
                              }
                              final t = Curves.easeOutBack.transform(
                                const Interval(
                                  0.3,
                                  1.0,
                                ).transform(_enter.value),
                              );
                              final o = const Interval(
                                0.3,
                                0.75,
                                curve: Curves.easeOut,
                              ).transform(_enter.value);
                              return Positioned(
                                left: 12,
                                right: 12,
                                top: y.clamp(
                                  12.0,
                                  size.height - chipHeight - 12,
                                ),
                                child: Align(
                                  // Centred under the head, but never off the edge.
                                  alignment: Alignment(
                                    (head.center.dx / size.width * 2 - 1).clamp(
                                      -1.0,
                                      1.0,
                                    ),
                                    -1,
                                  ),
                                  child: Opacity(
                                    opacity: o,
                                    child: Transform.scale(
                                      scale: 0.7 + 0.3 * t,
                                      alignment: Alignment.topCenter,
                                      child: FaceChipDemo(
                                        face: AssetImage(face.avatar ?? ''),
                                        name: face.name ?? '',
                                        photos: face.photos,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints whatever [draw] does, and repaints whenever [repaint] fires (so an animation redraws without its widgets
/// being rebuilt).
class _Live extends CustomPainter {
  _Live({required Listenable repaint, required this.draw})
    : super(repaint: repaint);

  final void Function(Canvas canvas, Size size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(covariant _Live old) => true;
}
