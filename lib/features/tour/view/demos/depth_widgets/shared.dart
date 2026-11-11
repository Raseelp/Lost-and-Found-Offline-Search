part of '../depth_widgets.dart';

/// Where a widget is in its turn, for the ones that do something while they are at the front.
class _Turn {
  const _Turn(this.depth, this.focus, this.d, this.t);

  /// From 0 far to 1 near. A mix of its resting depth and how far forward it has come.
  final double depth;

  /// 0 when it is back, 1 at the middle of its turn.
  final double focus;

  /// Turns before (negative) or after (positive) the middle of its turn.
  final double d;

  /// Where the whole loop is, 0 to 1.
  final double t;
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: TourPalette.white),
      ),
      child: child,
    );
  }
}

TextStyle _small(
  BuildContext context, {
  Color? color,
  FontWeight? weight,
  double size = 10,
  double? height,
}) => Theme.of(context).textTheme.labelSmall!.copyWith(
  color: color ?? TourPalette.text60,
  fontWeight: weight ?? FontWeight.w400,
  fontSize: size,
  height: height ?? 1.2,
);
