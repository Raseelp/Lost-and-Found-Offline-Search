import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/motion.dart';

/// One part of the page settling into place: it fades in and rises a little, a moment after the one before it. With
/// [pop] it also grows into its size with a small overshoot. [controller] runs once as the page opens, and the parts
/// share it, each in its own stretch of it.
class Settle extends StatelessWidget {
  const Settle({
    super.key,
    required this.controller,
    required this.index,
    required this.parts,
    required this.child,
    this.pop = false,
  });

  final AnimationController controller;
  final int index;
  final int parts;
  final Widget child;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    final start = 0.5 * index / parts;
    final end = start + 0.5;
    final fade = CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)).animate(controller);
    Widget content = FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(fade),
        child: child,
      ),
    );
    if (pop) {
      final grow = CurveTween(curve: Interval(start, end, curve: Curves.easeOutBack)).animate(controller);
      content = ScaleTransition(
        scale: Tween(begin: 0.8, end: 1.0).animate(grow),
        alignment: Alignment.centerLeft,
        child: content,
      );
    }
    return content;
  }
}

/// The page's background: parchment with two soft washes of the accent that drift slowly across it and back. [drift]
/// runs from 0 to 1 and back, slowly. With motion off it rests in the middle and nothing moves.
class DriftingBackground extends StatelessWidget {
  const DriftingBackground({super.key, required this.drift, required this.child});

  final Animation<double> drift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: drift,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(drift.value);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    gradient: RadialGradient(
                      center: Alignment(-0.9 + 0.8 * t, -1.05 + 0.25 * t),
                      radius: 1.15,
                      colors: [AppColors.primary.withValues(alpha: 0.14), AppColors.primary.withValues(alpha: 0)],
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(1.0 - 0.7 * t, -0.35 + 0.35 * t),
                        radius: 0.95,
                        colors: [AppColors.primaryGlow.withValues(alpha: 0.09), AppColors.primaryGlow.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Something that has just been added: it grows into place with a small overshoot, and does not move with motion off.
class Pop extends StatelessWidget {
  const Pop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: calm(context) ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) =>
          Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 0.85 + 0.15 * t, child: child)),
    );
  }
}
