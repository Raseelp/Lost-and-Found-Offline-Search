import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:lost_and_found/controllers/export_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';

// What the zip export shows while it works: the folders that are going into the zip, listed as
// they will be in it (each album with its Images and Videos), each filling with its own bar and
// count, with a real thumbnail of its photos or videos dropping onto the bar as it goes, and a
// zipper along the top that closes as the whole fills.
//
// All of it is driven by one number, how far the show has got (0..1): a folder's part of the
// bar is a slice of that, so it plays the same whether the zip takes a moment or an hour.

/// A zipper across the width: shut behind the slider, gaping ahead of it. [progress] is 0..1.
class ZipperBar extends StatelessWidget {
  const ZipperBar({super.key, required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => CustomPaint(
            size: Size.infinite,
            painter: _ZipperBarPainter(value),
          ),
        ),
      ),
    );
  }
}

class _ZipperBarPainter extends CustomPainter {
  _ZipperBarPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const inset = 14.0;
    final left = inset, right = size.width - inset;
    final slider = left + (right - left) * progress;

    // The strip it is sewn into.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(2, y - 15, size.width - 2, y + 15),
        const Radius.circular(15),
      ),
      Paint()..color = AppColors.parchment,
    );
    // What is already shut takes the colour.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(2, y - 15, math.max(2.0, slider + 6), y + 15),
        const Radius.circular(15),
      ),
      Paint()..color = AppColors.primary.withValues(alpha: .1),
    );

    final tooth = Paint()
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ink48;
    var n = 0;
    for (var x = left; x <= right; x += 6) {
      final shut = x <= slider;
      final gap = shut ? 0.0 : math.min(8.0, (x - slider) * .3);
      final lift = n.isEven ? -2.2 : 2.2;
      canvas.drawLine(
        Offset(x, y - gap + lift),
        Offset(x, y - gap + lift + (shut ? 3 : .01)),
        tooth,
      );
      if (!shut) {
        canvas.drawLine(
          Offset(x, y + gap - lift),
          Offset(x, y + gap - lift + 3),
          tooth,
        );
      }
      n++;
    }
    // The slider and its pull.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(slider, y), width: 13, height: 19),
        const Radius.circular(4),
      ),
      Paint()..color = AppColors.primary,
    );
    canvas.drawLine(
      Offset(slider, y + 9),
      Offset(slider, y + 17),
      Paint()
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_ZipperBarPainter old) => old.progress != progress;
}

/// The folders, album by album. Follows the folder being filled by scrolling to its album.
class ZipFolderTree extends StatefulWidget {
  const ZipFolderTree({
    super.key,
    required this.folders,
    required this.progress,
    required this.thumbs,
  });

  final List<ZipFolderPlan> folders;

  /// How far the whole has got, 0..1.
  final ValueListenable<double> progress;

  /// Thumbnails by file (the ones that are ready).
  final Map<String, Uint8List> thumbs;

  @override
  State<ZipFolderTree> createState() => _ZipFolderTreeState();
}

class _ZipFolderTreeState extends State<ZipFolderTree> {
  late final List<List<ZipFolderPlan>> _albums = () {
    final out = <List<ZipFolderPlan>>[];
    for (final folder in widget.folders) {
      if (out.isNotEmpty && out.last.first.albumKey == folder.albumKey) {
        out.last.add(folder);
      } else {
        out.add([folder]);
      }
    }
    return out;
  }();
  final ScrollController _scroll = ScrollController();
  int _active = -1;

  // Where each album's block starts in the list (the blocks have fixed heights).
  late final List<double> _offsets = () {
    var at = 4.0;
    final out = <double>[];
    for (final album in _albums) {
      out.add(at);
      at += _AlbumBlock.heightFor(album.length);
    }
    return out;
  }();

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_follow);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  // Brings the album being filled into view when the filling moves on to the next.
  void _follow() {
    final v = widget.progress.value;
    var active = 0;
    for (var i = 0; i < _albums.length; i++) {
      if (v >= _albums[i].first.start) active = i;
    }
    if (active == _active) return;
    _active = active;
    if (!_scroll.hasClients) return;
    final target = (_offsets[active] - 24).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _albums.length,
      itemBuilder: (context, i) => _AlbumBlock(
        folders: _albums[i],
        progress: widget.progress,
        thumbs: widget.thumbs,
      ),
    );
  }
}

// One album: its folder and the Images / Videos folders inside it.
class _AlbumBlock extends StatelessWidget {
  const _AlbumBlock({
    required this.folders,
    required this.progress,
    required this.thumbs,
  });

  // Padding, the album's own row, and a row for each folder in it.
  static double heightFor(int folderCount) => 8 + 36 + 44.0 * folderCount;

  final List<ZipFolderPlan> folders;
  final ValueListenable<double> progress;
  final Map<String, Uint8List> thumbs;

  static double fraction(ZipFolderPlan folder, double v) =>
      folder.end <= folder.start
      ? (v >= 1 ? 1 : 0)
      : ((v - folder.start) / (folder.end - folder.start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = folders.fold<int>(0, (sum, f) => sum + f.count);
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, v, _) {
          var done = 0;
          var started = false, finished = true;
          for (final f in folders) {
            final p = fraction(f, v);
            done += p >= 1 ? f.count : (p * f.count).floor();
            if (p > 0) started = true;
            if (p < 1) finished = false;
          }
          final tint = finished || started
              ? AppColors.primary
              : AppColors.ink48;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          finished
                              ? Icons.folder_special_rounded
                              : Icons.folder_rounded,
                          key: ValueKey(finished),
                          color: tint,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          folders.first.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            color: started ? AppColors.ink : AppColors.ink48,
                          ),
                        ),
                      ),
                      Text(
                        '$done / $total',
                        style: textTheme.bodySmall?.copyWith(
                          color: started ? AppColors.ink80 : AppColors.ink48,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final f in folders)
                  _FolderRow(folder: f, p: fraction(f, v), thumbs: thumbs),
              ],
            ),
          );
        },
      ),
    );
  }
}

// The Images or the Videos folder of an album: a bar that fills, its count, and the thumbnail of
// the file going in riding on the head of the bar.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.p,
    required this.thumbs,
  });

  final ZipFolderPlan folder;
  final double p;
  final Map<String, Uint8List> thumbs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final waiting = p <= 0, finished = p >= 1;
    final done = finished ? folder.count : (p * folder.count).floor();
    final sampleIndex = (p * folder.sample.length).floor().clamp(
      0,
      folder.sample.length - 1,
    );
    final item = folder.sample[sampleIndex];
    final bytes = thumbs[item.uri];

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.only(left: 34),
        child: Row(
          children: [
            Icon(
              folder.videos ? Icons.videocam_outlined : Icons.image_outlined,
              size: 18,
              color: waiting ? AppColors.ink48 : AppColors.primary,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                folder.videos ? 'Videos' : 'Images',
                style: textTheme.bodySmall?.copyWith(
                  color: waiting ? AppColors.ink48 : AppColors.ink,
                  fontWeight: waiting || finished
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  const tile = 30.0;
                  final head = ((box.maxWidth - tile) * p).clamp(
                    0.0,
                    box.maxWidth - tile,
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      SizedBox(
                        height: 8,
                        width: box.maxWidth,
                        child: CustomPaint(painter: _BarPainter(p)),
                      ),
                      if (!waiting && !finished)
                        Positioned(
                          left: head,
                          top: 7,
                          child: _DropIn(
                            key: ValueKey(sampleIndex),
                            child: _Thumb(
                              bytes: bytes,
                              video: folder.videos,
                              size: tile,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              width: 76,
              child: Align(
                alignment: Alignment.centerRight,
                child: finished
                    ? const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.primary,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$done / ${folder.count}',
                          maxLines: 1,
                          style: textTheme.bodySmall?.copyWith(
                            color: waiting ? AppColors.ink48 : AppColors.ink80,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(4),
    );
    canvas.drawRRect(track, Paint()..color = AppColors.hairline);
    if (p <= 0) return;
    final fill = Rect.fromLTWH(
      0,
      0,
      math.max(size.height, size.width * p),
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, const Radius.circular(4)),
      Paint()..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.p != p;
}

// A small square of a photo or video (a plain tile with its icon until the thumbnail is there).
class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.video, required this.size});

  final Uint8List? bytes;
  final bool video;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm + 1),
        border: Border.all(color: Colors.white, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm - 1),
        child: bytes != null
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: 72,
                gaplessPlayback: true,
              )
            : ColoredBox(
                color: AppColors.parchment,
                child: Icon(
                  video ? Icons.play_arrow_rounded : Icons.image_outlined,
                  size: 16,
                  color: AppColors.ink48,
                ),
              ),
      ),
    );
  }
}

// Drops its child in from above with a small bounce when it appears.
class _DropIn extends StatelessWidget {
  const _DropIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -16 * (1 - t)),
          child: Transform.scale(scale: .7 + .3 * t, child: child),
        ),
      ),
      child: child,
    );
  }
}
