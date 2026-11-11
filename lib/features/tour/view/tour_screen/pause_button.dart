part of '../tour_screen.dart';

/// A round button that pauses the download, or carries on with it when it is paused.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.paused, required this.onTap});

  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: paused ? 'Resume download' : 'Pause download',
      excludeSemantics: true,
      child: Tooltip(
        message: paused ? 'Resume' : 'Pause',
        child: Material(
          color: paused
              ? TourPalette.teal
              : TourPalette.teal.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  key: ValueKey(paused),
                  size: 24,
                  color: paused ? TourPalette.white : TourPalette.teal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
