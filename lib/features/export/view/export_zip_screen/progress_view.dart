part of '../export_zip_screen.dart';

class _ProgressView extends StatefulWidget {
  const _ProgressView({super.key, required this.c});

  final ExportController c;

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView>
    with SingleTickerProviderStateMixin {
  /// The least time in seconds the whole show takes, from empty to full, so that a zip made almost at once still plays
  /// the folders filling and does not flash past.
  static const double _minSeconds = 4.2;

  /// How far the show has got, from 0 to 1. It follows the real progress but never faster than [_minSeconds] allows.
  /// When the real progress is slower, the show keeps up with it.
  final ValueNotifier<double> _shown = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;
  double _elapsed = 0;
  double _holdFor = 0;
  bool _handedOver = false;

  /// Where each zip ends on the line from 0 to 1, to tell which zip it is on.
  late final List<double> _partEnds = () {
    final sizes = widget.c.partSizes;
    final total = sizes.fold<int>(0, (a, b) => a + b);
    var sum = 0;
    return [for (final s in sizes) total == 0 ? 1.0 : (sum += s) / total];
  }();

  /// Recent readings of the time and the bytes done, for how fast the real thing is going.
  final List<(DateTime, int)> _readings = [];

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown.dispose();
    super.dispose();
  }

  /// Moves the show on by one frame. The show goes no faster than [_minSeconds] allows, easing in over the first half
  /// second, and chases the real progress when that is slower. The last of a finished zip goes at the same pace and is
  /// not slowed to a crawl. Once all of it is shown and the zip is made, it holds a moment with everything shut and
  /// then hands over to the result.
  void _tick(Duration now) {
    final dt = _last == null
        ? 0.0
        : ((now - _last!).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = now;
    _elapsed += dt;
    final status = widget.c.status;
    final finished = !status.running;
    final real = status.phase == 'preparing'
        ? 0.0
        : (finished ? 1.0 : status.fraction);

    var v = _shown.value;
    if (real > v) {
      final cap = dt / _minSeconds * (_elapsed / .5).clamp(0.0, 1.0);
      final chase = (real - v) * (1 - math.exp(-dt * 6));
      var step = math.min(cap, chase);
      if (finished && real - v < .02) step = math.min(real - v, cap);
      v += step;
    }
    if (v != _shown.value) _shown.value = v;

    if (finished && v >= 1 && !_handedOver) {
      _holdFor += dt;
      if (_holdFor > .8) {
        _handedOver = true;
        widget.c.finishPlayback();
      }
    }
  }

  String? _timeLeft(ZipExportStatus s) {
    final now = DateTime.now();
    if (_readings.isEmpty || _readings.last.$2 != s.bytesDone) {
      _readings.add((now, s.bytesDone));
    }
    _readings.removeWhere((r) => now.difference(r.$1).inSeconds > 12);
    if (_readings.length < 3 || s.bytesTotal <= 0) return null;
    final seconds = now.difference(_readings.first.$1).inMilliseconds / 1000;
    final bytes = s.bytesDone - _readings.first.$2;
    if (seconds < 2 || bytes <= 0) return null;
    final left = (s.bytesTotal - s.bytesDone) / (bytes / seconds);
    if (left < 8) return 'a few seconds left';
    if (left < 90) return 'about ${left.round()} seconds left';
    final minutes = (left / 60).round();
    if (minutes < 90) {
      return 'about $minutes ${minutes == 1 ? 'minute' : 'minutes'} left';
    }
    return 'about ${(minutes / 60).toStringAsFixed(1)} hours left';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.status;
    final textTheme = Theme.of(context).textTheme;
    final preparing = s.phase == 'preparing';
    final folders = c.folders;
    final files = folders.isEmpty
        ? s.filesTotal
        : folders.fold<int>(0, (sum, f) => sum + f.count);
    final bytes = folders.isEmpty
        ? s.bytesTotal
        : folders.fold<int>(0, (sum, f) => sum + f.bytes);
    final parts = _partEnds.length > 1 ? _partEnds.length : s.partsTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.base,
      ),
      child: Column(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _shown,
            builder: (context, v, _) {
              final done = v >= 1 && !s.running;
              final left = !preparing && s.running && v >= s.fraction - .02
                  ? _timeLeft(s)
                  : null;
              return Column(
                children: [
                  Text(
                    preparing
                        ? 'Checking your files'
                        : (done ? 'All zipped up' : 'Making your zip'),
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    preparing
                        ? '${s.filesDone} of ${s.filesTotal}'
                        : '${(v * files).round()} of $files files · ${zipBytes(v * bytes)} of ${zipBytes(bytes)}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink80,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      if (left != null) left,
                      if (!preparing) '${(v * 100).floor()}%',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.base),
          ZipperBar(progress: _shown),
          if (parts > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            ValueListenableBuilder<double>(
              valueListenable: _shown,
              builder: (context, v, _) {
                var part = 1;
                if (_partEnds.length > 1) {
                  while (part < _partEnds.length &&
                      v > _partEnds[part - 1] + 1e-6) {
                    part++;
                  }
                } else {
                  part = s.part.clamp(1, parts);
                }
                return Column(
                  children: [
                    _PartDots(total: parts, current: part),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Zip $part of $parts',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: folders.isEmpty
                ? Center(
                    child: Text(
                      s.currentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  )
                : ZipFolderTree(
                    folders: folders,
                    progress: _shown,
                    thumbs: c.thumbs,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'It carries on if you leave the app. Your photos and videos are only read, never changed.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Continue in background',
              enabled: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (s.running)
            TextButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Cancel the zip?',
                message:
                    'What has been made so far is deleted. Your photos and videos are untouched.',
                confirmLabel: 'Cancel zip',
                onConfirm: c.cancel,
              ),
              child: const Text('Cancel zip'),
            )
          else
            const SizedBox(height: 48),
        ],
      ),
    );
  }
}

/// One dot per zip: the ones done are filled, and the one being made pulses a little.
class _PartDots extends StatelessWidget {
  const _PartDots({required this.total, required this.current});

  final int total, current;

  @override
  Widget build(BuildContext context) {
    final shown = total > 12 ? 12 : total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= shown; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 22 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: i < current
                  ? AppColors.primary
                  : (i == current
                        ? AppColors.primaryFocus
                        : AppColors.hairline),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        if (total > shown)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+${total - shown}'),
          ),
      ],
    );
  }
}
