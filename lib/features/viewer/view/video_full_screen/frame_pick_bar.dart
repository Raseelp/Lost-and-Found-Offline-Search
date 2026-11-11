part of '../video_full_screen.dart';

/// The playback bar while picking a frame: a real Slider with a big thumb
/// (unlike the thin, thumbless bar normally shown), so it reads as
/// draggable at a glance, seeking live so the frame on screen is the frame
/// that gets searched.
class _FramePickBar extends StatefulWidget {
  const _FramePickBar({
    required this.controller,
    required this.formatDuration,
    required this.onCancel,
    required this.onSearch,
  });

  final VideoPlayerController controller;
  final String Function(Duration) formatDuration;
  final VoidCallback onCancel;
  final VoidCallback onSearch;

  @override
  State<_FramePickBar> createState() => _FramePickBarState();
}

class _FramePickBarState extends State<_FramePickBar> {
  /// Seeking on every drag event floods the player with requests it can't
  /// keep up with (the picture lags behind the thumb); this lets one through
  /// every ~90ms while dragging and always lands exactly on release.
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  void _seek(double v, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSeek) < const Duration(milliseconds: 90)) {
      return;
    }
    _lastSeek = now;
    widget.controller.seekTo(Duration(milliseconds: v.round()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final formatDuration = widget.formatDuration;
    final onCancel = widget.onCancel;
    final onSearch = widget.onSearch;
    final durationMs = controller.value.duration.inMilliseconds;
    final positionMs = controller.value.position.inMilliseconds.clamp(
      0,
      durationMs > 0 ? durationMs : 1,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.xxl,
      ),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.onMedia24,
              thumbColor: AppColors.onMedia,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              overlayColor: AppColors.primary.withValues(alpha: 0.25),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            ),
            child: Slider(
              min: 0,
              max: durationMs > 0 ? durationMs.toDouble() : 1,
              value: positionMs.toDouble(),
              onChanged: _seek,
              onChangeEnd: (v) => _seek(v, force: true),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.onMedia70),
                ),
              ),
              const Spacer(),
              Text(
                formatDuration(controller.value.position),
                style: const TextStyle(color: AppColors.onMedia, fontSize: 13),
              ),
              const Spacer(),
              InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_search_rounded,
                        color: AppColors.onPrimary,
                        size: 18,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Show similar',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
