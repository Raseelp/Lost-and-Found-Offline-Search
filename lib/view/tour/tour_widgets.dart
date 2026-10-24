import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';

/// The frame every page of the tour sits in: a title in the serif, a line under it, then the page's own
/// picture or demo. It scrolls when the phone is short.
class TourPageFrame extends StatelessWidget {
  const TourPageFrame({
    super.key,
    required this.title,
    this.emphasis,
    this.subtitle,
    required this.child,
    this.fill = false,
  });

  final String title;

  /// The one word of [title] set in the italic serif, in the app's teal.
  final String? emphasis;
  final String? subtitle;
  final Widget child;

  /// Starts at the top and gives [child] all the room that is left (it must then fill it), instead of centring a
  /// block that is only as tall as its content. Still scrolls when the phone is too short for [_fillMinHeight].
  final bool fill;

  static const double _fillMinHeight = 540;

  /// What the stage has at least: more when the person has made the text larger, because the title and line
  /// above it then take more room.
  static double _minHeightFor(BuildContext context, double room) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extra = 470 * (scale - 1).clamp(0.0, 1.5);
    return math.max(room, _fillMinHeight + extra);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.base,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.maxHeight - AppSpacing.base - AppSpacing.lg,
          ),
          child: fill
              ? Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 460,
                      minHeight: _minHeightFor(
                        context,
                        box.maxHeight - AppSpacing.base - AppSpacing.lg,
                      ),
                      maxHeight: _minHeightFor(
                        context,
                        box.maxHeight - AppSpacing.base - AppSpacing.lg,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._head(textTheme),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [..._head(textTheme), child],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  TextSpan _titleSpan() {
    final base = GoogleFonts.instrumentSerif(
      fontSize: 38,
      height: 1.04,
      color: TourPalette.text,
    );
    final at = emphasis == null ? -1 : title.indexOf(emphasis!);
    if (at < 0) return TextSpan(text: title, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: title.substring(0, at)),
        TextSpan(
          text: emphasis,
          style: GoogleFonts.instrumentSerif(
            fontSize: 38,
            height: 1.04,
            color: TourPalette.teal,
            fontStyle: FontStyle.italic,
          ),
        ),
        TextSpan(text: title.substring(at + emphasis!.length)),
      ],
    );
  }

  List<Widget> _head(TextTheme textTheme) => [
    Text.rich(_titleSpan()),
    if (subtitle != null) ...[
      const SizedBox(height: AppSpacing.md),
      Text(
        subtitle!,
        style: textTheme.bodyLarge?.copyWith(
          color: TourPalette.text80,
          height: 1.45,
        ),
      ),
    ],
    const SizedBox(height: AppSpacing.xl),
  ];
}

/// Draws [child] at the size it was designed for, whatever text size the phone is set to. The tour's pictures
/// (cards, bars, chips) are laid out in fixed boxes; larger system text would make their words overflow them.
/// The words of the pages themselves (titles, lines, buttons) are not wrapped in this and do follow the setting.
class FixedTextScale extends StatelessWidget {
  const FixedTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child,
    );
  }
}

/// Keeps the text in the bars around the pages (the chip, Close, the download card, the button) from growing past
/// 1.3 times: they sit on every page, and at the largest text sizes they would leave the pages no room. The
/// pages themselves follow the phone's setting in full.
class BarTextScale extends StatelessWidget {
  const BarTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: child,
    );
  }
}

/// A small label for what is made up in a demo ("Sample data").
class TourTag extends StatelessWidget {
  const TourTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: TourPalette.text60,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// A white card laid on the paper, a little off straight, with a soft shadow.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.tilt = 0,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.radius = AppRadius.xl,
  });

  final Widget child;

  /// Degrees.
  final double tilt;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: TourPalette.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: TourPalette.line),
          boxShadow: [
            BoxShadow(
              color: TourPalette.black.withValues(alpha: 0.09),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// The tour's page: soft white going to pale mint, with a little mint and peach glowing behind the content.
class TourBackground extends StatelessWidget {
  const TourBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [TourPalette.top, TourPalette.bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: -110,
            top: 170,
            child: _Glow(color: TourPalette.mint, size: 300),
          ),
          const Positioned(
            right: -100,
            bottom: 110,
            child: _Glow(color: TourPalette.peach, size: 280),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.85),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
