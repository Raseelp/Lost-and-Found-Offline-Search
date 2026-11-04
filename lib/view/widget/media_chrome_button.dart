import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/palettes/viewer_palette.dart';

/// For the photo and video viewers, whose background is black. It has light status and navigation icons (the
/// app-wide style has dark ones for the light theme), and the navigation bar is painted black to match.
const SystemUiOverlayStyle kMediaOverlayStyle = SystemUiOverlayStyle(
  systemNavigationBarColor: AppColors.mediaBackdrop,
  systemNavigationBarDividerColor: AppColors.mediaBackdrop,
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.light,
  statusBarColor: AppColors.transparent,
  statusBarIconBrightness: Brightness.light,
);

/// A round button floating over a photo or video, in the style of the face-tapping effects in the viewer. It is a
/// soft dark disc without blur, edged by a thin ring in the app's flowing colours, faint at rest and brighter when
/// the thing it controls is on ([active]). It does not follow the app's light theme, because the media is what is on
/// screen. The image and video viewers share it.
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
  /// The long-press label and what a screen reader says. The buttons are bare icons next to each other.
  final String? tooltip;
  /// Whether the thing the button controls is switched on, such as the details sheet being open.
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

/// The colours of the ring: the app's teal (lightened to read on a photo), then blue, violet, pink and gold, and
/// back to teal.
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
