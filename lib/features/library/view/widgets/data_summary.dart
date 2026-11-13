import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/library/view/widgets/scan_steps.dart' show groupedCount;

/// What the app has made from the photos and videos so far, as four tiles of one size: the photos and the videos that
/// can be searched, the faces and the people they were grouped into, and the collections. Each tile has real pictures at
/// its top. The photos and videos are a small contact sheet of the ones indexed most recently, with a dashed slot for each
/// that there are not enough pictures for. The faces are a pile of faces of the people found, and the collections a fan
/// of their covers. Under the tiles, when the last scan was and, if there are any, how many files could not be read.
///
/// [photosOnPhone] and [videosOnPhone] are how many the gallery holds, or null when that is not known. The tiles then say
/// how many of them are searchable. The pictures are the most recently indexed ones, newest first, and a slot waits as a
/// plain block until its picture has been read.
class DataSummary extends StatelessWidget {
  const DataSummary({
    super.key,
    required this.photos,
    required this.videos,
    required this.photosOnPhone,
    required this.videosOnPhone,
    required this.faces,
    required this.people,
    required this.collections,
    required this.lastScan,
    required this.failed,
    this.photoPictures = const [],
    this.videoPictures = const [],
    this.facePictures = const [],
    this.collectionPictures = const [],
  });

  /// From this size of text the tiles go one under the other, as two side by side would leave the words too little room.
  static const _stackAbove = 18.5;
  static const _padding = AppSpacing.base - 2;
  static const _leastMedia = 60.0;
  static const _leastGap = AppSpacing.md;

  final int photos, videos, faces, people, collections, failed;
  final int? photosOnPhone, videosOnPhone;
  final DateTime? lastScan;
  final List<Uint8List> photoPictures, videoPictures, facePictures, collectionPictures;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final small = text.bodySmall?.copyWith(color: AppColors.ink48, height: 1.4);
    final photosIn = _outOf(photos, photosOnPhone);
    final videosIn = _outOf(videos, videosOnPhone);
    final stacked = MediaQuery.textScalerOf(context).scale(14) > _stackAbove;

    final tiles = [
      _Content(
        value: photos,
        of: photosIn,
        label: photos == 1 ? 'photo is searchable' : 'photos are searchable',
        media: _Sheet(columns: 4, rows: 2, aspect: 1, pictures: photoPictures, filled: math.min(photos, 8)),
        mediaHeight: (width) => _Sheet.heightFor(4, 2, 1, width),
      ),
      _Content(
        value: videos,
        of: videosIn,
        label: videos == 1 ? 'video is searchable' : 'videos are searchable',
        media: _Sheet(columns: 3, rows: 2, aspect: 0.62, pictures: videoPictures, filled: math.min(videos, 6), play: true),
        mediaHeight: (width) => _Sheet.heightFor(3, 2, 0.62, width),
      ),
      _Content(
        value: faces,
        label: faces == 1 ? 'face recognised and grouped into ' : 'faces recognised and grouped into ',
        strong: '${groupedCount(people)} ${people == 1 ? 'person' : 'people'}',
        media: _FacePile(pictures: people > 0 ? facePictures : const []),
      ),
      _Content(
        value: collections,
        label: collections == 1 ? 'collection that fills itself' : 'collections that fill themselves',
        media: _Fan(pictures: collectionPictures),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final width = stacked ? box.maxWidth : (box.maxWidth - AppSpacing.sm) / 2;
            final inner = width - 2 * _padding;
            final media = tiles.map((t) => t.mediaHeight(inner)).reduce(math.max);
            final height = tiles.map((t) => t.heightAt(context, inner)).reduce(math.max) + 2 * _padding + media + _leastGap;
            Widget tile(int i) => _Tile(content: tiles[i], height: height, mediaHeight: media);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(height: AppSpacing.sm), tile(i)]],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Expanded(child: tile(0)), const SizedBox(width: AppSpacing.sm), Expanded(child: tile(1))]),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [Expanded(child: tile(2)), const SizedBox(width: AppSpacing.sm), Expanded(child: tile(3))]),
              ],
            );
          },
        ),
        if (lastScan != null || failed > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.base,
            runSpacing: AppSpacing.xs,
            children: [
              if (lastScan != null) Text('Last scanned ${_timeAgo(lastScan!)}', style: small),
              if (failed > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.xs),
                    Text('$failed ${failed == 1 ? 'file' : 'files'} could not be read', style: small),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// How many there are on the phone. It is never less than how many are searchable, as a photo that was deleted after
  /// it was indexed is still in the index.
  int? _outOf(int searchable, int? onPhone) => onPhone == null ? null : math.max(onPhone, searchable);
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  if (diff.inDays < 7) return diff.inDays == 1 ? 'yesterday' : '${diff.inDays} days ago';
  return '${time.day}/${time.month}/${time.year}';
}

/// What one tile says and shows: a number, how many there are in all when that is known, the words, and the pictures.
/// [strong] is the part of the words that is a number of its own.
class _Content {
  const _Content({required this.value, required this.label, required this.media, this.mediaHeight = _fixedMedia, this.of, this.strong});

  final int value;
  final int? of;
  final String label;
  final String? strong;
  final Widget media;

  /// How tall the pictures are when there are [width] for them. The faces and the covers have a fixed height, and a contact
  /// sheet as tall as its frames, which are as wide as the room allows.
  final double Function(double width) mediaHeight;

  static double _fixedMedia(double width) => DataSummary._leastMedia;

  String get number => groupedCount(value);
  String? get total => of == null ? null : 'of ${groupedCount(of!)}';

  static TextStyle? numberStyle(TextTheme text) =>
      text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.15, fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle? wordsStyle(TextTheme text) => text.bodyMedium?.copyWith(color: AppColors.ink80, height: 1.3);

  /// How tall the number and the words are in [width], at the size of text on the phone, so that the four tiles can be given
  /// the height of the tallest.
  double heightAt(BuildContext context, double width) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final words = wordsStyle(text);
    Size measure(InlineSpan span) {
      final painter = TextPainter(text: span, textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final numberSize = measure(TextSpan(text: number, style: numberStyle(text)));
    var numberHeight = numberSize.height;
    if (total != null) {
      final totalSize = measure(TextSpan(text: total, style: words));
      if (numberSize.width + AppSpacing.xs + 2 + totalSize.width > width) numberHeight += totalSize.height;
    }
    final labelHeight = measure(
      TextSpan(
        text: label,
        style: words,
        children: [if (strong != null) TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w700))],
      ),
    ).height;
    return numberHeight + 2 + labelHeight;
  }
}

/// One tile. Its pictures are at the top and its number and words under them. All four tiles are given the same [height].
class _Tile extends StatelessWidget {
  const _Tile({required this.content, required this.height, required this.mediaHeight});

  final _Content content;
  final double height, mediaHeight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final words = _Content.wordsStyle(text);
    final total = content.total;
    return Semantics(
      label: '${content.number}${total == null ? '' : ' $total'} ${content.label}${content.strong ?? ''}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.all(DataSummary._padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: mediaHeight, width: double.infinity, child: ExcludeSemantics(child: content.media)),
                const SizedBox(height: DataSummary._leastGap),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpacing.xs + 2,
                  children: [
                    Text(content.number, style: _Content.numberStyle(text)),
                    if (total != null) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(total, style: words?.copyWith(color: AppColors.ink48))),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: content.label,
                    children: [
                      if (content.strong != null) TextSpan(text: content.strong, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    ],
                  ),
                  style: words,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small contact sheet: [columns] by [rows] slots, the first [filled] of them with a picture, where a slot whose picture
/// has not been read yet is a plain block, and the rest dashed and empty. [filled] is how many pictures there are to show,
/// so a library with more than the sheet holds fills it. A frame is [aspect] as high as it is wide. With
/// [play] set, each picture has a play badge, for videos.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.columns, required this.rows, required this.aspect, required this.pictures, required this.filled, this.play = false});

  final int columns, rows, filled;
  final double aspect;
  final List<Uint8List> pictures;
  final bool play;

  static const _gap = 3.0;

  /// How tall a sheet is in [width]: its frames are as wide as that allows, so the slots fill the width from edge to edge.
  static double heightFor(int columns, int rows, double aspect, double width) =>
      rows * (width - (columns - 1) * _gap) / columns * aspect + (rows - 1) * _gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - (columns - 1) * _gap) / columns;
        final size = Size(width, width * aspect);
        Widget slot(int i) => SizedBox.fromSize(
          size: size,
          child: i >= filled
              ? const _Dashed(radius: 4)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (i < pictures.length)
                        Image.memory(pictures[i], fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 120, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.hairline))
                      else
                        const ColoredBox(color: AppColors.hairline),
                      if (play && i < pictures.length) const Center(child: _PlayBadge()),
                    ],
                  ),
                ),
        );
        return Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: _gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c = 0; c < columns; c++) ...[if (c > 0) const SizedBox(width: _gap), slot(r * columns + c)],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.6), shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 15, child: Icon(Icons.play_arrow_rounded, size: 11, color: Colors.white)),
    );
  }
}

/// A rounded outline of dashes, for what is not there yet.
class _Dashed extends StatelessWidget {
  const _Dashed({required this.radius, this.circle = false});

  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DashedPainter(radius, circle), child: const SizedBox.expand());
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.radius, this.circle);

  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.75);
    final path = Path()..addRRect(circle ? RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)) : RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.ink48.withValues(alpha: 0.4);
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 6) {
        canvas.drawPath(metric.extractPath(at, math.min(at + 3, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.radius != radius || old.circle != circle;
}

/// The faces of the first few people found, side by side and overlapping. Where there are fewer than three, the rest are
/// dashed circles.
class _FacePile extends StatelessWidget {
  const _FacePile({required this.pictures});

  final List<Uint8List> pictures;

  static const _size = 46.0;
  static const _count = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final step = math.max(0.0, math.min(_size - 16, (box.maxWidth - _size) / (_count - 1)));
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _size + step * (_count - 1),
            height: _size,
            child: Stack(
              children: [
                for (var i = _count - 1; i >= 0; i--)
                  Positioned(
                    left: i * step,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.parchment),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: SizedBox.square(
                          dimension: _size - 6,
                          child: i < pictures.length
                              ? ClipOval(child: Image.memory(pictures[i], fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 120, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.hairline)))
                              : const _Dashed(radius: 0, circle: true),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The covers of a few collections fanned out in a pile, the middle one on top. Where there are fewer than three, the
/// rest are dashed cards.
class _Fan extends StatelessWidget {
  const _Fan({required this.pictures});

  final List<Uint8List> pictures;

  static const _card = Size(38, 46);

  /// How far the outer cards are from the left one, at the widest.
  static const _reach = 50.0;

  /// Where each card sits from the left, how far it turns, and which picture it takes: the left, the right and then the
  /// middle one, so the middle is drawn last and on top.
  static const _cards = [(0.0, -0.19, 1), (_reach, 0.19, 2), (_reach / 2, -0.03, 0)];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final spread = (box.maxWidth - _card.width).clamp(0.0, _reach) / _reach;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _card.width + _reach * spread,
            height: DataSummary._leastMedia,
            child: Stack(
              children: [
                for (final (left, turn, index) in _cards)
                  Positioned(
                    left: left * spread,
                    top: 7,
                    child: Transform.rotate(
                      angle: turn,
                      child: SizedBox.fromSize(
                        size: _card,
                        child: index < pictures.length
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: AppColors.parchment, width: 2.5),
                                  boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 1))],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4.5),
                                  child: Image.memory(pictures[index], fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 120, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.hairline)),
                                ),
                              )
                            : const _Dashed(radius: 7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
