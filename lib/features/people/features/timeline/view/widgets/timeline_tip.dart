import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/people_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seenKey = 'timeline_tip_seen';

/// Tells the person what the Timeline needs to look good, the first time they open it and never again. The choice is
/// saved as the tip opens, so closing it any way counts as seen. A person who leaves the screen before the tip could
/// open does not use it up. Nothing is shown when the choice cannot be read, so the tip never comes back on every
/// visit.
Future<void> showTimelineTipOnce(BuildContext context) async {
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  unawaited(prefs.setBool(_seenKey, true).catchError((_) => false));
  await showTimelineTip(context);
}

/// Shows the tip, whether it was seen before or not. The button in the Timeline's top bar uses it to bring it back.
Future<void> showTimelineTip(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim.withValues(alpha: 0.45),
    builder: (_) => const _TimelineTipDialog(),
  );
}

/// The tip: a title, a sentence, a small animation of people appearing over the years, and one button. It scrolls
/// when the text is large or the screen is short.
class _TimelineTipDialog extends StatelessWidget {
  const _TimelineTipDialog();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AppColors.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good to know',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This page shows when the people in your photos appeared over the years. '
                'The more photos you have, from more years, the better it looks.',
                style: text.bodyMedium?.copyWith(color: AppColors.ink80, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.base),
              const _DemoBox(),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The animation on its parchment panel. It is a picture, so a screen reader skips it: the text says the same.
class _DemoBox extends StatelessWidget {
  const _DemoBox();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AspectRatio(aspectRatio: _TipPainter.width / _TipPainter.height, child: _TipAnimation()),
        ),
      ),
    );
  }
}

/// Plays the loop. With motion off in the phone's settings it stands still on the finished picture.
class _TipAnimation extends StatefulWidget {
  const _TipAnimation();

  @override
  State<_TipAnimation> createState() => _TipAnimationState();
}

class _TipAnimationState extends State<_TipAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _TipPainter.cycleMs),
    animationBehavior: AnimationBehavior.preserve,
  );
  _TipPainter? _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _painter?.dispose();
    _painter = _TipPainter(clock: _clock, labelStyle: Theme.of(context).textTheme.bodySmall ?? const TextStyle());
    loopUnlessCalm(context, _clock, rest: _TipPainter.restAt);
  }

  @override
  void dispose() {
    _clock.dispose();
    _painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: CustomPaint(painter: _painter));
  }
}

/// One person in the picture: where their row sits, when their photos start (months after the left edge) and how
/// many months have a photo.
class _Row {
  const _Row(this.y, this.color, this.letter, this.start, this.keep);

  final double y;
  final Color color;
  final String letter;
  final int start;
  final double keep;
}

/// A month with a photo, as a short upright dash in a person's row.
class _Dash {
  const _Dash(this.row, this.month, this.height);

  final int row;
  final int month;
  final double height;
}

/// Draws three people appearing along seven years. A marker crosses the years; each person's face lights up when the
/// marker reaches their first photo, and their months fill in behind it. The picture is drawn on a 288 by 146 sheet
/// and scaled to the space it gets. The loop builds up, holds, fades out and starts again.
class _TipPainter extends CustomPainter {
  _TipPainter({required this.clock, required TextStyle labelStyle}) : super(repaint: clock) {
    final label = labelStyle.copyWith(fontSize: 9.5, fontWeight: FontWeight.w500, color: AppColors.ink48, height: 1);
    final chip = labelStyle.copyWith(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.white, height: 1);
    final initial = labelStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, height: 1);
    final dim = initial.copyWith(color: Colors.white.withValues(alpha: _dimmed));
    for (final year in _axisYears) {
      _axisLabels[year] = _lay('$year', label);
    }
    for (var i = 0; i < _years; i++) {
      _chipLabels.add(_lay('${_firstYear + i}', chip));
    }
    for (final row in _rows) {
      _initials.add(_lay(row.letter, initial));
      _dimInitials.add(_lay(row.letter, dim));
    }
  }

  final AnimationController clock;

  static const double width = 288;
  static const double height = 146;
  static const int cycleMs = 7200;
  static const int buildMs = 5000;

  /// Where the clock rests with motion off: the end of the build, everything drawn.
  static const double restAt = buildMs / cycleMs;

  static const int _firstYear = 2019;
  static const int _years = 7;
  static const int _months = _years * 12;
  static const double _left = 42;
  static const double _right = 282;
  static const double _perMonth = (_right - _left) / _months;
  static const double _axisY = 122;
  static const double _dimmed = 0.3;
  static const List<int> _axisYears = [2019, 2021, 2023, 2025];

  static const List<_Row> _rows = [
    _Row(38, PeoplePalette.green450, 'A', 0, 0.55),
    _Row(70, PeoplePalette.red450, 'D', 30, 0.6),
    _Row(102, PeoplePalette.indigo450, 'M', 52, 0.65),
  ];

  static final List<_Dash> _dashes = _makeDashes();

  final Map<int, TextPainter> _axisLabels = {};
  final List<TextPainter> _chipLabels = [];
  final List<TextPainter> _initials = [];
  final List<TextPainter> _dimInitials = [];
  final Paint _paint = Paint();

  static List<_Dash> _makeDashes() {
    final dashes = <_Dash>[];
    for (var r = 0; r < _rows.length; r++) {
      final random = math.Random(11 + r * 97);
      for (var m = _rows[r].start; m < _months; m++) {
        if (random.nextDouble() > _rows[r].keep) continue;
        dashes.add(_Dash(r, m, 10 + (random.nextDouble() * 8).roundToDouble()));
      }
    }
    return dashes;
  }

  static TextPainter _lay(String text, TextStyle style) {
    return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  }

  void dispose() {
    for (final painter in [..._axisLabels.values, ..._chipLabels, ..._initials, ..._dimInitials]) {
      painter.dispose();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = clock.value * cycleMs;
    final fade = math.min(1.0, math.min(elapsed / 350, (cycleMs - elapsed) / 700));
    final progress = Curves.easeInOutQuad.transform((elapsed / buildMs).clamp(0.0, 1.0));
    final month = progress * (_months - 1);

    canvas.save();
    canvas.scale(size.width / width);
    if (fade < 1) {
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, width, height),
        Paint()..color = Colors.black.withValues(alpha: fade),
      );
    }
    _drawAxis(canvas);
    _drawRows(canvas, month);
    _drawMarker(canvas, month);
    if (fade < 1) canvas.restore();
    canvas.restore();
  }

  void _drawAxis(Canvas canvas) {
    _paint
      ..color = AppColors.hairline
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(_left, _axisY), const Offset(_right, _axisY), _paint);
    _paint
      ..color = AppColors.ink48
      ..strokeWidth = 1;
    for (final year in _axisYears) {
      final x = _left + (year - _firstYear) * 12 * _perMonth;
      canvas.drawLine(Offset(x, _axisY), Offset(x, _axisY + 4), _paint);
      final label = _axisLabels[year]!;
      label.paint(canvas, Offset(x - label.width / 2, 131));
    }
    _paint.style = PaintingStyle.fill;
  }

  void _drawRows(Canvas canvas, double month) {
    for (var r = 0; r < _rows.length; r++) {
      final row = _rows[r];
      final lit = ((month - row.start + 1.5) / 3).clamp(0.0, 1.0);
      _paint
        ..color = row.color.withValues(alpha: _dimmed + (1 - _dimmed) * lit)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(18, row.y), 12, _paint);
      _drawInitial(canvas, r, lit);

      _paint
        ..color = AppColors.hairline
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(_left + row.start * _perMonth, row.y), Offset(_right, row.y), _paint);
    }
    _paint.style = PaintingStyle.fill;
    for (final dash in _dashes) {
      final grown = ((month - dash.month) / 3).clamp(0.0, 1.0);
      if (grown <= 0) continue;
      final row = _rows[dash.row];
      final h = dash.height * grown;
      _paint.color = row.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_left + dash.month * _perMonth + 0.3, row.y - h / 2, _perMonth - 0.7, h),
          const Radius.circular(1),
        ),
        _paint,
      );
    }
  }

  /// A person's letter, fading from dim to white as their face lights up. The fade needs a layer, which only the few
  /// frames in between use.
  void _drawInitial(Canvas canvas, int r, double lit) {
    final dim = _dimInitials[r];
    final full = _initials[r];
    final at = Offset(18 - full.width / 2, _rows[r].y - full.height / 2);
    if (lit >= 1) {
      full.paint(canvas, at);
      return;
    }
    dim.paint(canvas, at);
    if (lit <= 0) return;
    canvas.saveLayer(at & full.size, Paint()..color = Colors.black.withValues(alpha: lit));
    full.paint(canvas, at);
    canvas.restore();
  }

  void _drawMarker(Canvas canvas, double month) {
    final x = _left + month * _perMonth;
    _paint
      ..color = AppColors.primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 20), Offset(x, _axisY), _paint);
    _paint.style = PaintingStyle.fill;

    final chipX = x.clamp(_left + 6, _right - 6).toDouble();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(chipX - 17, 2, 34, 15), const Radius.circular(7.5)),
      _paint,
    );
    final year = _chipLabels[math.min(_years - 1, month ~/ 12)];
    year.paint(canvas, Offset(chipX - year.width / 2, 9.5 - year.height / 2));
  }

  @override
  bool shouldRepaint(_TipPainter oldDelegate) => oldDelegate.clock != clock;
}
