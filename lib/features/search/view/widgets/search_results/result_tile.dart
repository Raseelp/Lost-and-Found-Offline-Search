part of '../search_results.dart';

class _ResultTile extends StatefulWidget {
  const _ResultTile({
    required this.bytes,
    required this.isVideo,
    required this.onTap,
    this.upgradeMaxDimension,
    this.uri,
    this.timestampMs = 0,
    this.isNew = false,
  });

  final Uint8List bytes;
  final bool isVideo;
  final VoidCallback onTap;

  /// Whether the latest scan indexed it, which tags the tile.
  final bool isNew;

  /// Non-null only for a bento hero or showcase tile (see _bentoUpgradeDimension). [bytes] is still the cheap
  /// grid-tile decode and arrives at once so the tile never waits, and this triggers a one-time background fetch of a
  /// sharper version at that cap, crossfaded in when it lands, instead of raising the shared per-tile cap that every
  /// tile would pay for.
  final int? upgradeMaxDimension;
  final String? uri;
  final int timestampMs;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile>
    with SingleTickerProviderStateMixin {
  Uint8List? _upgradedBytes;

  /// Bumped every time _maybeUpgrade is triggered. A result that lands after a later request has started is from a
  /// superseded uri, since the same State can be reused for a different item at this grid index (see didUpdateWidget),
  /// and must be dropped.
  int _upgradeRequestId = 0;

  /// Plays once, the moment a sharper upgrade lands (see _maybeUpgrade). It is never touched for tiles that have no
  /// upgrade, so it costs nothing except on the rare hero or showcase tile. It drives the sheen and scale in build().
  late final AnimationController _focusReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void initState() {
    super.initState();
    _maybeUpgrade();
  }

  @override
  void dispose() {
    _focusReveal.dispose();
    super.dispose();
  }

  /// Uint8List has no structural equality, so this is an identity check. The same cached bytes object coming through
  /// on a rebuild, while thumbnails for other tiles stream in, correctly does nothing, and only a different item
  /// landing in this slot re-triggers the fetch.
  @override
  void didUpdateWidget(_ResultTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes || oldWidget.uri != widget.uri) {
      _upgradedBytes = null;
      _focusReveal.value = 0;
      _maybeUpgrade();
    }
  }

  /// Fetches the sharper version. The normal-res bytes already on screen are a fine fallback, so a missed upgrade
  /// never surfaces an error.
  Future<void> _maybeUpgrade() async {
    final maxDimension = widget.upgradeMaxDimension;
    if (maxDimension == null || widget.uri == null) return;
    final requestId = ++_upgradeRequestId;
    try {
      final upgraded = widget.isVideo
          ? await MediaService().loadVideoThumbnail(
              uri: widget.uri!,
              timestampMs: widget.timestampMs,
              maxDimension: maxDimension,
            )
          : await MediaService().loadImageBytes(
              uri: widget.uri!,
              isCompressed: true,
              maxDimension: maxDimension,
            );
      if (!mounted || requestId != _upgradeRequestId) return;
      setState(() => _upgradedBytes = upgraded);
      _focusReveal.forward(from: 0);
    } catch (_) {
    }
  }

  /// Image.memory decodes only to roughly the tile's on-screen size, off the longer tile edge, because the source's
  /// full resolution made scrolling memory-hungry. Only cacheWidth is set, because both cacheWidth and cacheHeight
  /// decode to exactly that box and ignore the photo's aspect ratio, which stretched thumbnails. AnimatedSwitcher's
  /// default layoutBuilder uses StackFit.loose, which let Image.memory fall back to its intrinsic size and leave a
  /// border, so the override uses StackFit.expand. _focusReveal adds a one-shot bell-shaped sheen and a small settling
  /// scale when an upgrade lands, and does nothing for tiles without one.
  @override
  Widget build(BuildContext context) {
    final activeBytes = _upgradedBytes ?? widget.bytes;
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final tileEdge = constraints.maxWidth > constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final cacheWidth = tileEdge.isFinite
                  ? (tileEdge * dpr).round()
                  : null;

              return Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _focusReveal,
                    builder: (context, child) {
                      final t = _focusReveal.value;
                      final eased = Curves.easeOutCubic.transform(t);
                      final scale = 1.02 - 0.02 * eased;
                      final sheenStrength = sin(t * pi).clamp(0.0, 1.0);
                      return Transform.scale(
                        scale: scale,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child!,
                            if (sheenStrength > 0.01)
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-1.6 + 3.2 * t, -1),
                                      end: Alignment(-0.5 + 3.2 * t, 1),
                                      colors: [
                                        AppColors.transparent,
                                        AppColors.primaryFocus.withValues(
                                          alpha: sheenStrength * 0.16,
                                        ),
                                        AppColors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOut,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Image.memory(
                        activeBytes,
                        key: ValueKey(identityHashCode(activeBytes)),
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                      ),
                    ),
                  ),
                  if (widget.isVideo)
                    widget.uri == null
                        ? const Positioned(right: 6, bottom: 6, child: _PlayMark())
                        : GridVideoLayer(uri: widget.uri!, idleBadge: const _PlayMark()),
                  if (widget.isNew)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: NewTag(compact: constraints.maxWidth < 96),
                    ),
                  Positioned(
                    right: 9,
                    top: 0,
                    child: MomentTag(uri: widget.uri, compact: constraints.maxWidth < 96),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The small play mark in the corner of a video's tile.
class _PlayMark extends StatelessWidget {
  const _PlayMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: AppColors.onMedia,
        size: 13,
      ),
    );
  }
}
