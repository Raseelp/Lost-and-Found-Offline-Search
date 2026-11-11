part of '../tour_screen.dart';

/// The download, with the details: it opens when the download starts and when it needs the person, tucks into the
/// chip after a few seconds (tap the chip to bring it back), and has the button that pauses and resumes it. A tap on
/// the rest of the card tucks it away.
class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.download,
    required this.state,
    required this.onMinimise,
  });

  final TourDownload download;
  final TourDownloadState state;
  final VoidCallback onMinimise;

  /// Pausing is offered while bytes are coming (or being asked for), and resuming while it is paused.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String title, detail;
    String? action;
    switch (state.phase) {
      case TourDownloadPhase.error:
        title = 'Download stopped';
        detail = 'Check your connection';
        action = 'Try again';
      case TourDownloadPhase.connecting:
        title = 'Starting the download';
        detail = 'Connecting to the server';
      case TourDownloadPhase.verifying:
        title = 'Checking the download';
        detail = 'Almost ready';
      case TourDownloadPhase.paused:
        title = 'Download paused';
        detail =
            '${state.percent}%  ·  ${_size(state.downloadedBytes)} of ${_size(state.totalBytes)}';
      default:
        title = 'Downloading search models';
        detail =
            '${state.percent}%  ·  ${_size(state.downloadedBytes)} of ${_size(state.totalBytes)}';
    }
    final Widget lead;
    switch (state.phase) {
      case TourDownloadPhase.error:
        lead = const Icon(
          Icons.error_outline_rounded,
          size: 26,
          color: TourPalette.red550,
        );
      case TourDownloadPhase.connecting || TourDownloadPhase.verifying:
        lead = const _Ring(value: null);
      default:
        lead = _Ring(value: state.fraction);
    }
    final canPause =
        state.phase == TourDownloadPhase.downloading ||
        state.phase == TourDownloadPhase.connecting;
    return Semantics(
      liveRegion: true,
      label: '$title. $detail',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onMinimise,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: TourPalette.white,
            borderRadius: BorderRadius.circular(AppRadius.lg + 2),
            border: Border.all(color: TourPalette.line),
            boxShadow: kTourSoftShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 30, height: 30, child: Center(child: lead)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: TourPalette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: TourPalette.text60,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (canPause || state.paused) ...[
                const SizedBox(width: 6),
                _PauseButton(
                  paused: state.paused,
                  onTap: state.paused ? download.resume : download.pause,
                ),
              ],
              if (action != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: download.start,
                  style: TextButton.styleFrom(
                    foregroundColor: TourPalette.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    action,
                    style: textTheme.labelLarge?.copyWith(
                      color: TourPalette.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}
