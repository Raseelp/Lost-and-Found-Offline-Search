part of '../scan_square.dart';

/// What a scan tells the user under the chip: one gauge for whatever the scan is doing. While photos are made
/// searchable it is gold (the top row of wires on the chip), with no bar for faces until a batch starts. When a batch
/// of faces starts the gauge fades to copper (the bottom row of wires) and shows the batch's progress, and when the
/// batch ends it fades back to gold.
class _ScanStory extends StatefulWidget {
  const _ScanStory({super.key, required this.stats, required this.queue, required this.facesNow});

  final ScanChipStats stats;
  final OrbitQueueInfo? queue;

  /// Indexing waits while the faces of a batch are found.
  final bool facesNow;

  @override
  State<_ScanStory> createState() => _ScanStoryState();
}

class _ScanStoryState extends State<_ScanStory> with SingleTickerProviderStateMixin {
  static const _photosColor = ScanPalette.gold450;
  static const _facesColor = AppColors.faceAccent;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  static String _count(int n) {
    final digits = '$n';
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// Time left, rounded the way people say it (a figure that changes every second is noise).
  static String _left(int ms) {
    final minutes = ms / 60000;
    if (minutes < .75) return 'under a minute left';
    if (minutes < 1.5) return 'about a minute left';
    if (minutes < 20) return 'about ${minutes.round()} min left';
    if (minutes < 90) return 'about ${(minutes / 5).round() * 5} min left';
    final hours = minutes / 60;
    if (hours < 10) {
      final halves = (hours * 2).round() / 2;
      return 'about ${halves == halves.roundToDouble() ? halves.round() : halves} h left';
    }
    return 'about ${hours.round()} h left';
  }

  _Channel _current() {
    final stats = widget.stats;
    final queue = widget.queue;
    final people = stats.people;
    final peopleNote = people > 0 ? '${_count(people)} ${people == 1 ? 'person' : 'people'} found so far' : null;

    if (stats.tuning) {
      return _Channel(
        label: 'Preparing face search for this phone',
        color: _facesColor,
        fraction: null,
        left: 'One time only, about a minute',
      );
    }
    if (widget.facesNow) {
      final total = stats.faceTotal > 0 ? stats.faceTotal : (queue?.photos ?? 60);
      return _Channel(
        label: 'Grouping faces in the last ${_count(total)} photos',
        color: _facesColor,
        fraction: stats.faceTotal > 0 ? (stats.faceDone / stats.faceTotal).clamp(0.0, 1.0) : null,
        figure: stats.faceTotal > 0 ? '${_count(stats.faceDone)} / ${_count(stats.faceTotal)}' : null,
        left: peopleNote,
      );
    }
    if (stats.total == 0) {
      return _Channel(
        label: 'Loading the embedding model into memory',
        color: _photosColor,
        fraction: null,
        left: stats.found != null ? '${_count(stats.found!)} items' : null,
      );
    }
    if (stats.indexed == 0) {
      return _Channel(
        label: 'Loading the embedding model into memory',
        color: _photosColor,
        fraction: null,
      );
    }
    return _Channel(
      label: 'Making your media searchable offline',
      color: _photosColor,
      fraction: (stats.indexed / stats.total).clamp(0.0, 1.0),
      figure: '${(stats.indexed * 100 / stats.total).floor()}%',
      left: '${_count(stats.indexed)} of ${_count(stats.total)}',
      right: stats.etaMs != null ? _left(stats.etaMs!) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final channel = _current();
    final sweeping = channel.fraction == null && !MediaQuery.disableAnimationsOf(context);
    if (sweeping && !_sweep.isAnimating) _sweep.repeat();
    if (!sweeping && _sweep.isAnimating) _sweep.stop();
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink);
    final figure = textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final detail = textTheme.bodySmall!.copyWith(
      color: AppColors.ink80,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ExcludeSemantics(
      child: FractionallySizedBox(
        widthFactor: 296 / 340,
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _channel(channel, label, figure, detail),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channel(_Channel c, TextStyle label, TextStyle figure, TextStyle detail) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(c.label, key: ValueKey(c.label), style: label, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (c.figure != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text(c.figure!, style: figure)),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: c.color),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          builder: (context, color, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: c.fraction ?? 0),
            duration: reduced ? Duration.zero : const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: const Size(double.infinity, 15),
              painter: _RulerPainter(
                fraction: c.fraction == null ? null : value,
                color: color ?? c.color,
                sweep: reduced ? null : _sweep,
              ),
            ),
          ),
        ),
        if (c.left != null || c.right != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(child: Text(c.left ?? '', style: detail, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (c.right != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(c.right!, style: detail, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ],
      ],
    );
  }
}

class _Channel {
  const _Channel({
    required this.label,
    required this.color,
    required this.fraction,
    this.figure,
    this.left,
    this.right,
  });

  final String label;
  final Color color;

  /// How far it is, 0..1 (null when that cannot be told yet: a sweep is shown instead).
  final double? fraction;
  final String? figure;

  /// The line under the ruler: what is done / found on the left, what is left on the right.
  final String? left, right;

}
