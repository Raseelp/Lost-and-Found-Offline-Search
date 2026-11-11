part of '../person_menu.dart';

/// The explanation, as a speech bubble opening underneath the badge once it has arrived, so the badge seems to speak
/// it. Cancel sends the badge back to the orbit, and confirming runs the action once it is gone. There is no Center
/// wrapper because a CompositedTransformFollower gives this widget loose but finite constraints, and Center or Align
/// would expand to fill them. A SizedBox(width: ...) with no height lets the Stack size itself to its content.
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

/// The bubble's background: a rounded rectangle with a small triangular notch at the top centre, pointing up at the
/// badge it belongs to. It is one shape with one shadow, so the notch never looks stuck on.
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
