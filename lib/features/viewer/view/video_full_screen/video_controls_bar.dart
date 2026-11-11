part of '../video_full_screen.dart';

/// The bottom bar: one calm rounded surface holding play and pause, the seek bar with the times under it and, when
/// there are people in the video, the People button. Same near-black surface and hairline edge as the rest of the
/// viewer's floating pieces, with no gradient wash over the picture.
class _VideoControlsBar extends StatelessWidget {
  const _VideoControlsBar({
    required this.controller,
    required this.formatDuration,
    required this.markers,
    required this.peopleCount,
    required this.peopleOpen,
    required this.peoplePulse,
    required this.onPlayPause,
    required this.onPeople,
  });

  final VideoPlayerController controller;
  final String Function(Duration) formatDuration;
  final List<int> markers;
  final int peopleCount;
  final bool peopleOpen;
  final int peoplePulse;
  final VoidCallback onPlayPause;
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.onMedia.withValues(alpha: 0.72),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.xxl,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs + 2,
          AppSpacing.xs + 2,
          AppSpacing.md,
          AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.mediaPanel,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.09)),
        ),
        child: Row(
          children: [
            MediaChromeButton(
              icon: value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              tooltip: value.isPlaying ? 'Pause' : 'Play',
              onTap: onPlayPause,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VideoScrubber(controller: controller, markers: markers),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(formatDuration(value.position), style: label),
                        const Spacer(),
                        Text(formatDuration(value.duration), style: label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (peopleCount > 0) ...[
              const SizedBox(width: AppSpacing.md),
              PeopleChipButton(
                count: peopleCount,
                pulse: peoplePulse,
                open: peopleOpen,
                onTap: onPeople,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
