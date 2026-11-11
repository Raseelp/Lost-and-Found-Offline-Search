part of '../library_tab.dart';

/// What is indexed so far, as one card: the photos and videos counts large, and under them, quietly, the rest
/// (folders, embeddings, size on the phone and when it was last scanned). Files that could not be read get a line of
/// their own when there are some.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    super.key,
    required this.images,
    required this.videos,
    required this.folders,
    required this.embeddings,
    required this.sizeBytes,
    required this.lastScan,
    required this.failed,
  });

  final int images, videos, folders, embeddings, sizeBytes, failed;
  final DateTime? lastScan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      _count(folders, 'folder', 'folders'),
      _count(embeddings, 'embedding', 'embeddings'),
      if (sizeBytes > 0)
        '${ModelDownloadProgress.formatBytes(sizeBytes)} on device',
      if (lastScan != null) 'scanned ${_timeAgo(lastScan!)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _BigCount(
                      icon: Icons.image_outlined,
                      value: images,
                      label: images == 1 ? 'photo' : 'photos',
                    ),
                  ),
                  const VerticalDivider(
                    width: AppSpacing.base,
                    color: AppColors.hairline,
                  ),
                  Expanded(
                    child: _BigCount(
                      icon: Icons.videocam_outlined,
                      value: videos,
                      label: videos == 1 ? 'video' : 'videos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: AppSpacing.md),
            Text(
              details.join('  ·  '),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.45,
              ),
            ),
            if (failed > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      '${_count(failed, 'file', 'files')} could not be read and '
                      '${failed == 1 ? 'was' : 'were'} skipped',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink80,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _count(int n, String one, String many) =>
    '${_grouped(n)} ${n == 1 ? one : many}';

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  }
  if (diff.inDays < 7) {
    return diff.inDays == 1 ? 'yesterday' : '${diff.inDays} days ago';
  }
  return '${time.day}/${time.month}/${time.year}';
}

class _BigCount extends StatelessWidget {
  const _BigCount({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _grouped(value),
                maxLines: 1,
                style: textTheme.titleLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
        ),
      ],
    );
  }
}

String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
