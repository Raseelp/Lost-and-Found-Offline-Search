part of '../video_full_screen.dart';

class _VideoMetadataContent extends StatelessWidget {
  const _VideoMetadataContent({
    required this.metadata,
    required this.isLoading,
    required this.matchExplanation,
    required this.matchedFrameBytes,
    required this.matchedTimestampMs,
  });

  final ImageMetadata metadata;
  final bool isLoading;
  final List<MapEntry<String, double>> matchExplanation;
  final Uint8List matchedFrameBytes;
  final int matchedTimestampMs;

  String _formatTimestamp(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (matchExplanation.isNotEmpty) ...[
            const InfoGroupLabel('Why this matched'),
            const SizedBox(height: AppSpacing.sm),
            _MatchedFrameRow(
              bytes: matchedFrameBytes,
              label: 'Matched at ${_formatTimestamp(matchedTimestampMs)}',
            ),
            const SizedBox(height: AppSpacing.base),
            MatchStrengthBars(entries: matchExplanation),
            const SizedBox(height: AppSpacing.xl),
          ],
          const InfoGroupLabel('File information'),
          const SizedBox(height: AppSpacing.sm),
          InfoGroupCard(
            children: [
              InfoRow(
                icon: Icons.videocam_outlined,
                label: 'File name',
                value: metadata.fileName.isNotEmpty
                    ? metadata.fileName
                    : 'Unknown',
              ),
              InfoRow(
                icon: Icons.folder_outlined,
                label: 'File path',
                value: metadata.imagePath.isNotEmpty
                    ? metadata.imagePath
                    : 'Unknown',
              ),
              if (metadata.durationMs > 0)
                InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: metadata.durationFormatted,
                ),
              InfoRow(
                icon: Icons.straighten_rounded,
                label: 'Resolution',
                value: metadata.resolution,
              ),
              InfoRow(
                icon: Icons.storage_rounded,
                label: 'File size',
                value: metadata.fileSizeFormatted,
              ),
              InfoRow(
                icon: Icons.type_specimen_outlined,
                label: 'Format',
                value: metadata.mimeType.split('/').last.toUpperCase(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

/// A small preview of the exact frame CLIP matched, not just the words that matched it, as in the search grid's
/// thumbnail (see search_results.dart), so that "why this matched" reads as concretely as in the image viewer.
class _MatchedFrameRow extends StatelessWidget {
  const _MatchedFrameRow({required this.bytes, required this.label});

  final Uint8List bytes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
