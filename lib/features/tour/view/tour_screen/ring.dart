part of '../tour_screen.dart';

/// The progress as a ring: filling up, or going round while it is not a number yet.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, this.size = 30});

  /// 0 to 1, or null for "working".
  final double? value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: size > 22 ? 3 : 2.4,
        valueColor: const AlwaysStoppedAnimation<Color>(TourPalette.teal),
        backgroundColor: TourPalette.black.withValues(alpha: 0.09),
        strokeCap: StrokeCap.round,
      ),
    );
  }
}
