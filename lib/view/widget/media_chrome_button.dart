import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/palettes/viewer_palette.dart';

/// For the photo and video viewers, whose background is black: light
/// status/navigation icons (the app-wide style has dark ones for the light
/// theme), with the navigation bar painted black to match the viewers' background.
const SystemUiOverlayStyle kMediaOverlayStyle = SystemUiOverlayStyle(
  systemNavigationBarColor: AppColors.mediaBackdrop,
  systemNavigationBarDividerColor: AppColors.mediaBackdrop,
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.light,
  statusBarColor: AppColors.transparent,
  statusBarIconBrightness: Brightness.light,
);

// Floating chrome over a photo or video, in the same language as the face-tapping
// effects in the viewer: a soft dark disc (no blur) edged by a thin ring in the app's
// flowing colours - faint at rest, brighter when the thing it controls is on ([active]).
// Standard regardless of the app's light theme underneath (the media, not the app
// chrome, is what's on screen), so this stays outside the app's light-surface token
// language on purpose. Shared by the image and video viewers.
class MediaChromeButton extends StatelessWidget {
  const MediaChromeButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  // Long-press label (and what a screen reader says) - these are bare icons
  // next to each other, so which is which isn't obvious at a glance.
  final String? tooltip;
  // The control's thing is switched on (e.g. the details sheet is open).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _RimPainter(active),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.scrim.withValues(alpha: active ? 0.5 : 0.38),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon, color: AppColors.onMedia, size: 22),
          tooltip: tooltip,
          onPressed: onTap,
        ),
      ),
    );
  }
}

// The colours of the ring: the app's teal (lightened to read on a photo) through
// blue, violet, pink and gold, and back.
const List<Color> _rimColors = [
  AppColors.mediaAccent,
  ViewerPalette.sky250,
  ViewerPalette.indigo250,
  ViewerPalette.pink250,
  ViewerPalette.orange300,
  AppColors.mediaAccent,
];

class _RimPainter extends CustomPainter {
  _RimPainter(this.active);

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final alpha = active ? 0.95 : 0.5;
    canvas.drawCircle(
      rect.center,
      size.shortestSide / 2 - 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.8 : 1.2
        ..shader = SweepGradient(
          colors: [for (final c in _rimColors) c.withValues(alpha: alpha)],
          transform: const GradientRotation(-1.2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => old.active != active;
}
