part of '../tour_screen.dart';

/// Where the download is, small: a ring and the percentage, at the top of the tour.
class _DownloadChip extends StatelessWidget {
  const _DownloadChip({
    super.key,
    required this.state,
    this.onTap,
  });

  final TourDownloadState state;

  /// Brings the card back down.
  final VoidCallback? onTap;

  /// The tap reaches past the small chip, to the height of the bar it sits in.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String text;
    switch (state.phase) {
      case TourDownloadPhase.done:
        text = 'Ready';
      case TourDownloadPhase.verifying:
        text = 'Checking';
      case TourDownloadPhase.connecting:
        text = 'Starting';
      case TourDownloadPhase.paused:
        text = 'Paused  ·  ${state.percent}%';
      default:
        text = '${state.percent}%';
    }
    final double? ring = switch (state.phase) {
      TourDownloadPhase.connecting || TourDownloadPhase.verifying => null,
      _ => state.fraction,
    };
    final chip = Semantics(
      label: onTap == null
          ? 'Download: $text'
          : 'Download: $text. Tap to show details',
      excludeSemantics: true,
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: 8, right: 12),
        decoration: BoxDecoration(
          color: TourPalette.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: TourPalette.line),
          boxShadow: kTourSoftShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (state.done)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: TourPalette.teal,
              )
            else if (state.paused)
              const Icon(
                Icons.pause_circle_filled_rounded,
                size: 18,
                color: TourPalette.teal,
              )
            else
              _Ring(value: ring, size: 18),
            const SizedBox(width: 7),
            Text(
              text,
              style: textTheme.labelMedium?.copyWith(
                color: TourPalette.text,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: chip,
        ),
      ),
    );
  }
}
