import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/viewer/view/widgets/viewer_palette.dart';

/// The shared shell for a floating panel over the photo and video viewer. The people strip and the "similar to this"
/// strip both live in one, so they read as one family of trays. It is frosted glass: [BackdropFilter] blurs the
/// picture behind it, a thin line of light sits along the top edge, and the accent shows once as a brief warm catch of
/// light while the tray opens.
class MediaTray extends StatefulWidget {
  const MediaTray({super.key, required this.child, this.accent = AppColors.mediaAccent});

  final Widget child;
  final Color accent;

  @override
  State<MediaTray> createState() => _MediaTrayState();
}

class _MediaTrayState extends State<MediaTray> with SingleTickerProviderStateMixin {
  late final AnimationController _open =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  /// Rises fast, then fades all the way out: a catch of light, not a standing glow.
  double _glow(double t) {
    if (t < 0.25) return Curves.easeOut.transform(t / 0.25);
    return 1.0 - Curves.easeIn.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, reveal, child) => Opacity(
        opacity: reveal,
        child: Transform.translate(offset: Offset(0, 14 * (1 - reveal)), child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.onMedia.withValues(alpha: 0.10), AppColors.scrim.withValues(alpha: 0.34)],
              ),
              border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.14)),
            ),
            child: Stack(
              children: [
                const Positioned(
                  left: 18,
                  right: 18,
                  top: 0,
                  child: SizedBox(
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.transparent, ViewerPalette.whiteA54, AppColors.transparent]),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _open,
                    builder: (context, _) => IgnorePointer(
                      child: Opacity(
                        opacity: _glow(_open.value),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [widget.accent.withValues(alpha: 0.3), AppColors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.onMedia.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      widget.child,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
