import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

/// Which of the person page's actions a [PersonDemo] shows.
enum PersonDemoKind { together, merge, separate, check, hide, save }

/// A picture in a demo: one of the app's face crops, a photo's thumbnail, or one of the tour's demo
/// pictures (when the library hasn't got enough of its own).
class DemoPic {
  const DemoPic.face(int this.faceId) : bytes = null, asset = null;
  const DemoPic.bytes(Uint8List this.bytes) : faceId = null, asset = null;
  const DemoPic.asset(String this.asset) : faceId = null, bytes = null;

  final int? faceId;
  final Uint8List? bytes;
  final String? asset;

  Widget build(double size, {bool round = true}) {
    final id = faceId;
    if (id != null) return FaceAvatar(faceId: id, size: size, square: !round, radius: 8);
    final picture = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        : Image.asset(asset!, fit: BoxFit.cover);
    return SizedBox(
      width: size,
      height: size,
      child: round ? ClipOval(child: picture) : ClipRRect(borderRadius: BorderRadius.circular(8), child: picture),
    );
  }
}

/// Who and what a demo is made of: the person themselves (a few of their faces and their name),
/// other people (to pick, to mix up with, to sit beside), and some of the person's photos.
class DemoCast {
  const DemoCast({
    required this.me,
    required this.name,
    required this.photoCount,
    required this.others,
    required this.photos,
  });

  /// At least one of the person's faces; more makes the grids look like the real thing.
  final List<DemoPic> me;
  final String? name;
  final int photoCount;

  /// At least four other people, each with a name ('' for someone unnamed).
  final List<(DemoPic, String)> others;

  /// At least six of the person's photos.
  final List<DemoPic> photos;

  DemoPic mine(int i) => me[i % me.length];
}

/// A short looping film of what one action on the person page does, played with the person's own
/// faces and photos inside the bubble that asks about it. One clock runs each film, so every move in
/// it is worked out from the same moment and nothing can drift or stutter.
class PersonDemo extends StatefulWidget {
  const PersonDemo({super.key, required this.kind, required this.cast});

  final PersonDemoKind kind;
  final DemoCast cast;

  static const double height = 150;

  @override
  State<PersonDemo> createState() => _PersonDemoState();
}

class _PersonDemoState extends State<PersonDemo> with SingleTickerProviderStateMixin {
  // How long each film runs before it starts again (it fades out and back in at the join).
  static const Map<PersonDemoKind, int> _lengths = {
    PersonDemoKind.together: 5800,
    PersonDemoKind.merge: 5400,
    PersonDemoKind.separate: 6000,
    PersonDemoKind.check: 5600,
    PersonDemoKind.hide: 5400,
    PersonDemoKind.save: 5600,
  };

  // Where each film comes to rest, shown still when animations are turned off.
  static const Map<PersonDemoKind, int> _restAt = {
    PersonDemoKind.together: 4600,
    PersonDemoKind.merge: 4400,
    PersonDemoKind.separate: 5000,
    PersonDemoKind.check: 4600,
    PersonDemoKind.hide: 4400,
    PersonDemoKind.save: 4600,
  };

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _lengths[widget.kind]!),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.stop();
      _clock.value = _restAt[widget.kind]! / _lengths[widget.kind]!;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final length = _lengths[widget.kind]!.toDouble();
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: PersonDemo.height,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.dividerSoft),
          ),
          child: LayoutBuilder(
            builder: (context, box) => AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final ms = _clock.value * length;
                // Fades in at the start of each round and out at its end, so the join never jumps.
                final round = still ? 1.0 : math.min(_t(ms, 0, 260), 1 - _t(ms, length - 300, length));
                final s = _Scene(ms, box.maxWidth, widget.cast);
                return Opacity(
                  opacity: round.clamp(0.0, 1.0),
                  child: Stack(clipBehavior: Clip.hardEdge, children: _film(s)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _film(_Scene s) => switch (widget.kind) {
    PersonDemoKind.together => s.together(),
    PersonDemoKind.merge => s.merge(),
    PersonDemoKind.separate => s.separate(),
    PersonDemoKind.check => s.check(),
    PersonDemoKind.hide => s.hide(),
    PersonDemoKind.save => s.save(),
  };
}

// How far along [from]..[to] (in ms) the moment [ms] is, 0 to 1, eased by [curve].
double _t(double ms, double from, double to, [Curve curve = Curves.linear]) =>
    curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

double _lerp(double a, double b, double t) => a + (b - a) * t;

// A gentle spring: overshoots a little and settles.
const Curve _spring = Curves.easeOutBack;
const Curve _glide = Curves.easeInOutCubic;
const Curve _out = Curves.easeOutCubic;

const _label = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.2);
const _sub = TextStyle(fontSize: 10, color: AppColors.ink48, height: 1.2);

/// One frame of a film: what is where at moment [ms] on a stage [w] wide.
class _Scene {
  _Scene(this.ms, this.w, this.cast);

  final double ms;
  final double w;
  final DemoCast cast;

  double get cx => w / 2;
  String get who => cast.name ?? 'This person';

  double t(double from, double to, [Curve curve = Curves.linear]) => _t(ms, from, to, curve);

  // Something on the stage by its top-left corner; skipped while invisible. [id] keeps each thing the
  // same widget from frame to frame (so a face never reloads mid-move).
  Widget? at(
    String id,
    double x,
    double y,
    double width,
    double height,
    Widget child, {
    double opacity = 1,
    double scale = 1,
    double turn = 0,
    Alignment origin = Alignment.center,
  }) {
    if (opacity <= 0.004) return null;
    return Positioned(
      key: ValueKey(id),
      left: x,
      top: y,
      width: width,
      height: height,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: turn,
          child: Transform.scale(scale: scale, alignment: origin, child: child),
        ),
      ),
    );
  }

  // Comes in: from a little smaller and transparent to itself, with a small overshoot.
  (double, double) appear(double from, [double length = 360]) {
    final p = t(from, from + length);
    return (Curves.easeOut.transform(p), _lerp(0.8, 1, _spring.transform(p)));
  }

  Widget face(DemoPic pic, double size, {Color? ring}) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: ring ?? AppColors.canvas, spreadRadius: ring == null ? 2 : 2.5),
        BoxShadow(color: AppColors.ink.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2)),
      ],
    ),
    child: pic.build(size),
  );

  Widget text(String s, TextStyle style) =>
      Text(s, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

  Widget chip(String s, {Color color = AppColors.primary}) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Text(s, maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
    ),
  );

  // A finger tap at (x, y), starting at [from]: a ring lands and widens away.
  Widget? tap(String id, double x, double y, double from) {
    final land = t(from, from + 260, _out);
    final leave = t(from + 260, from + 640, _out);
    if (land <= 0 || leave >= 1) return null;
    final size = 26 * (leave > 0 ? 1 + 0.9 * leave : 1.6 - 0.6 * land);
    return at(
      id,
      x - size / 2,
      y - size / 2,
      size,
      size,
      DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
        ),
      ),
      opacity: leave > 0 ? 1 - leave : land,
    );
  }

  List<Widget> keep(List<Widget?> parts) => [for (final p in parts) if (p != null) p];

  // ---- With someone: the person, an empty place, people to pick; one is picked and flies in, and
  // the photos they're both in rise up. ----
  List<Widget> together() {
    final parts = <Widget?>[];
    final picked = 2;
    // The person and the empty place beside them, until the pair turns into a small heading.
    final pairOut = t(2700, 3050, _out);
    final (meIn, meScale) = appear(0);
    parts.add(at('me', cx - 52, 14, 44, 44, face(cast.mine(0), 44),
        opacity: meIn * (1 - pairOut), scale: meScale * (1 - 0.3 * pairOut)));
    final (slotIn, slotScale) = appear(80);
    final slotGone = t(1900, 2100);
    parts.add(at('slot', cx + 8, 14, 44, 44, CustomPaint(painter: _DashedCircle()),
        opacity: slotIn * (1 - slotGone), scale: slotScale));
    parts.add(at('plus', cx + 8, 14, 44, 44, const Icon(Icons.add_rounded, size: 18, color: Color(0xFF9DB3AD)),
        opacity: slotIn * (1 - slotGone)));
    // The people to pick from.
    final step = math.min(56.0, (w - 24) / 4);
    for (var i = 0; i < 4; i++) {
      final (pic, name) = cast.others[i];
      final x = cx - step * 2 + i * step + (step - 36) / 2;
      final (inP, inS) = appear(180 + i * 70.0);
      final leave = i == picked ? 0.0 : t(1900, 2150);
      if (i == picked) {
        // Flies up into the empty place, growing to match the person.
        final fly = t(1950, 2500, _glide);
        final grow = _spring.transform(t(1950, 2500));
        final fx = _lerp(x, cx + 8, fly), fy = _lerp(86, 14, fly) - 14 * math.sin(math.pi * fly);
        final size = _lerp(36, 44, grow);
        parts.add(at('o$i', fx, fy, size, size, face(pic, size),
            opacity: inP * (1 - pairOut), scale: inS * (1 - 0.3 * pairOut)));
      } else {
        parts.add(at('o$i', x, 86, 36, 36, face(pic, 36), opacity: inP * (1 - leave), scale: inS * (1 - 0.2 * leave)));
      }
      if (name.isNotEmpty) {
        parts.add(at('n$i', x - 10, 126, 56, 14, text(name, _sub), opacity: inP * (1 - (i == picked ? t(1900, 2050) : leave))));
      }
    }
    parts.add(tap('tap', cx - step * 2 + picked * step + step / 2, 104, 1300));
    // The pair as a small heading, and the photos they're both in.
    final (hIn, hS) = appear(2950, 320);
    parts.add(at('ha', cx - 92, 14, 26, 26, face(cast.mine(0), 26), opacity: hIn, scale: hS));
    parts.add(at('hb', cx - 72, 14, 26, 26, face(cast.others[picked].$1, 26), opacity: hIn, scale: hS));
    parts.add(at('chip', cx - 46, 17, 124, 22, chip('Photos with both'), opacity: t(3050, 3350, _out)));
    final tile = math.min(80.0, (w - 40) / 3);
    final gap = 8.0;
    final left = cx - (tile * 3 + gap * 2) / 2;
    for (var i = 0; i < 3; i++) {
      final p = t(3150 + i * 110.0, 3630 + i * 110.0);
      final x = left + i * (tile + gap);
      parts.add(at('p$i', x, 52 + 26 * (1 - _out.transform(p)), tile, tile, cast.photos[i].build(tile, round: false),
          opacity: Curves.easeOut.transform(p), scale: _lerp(0.9, 1, _spring.transform(p))));
      final (fIn, fS) = appear(3500 + i * 110.0, 300);
      parts.add(at('pa$i', x + 5, 52 + tile - 23, 18, 18, face(cast.mine(0), 18), opacity: fIn, scale: fS));
      parts.add(at('pb$i', x + 19, 52 + tile - 23, 18, 18, face(cast.others[picked].$1, 18), opacity: fIn, scale: fS));
    }
    return keep(parts);
  }

  // ---- Same person: the person and an unnamed copy of them; the copy slides in and is taken up,
  // and the number of photos adds up. ----
  List<Widget> merge() {
    final parts = <Widget?>[];
    // The person's real count, and a smaller, made-up one for the copy.
    final countA = math.max(cast.photoCount, 1);
    final extra = (countA * 0.12).round().clamp(3, 40);
    final slide = t(2000, 2650, _glide);
    final (aIn, aS) = appear(0);
    final (bIn, bS) = appear(120);
    // The person: swells as the copy runs into them, then moves to the middle.
    final swell = math.sin(math.pi * t(2300, 2900)) * 0.16;
    final move = t(2000, 2700, _glide);
    final ax = cx - 96 + 64 * move;
    parts.add(at('a', ax, 18, 64, 64, face(cast.mine(0), 64), opacity: aIn, scale: aS * (1 + swell)));
    parts.add(at('al', ax - 16, 88, 96, 14, text(who, _label), opacity: aIn));
    final counted = (countA + extra * t(2600, 3500, _out)).round();
    parts.add(at('ac', ax - 16, 104, 96, 13, text('${ms < 2600 ? countA : counted} photos', _sub), opacity: aIn));
    // The copy.
    final bx = cx + 32 - 128 * slide;
    final bFade = t(2450, 2650);
    // Drawn first, so it slides in under the person rather than over them.
    parts.insert(0, at('b', bx, 18, 64, 64, face(cast.mine(1), 64), opacity: bIn * (1 - bFade), scale: bS * _lerp(1, 0.6, slide)));
    final bLabels = 1 - t(1900, 2150);
    parts.add(at('bl', cx + 16, 88, 96, 14, text('Unnamed', _sub.copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
        opacity: bIn * bLabels));
    parts.add(at('bc', cx + 16, 104, 96, 13, text('$extra photos', _sub), opacity: bIn * bLabels));
    // "same person", then "one person now".
    final same = t(1000, 1300, _out) * (1 - t(1850, 2050));
    // Under the two, where "one person now" comes later.
    parts.add(at('same', cx - 60, 124 + 6 * (1 - t(1000, 1300, _out)), 120, 22, chip('same person?'), opacity: same));
    final (dIn, dS) = appear(3500, 320);
    parts.add(at('done', cx - 60, 124, 120, 22, chip('one person now'), opacity: dIn, scale: dS));
    return keep(parts);
  }

  // ---- Two people: the person's faces turn out to be two people; they sort into two groups, and
  // each group becomes its own person. ----
  List<Widget> separate() {
    final parts = <Widget?>[];
    const isMine = [true, false, true, true, false, true, false, true];
    const d = 34.0, gap = 8.0;
    final startX = cx - (4 * d + 3 * gap) / 2;
    parts.add(at('head', 0, 6, w, 14, text('$who · 8 faces', _label), opacity: t(0, 300) * (1 - t(1500, 1700))));
    final other = cast.others[0].$1;
    var mi = 0, oi = 0;
    final gather = t(3000, 3450, _glide);
    for (var i = 0; i < 8; i++) {
      final mine = isMine[i];
      final n = mine ? mi++ : oi++;
      final x0 = startX + (i % 4) * (d + gap), y0 = 28 + (i ~/ 4) * (d + gap);
      // Sorted: the person's faces to the left, the other person's to the right.
      final x1 = (mine ? cx - 116 : cx + 30) + (n % 3) * 30, y1 = 32.0 + (n ~/ 3) * 30;
      final sort = _spring.transform(t(1500 + n * 40.0, 2120 + n * 40.0));
      // Gathered into one face per group.
      final x2 = mine ? cx - 92 : cx + 44, y2 = 38.0;
      final x = _lerp(_lerp(x0, x1, sort), x2, gather);
      final y = _lerp(_lerp(y0, y1, sort), y2, gather);
      final (inP, inS) = appear(60.0 * i, 300);
      parts.add(at('f$i', x, y, d, d, face(mine ? cast.mine(n) : other, d),
          opacity: inP * (1 - gather), scale: inS * _lerp(1, 0.8, sort) * _lerp(1, 0.6, gather)));
    }
    final line = t(2300, 2650, _out) * (1 - t(3000, 3300));
    parts.add(at('line', cx + 3, 28, 2, 74 * t(2300, 2650, _out), const ColoredBox(color: Color(0xFFB9C9C4)), opacity: line));
    final (aIn, aS) = appear(3350, 400);
    final (bIn, bS) = appear(3430, 400);
    parts.add(at('A', cx - 104, 24, 58, 58, face(cast.mine(0), 58), opacity: aIn, scale: aS));
    parts.add(at('B', cx + 42, 24, 58, 58, face(other, 58), opacity: bIn, scale: bS));
    parts.add(at('Al', cx - 123, 90, 96, 14, text(who, _label), opacity: t(3500, 3800)));
    parts.add(at('Bl', cx + 23, 90, 96, 14, text('New person', _label), opacity: t(3580, 3880)));
    parts.add(at('Ac', cx - 123, 106, 96, 13, text('5 faces', _sub), opacity: t(3600, 3900)));
    parts.add(at('Bc', cx + 23, 106, 96, 13, text('3 faces', _sub), opacity: t(3660, 3960)));
    return keep(parts);
  }

  // ---- Wrong faces: every face counted as the person, with one that isn't; it is tapped, marked,
  // lifted out, and the faces after it close the gap. ----
  List<Widget> check() {
    final parts = <Widget?>[];
    const cols = 5, count = 10, odd = 6;
    const gap = 9.0;
    final d = math.min(38.0, (w - 24 - gap * (cols - 1)) / cols);
    final startX = cx - (cols * d + (cols - 1) * gap) / 2;
    Offset pos(int i) => Offset(startX + (i % cols) * (d + gap), 22 + (i ~/ cols) * (d + gap));
    parts.add(at('head', 0, 4, w, 13, text('Every face counted as ${cast.name ?? 'this person'}', _sub), opacity: t(0, 300)));
    final lift = t(2350, 2800, _glide);
    for (var i = 0; i < count; i++) {
      final (inP, inS) = appear(50.0 * i, 300);
      var p = pos(i);
      if (i > odd) {
        final shift = _spring.transform(t(2700 + (i - odd - 1) * 50.0, 3200 + (i - odd - 1) * 50.0));
        p = Offset.lerp(p, pos(i - 1), shift)!;
      }
      final isOdd = i == odd;
      final marked = isOdd && ms > 1750;
      final pic = isOdd ? cast.others[1].$1 : cast.mine(i);
      parts.add(at('f$i', p.dx, p.dy - (isOdd ? 30 * lift : 0), d, d,
          face(pic, d, ring: marked ? AppColors.danger : null),
          opacity: inP * (isOdd ? 1 - lift : 1), scale: inS * (isOdd ? _lerp(1, 0.6, lift) : 1)));
    }
    final o = pos(odd);
    parts.add(tap('tap', o.dx + d / 2, o.dy + d / 2, 1300));
    final (mIn, mS) = appear(1750, 260);
    parts.add(at('minus', o.dx + d - 12, o.dy - 6 - 26 * lift, 18, 18,
        Container(
          decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.remove_rounded, size: 14, color: AppColors.onPrimary),
        ),
        opacity: mIn * (1 - lift), scale: mS));
    final (dIn, dS) = appear(3300, 320);
    parts.add(at('done', cx - 60, 122, 120, 22, chip('1 face taken out'), opacity: dIn, scale: dS));
    return keep(parts);
  }

  // ---- Hide: the Faces tab's row of people; the person lifts, drops into Hidden people, and the
  // row closes up behind them. ----
  List<Widget> hide() {
    final parts = <Widget?>[];
    const d = 46.0;
    final step = math.min(62.0, (w - 24) / 4);
    final startX = cx - (3 * step + d) / 2;
    final row = [cast.others[0], cast.others[1], (cast.mine(0), cast.name ?? ''), cast.others[2]];
    final drawerX = cx - 78, drawerY = 104.0;
    final close = _spring.transform(t(2300, 2800));
    // The drawer first, so the person dropping into it is drawn over it.
    final (drIn, drS) = appear(1450, 320);
    parts.add(at('drawer', drawerX, drawerY, 156, 30,
        Container(
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.only(left: 32, right: 10),
          child: const Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 13, color: AppColors.ink48),
              SizedBox(width: 6),
              Text('Hidden people', style: TextStyle(fontSize: 11, color: AppColors.ink80)),
            ],
          ),
        ),
        opacity: drIn, scale: drS));
    for (var i = 0; i < 4; i++) {
      final (pic, name) = row[i];
      final (inP, inS) = appear(60.0 * i, 300);
      var x = startX + i * step;
      if (i == 3) x -= step * close;
      if (i == 2) {
        // Lifts as if picked, then drops into the drawer's empty place with a small hop.
        final pick = math.sin(math.pi * 0.5 * t(1200, 1450, _out)) * 0.12;
        final drop = t(1800, 2450, _glide);
        final tx = _lerp(x, drawerX + 6, drop), ty = _lerp(10, drawerY + 5 - (d - 20) / 2, drop);
        final hop = -18 * math.sin(math.pi * drop);
        parts.add(at('f$i', tx, ty + hop, d, d, face(pic, d),
            scale: inS * (1 + pick * (1 - drop)) * _lerp(1, 20 / d, drop), opacity: inP,
            origin: drop > 0 ? Alignment.topLeft : Alignment.center));
        parts.add(at('n$i', x - 10, 60, d + 20, 14, text(name, _sub.copyWith(color: AppColors.ink80)),
            opacity: inP * (1 - t(1800, 2000))));
      } else {
        parts.add(at('f$i', x, 10, d, d, face(pic, d), opacity: inP, scale: inS));
        parts.add(at('n$i', x - 10, 60, d + 20, 14, text(name, _sub.copyWith(color: AppColors.ink80)), opacity: inP));
      }
    }
    parts.add(at('note', 0, 138, w, 12,
        text('Bring ${cast.name ?? 'them'} back anytime from Settings', _sub.copyWith(fontSize: 9.5)),
        opacity: t(2700, 3000)));
    return keep(parts);
  }

  // ---- Save all: the person's photos fly one by one into a zip file, which counts up its size. ----
  List<Widget> save() {
    final parts = <Widget?>[];
    const d = 46.0, gap = 6.0;
    final gridX = cx - 128.0;
    final zipX = cx + 52, zipY = 28.0;
    var mb = 0.0;
    for (var i = 0; i < 6; i++) {
      final x = gridX + (i % 3) * (d + gap), y = 16 + (i ~/ 3) * (d + gap);
      final (inP, inS) = appear(50.0 * i, 300);
      final start = 1300 + 280.0 * i;
      final fly = t(start, start + 560, Curves.easeInOutCubic);
      final tx = zipX + 32 - d / 2, ty = zipY + 34 - d / 2;
      final fx = _lerp(x, tx, fly), fy = _lerp(y, ty, fly) - 26 * math.sin(math.pi * fly);
      parts.add(at('p$i', fx, fy, d, d, cast.photos[i].build(d, round: false),
          opacity: inP * (1 - t(start + 380, start + 560)),
          scale: inS * _lerp(1, 0.2, fly), turn: (i.isEven ? -0.14 : 0.14) * math.sin(math.pi * fly)));
      mb += 8 * t(start + 420, start + 640, _out);
    }
    // The zip, which gives a little bump as each photo lands in it.
    var bump = 0.0;
    for (var i = 0; i < 6; i++) {
      final land = 1300 + 280.0 * i + 420;
      bump = math.max(bump, math.sin(math.pi * t(land, land + 220)) * 0.08);
    }
    final (zIn, zS) = appear(900, 360);
    final saved = t(3400, 3700, _out);
    parts.add(at('zip', zipX, zipY, 64, 76,
        _Zip(name: '${cast.name ?? 'Photos'}.zip', size: '${mb.round()} MB', done: saved),
        opacity: zIn, scale: zS * (1 + bump)));
    final (sIn, sS) = appear(3400, 320);
    parts.add(at('saved', zipX - 18, 114, 100, 22, chip('Saved'), opacity: sIn, scale: sS));
    return keep(parts);
  }
}

class _Zip extends StatelessWidget {
  const _Zip({required this.name, required this.size, required this.done});

  final String name;
  final String size;
  final double done;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Stack(
        children: [
          // The zip's teeth down the middle, turning into a tick once it's done.
          Positioned(
            left: 29,
            top: 0,
            width: 6,
            height: 34,
            child: Opacity(opacity: 1 - done, child: const CustomPaint(painter: _Teeth())),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: Opacity(
              opacity: done,
              child: Transform.scale(
                scale: 0.6 + 0.4 * Curves.easeOutBack.transform(done),
                child: const Icon(Icons.check_rounded, size: 22, color: AppColors.onPrimary),
              ),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.onPrimary)),
                Text(size, maxLines: 1,
                    style: TextStyle(fontSize: 9, color: AppColors.onPrimary.withValues(alpha: 0.85),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Teeth extends CustomPainter {
  const _Teeth();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.onPrimary.withValues(alpha: 0.75);
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Teeth old) => false;
}

class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB9C9C4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = size.width / 2 - 1;
    const dashes = 14;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), a, math.pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCircle old) => false;
}
