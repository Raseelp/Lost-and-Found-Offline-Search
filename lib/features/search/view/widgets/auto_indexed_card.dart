import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/media/media_view_route.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
import 'package:lost_and_found/features/viewer/controllers/viewer_controller.dart';
import 'package:lost_and_found/features/viewer/view/image_full_screen.dart';
import 'package:lost_and_found/features/viewer/view/video_full_screen.dart';

/// Tells the person that new photos and videos were indexed by themselves, with a few of them. It sits under the search
/// bar and the story rings for as long as the app stays open (see LibraryController.autoIndexed), searching or not, and
/// is not there when nothing was indexed. A tap on a picture opens it in the viewer.
class AutoIndexedCard extends StatefulWidget {
  const AutoIndexedCard({super.key, required this.batch});

  final AutoIndexedBatch batch;

  /// The most pictures the card shows. A narrow phone shows fewer, so that each is still big enough to tap. When there
  /// are more files than are shown, the last picture says how many more.
  static const slots = 5;

  /// The smallest a picture may be, which is what Android advises for something to tap.
  static const _minTile = 48.0;

  /// "3 new photos are ready to search.", "1 new video is ready to search.", "12 new photos and 2 videos are ready to
  /// search."
  static String sentence(AutoIndexedBatch batch) {
    final photos = batch.photos, videos = batch.videos;
    final photoWord = photos == 1 ? 'photo' : 'photos';
    final videoWord = videos == 1 ? 'video' : 'videos';
    final what = photos > 0 && videos > 0
        ? '${_number(photos)} new $photoWord and ${_number(videos)} $videoWord'
        : photos > 0
        ? '${_number(photos)} new $photoWord'
        : '${_number(videos)} new $videoWord';
    return '$what ${batch.count == 1 ? 'is' : 'are'} ready to search.';
  }

  static String _number(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  State<AutoIndexedCard> createState() => _AutoIndexedCardState();
}

class _AutoIndexedCardState extends State<AutoIndexedCard> {
  final Map<String, Uint8List> _pictures = {};

  /// The pictures being read, and the ones that could not be, so a rebuild of the page does not ask for one twice.
  final Set<String> _reading = {};
  final Set<String> _failed = {};

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(AutoIndexedCard old) {
    super.didUpdateWidget(old);
    _read();
  }

  /// The items that may be shown, which are the first few the batch holds. How many of them are shown depends on the
  /// width.
  List<({String uri, bool video})> get _shown =>
      widget.batch.items.take(AutoIndexedCard.slots).toList();

  /// Opens the picture in the viewer, which starts from the small picture and loads the sharp one itself.
  void _open(({String uri, bool video}) item, Uint8List bytes) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (Get.isRegistered<ViewerController>()) {
      unawaited(
        Get.find<ViewerController>().loadMetaDataByUri(
          uri: item.uri,
          isVideo: item.video,
        ),
      );
    }
    Navigator.of(context).push(
      mediaViewRoute(
        (_) => item.video
            ? VideoViewScreen(
                videoUri: item.uri,
                timestampMs: 0,
                thumbnailBytes: bytes,
              )
            : ImageViewScreen(
                imageBytes: bytes,
                uri: item.uri,
                loadFullRes: true,
              ),
      ),
    );
  }

  /// Reads the pictures that are not read yet. One that cannot be read leaves its slot grey and is not asked for again.
  Future<void> _read() async {
    final media = MediaService();
    for (final item in _shown) {
      if (_pictures.containsKey(item.uri) ||
          _failed.contains(item.uri) ||
          !_reading.add(item.uri)) {
        continue;
      }
      try {
        final bytes = await media.loadThumbnail(
          uri: item.uri,
          isVideo: item.video,
          size: 160,
        );
        if (!mounted) return;
        setState(() => _pictures[item.uri] = bytes);
      } catch (_) {
        _failed.add(item.uri);
      } finally {
        _reading.remove(item.uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final batch = widget.batch;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'New media found and indexed automatically',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AutoIndexedCard.sentence(batch),
                style: text.bodySmall?.copyWith(
                  color: AppColors.ink80,
                  height: 1.4,
                ),
              ),
              if (_shown.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _pictureRow(batch),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The pictures in one row, all the same size, so the row looks alike. When the batch is bigger than what is shown,
  /// the last picture is dimmed and says how many more there are.
  Widget _pictureRow(AutoIndexedBatch batch) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = AppSpacing.sm;
        final fit = ((box.maxWidth + gap) / (AutoIndexedCard._minTile + gap))
            .floor();
        final slots = fit.clamp(1, AutoIndexedCard.slots);
        final side = (box.maxWidth - gap * (slots - 1)) / slots;
        final shown = _shown.take(slots).toList();
        final more = batch.count - shown.length;
        return Row(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              _tile(
                shown[i],
                side,
                i == shown.length - 1 && more > 0 ? more : 0,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(({String uri, bool video}) item, double side, int more) {
    final bytes = _pictures[item.uri];
    final label =
        '${item.video ? 'Open video' : 'Open photo'}${more > 0 ? ', $more more not shown' : ''}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bytes == null ? null : () => _open(item, bytes),
        child: SizedBox(
          width: side,
          height: side,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.hairline),
                AnimatedSwitcher(
                  duration: calm(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: bytes == null
                      ? const SizedBox.shrink()
                      : Image.memory(
                          bytes,
                          key: ValueKey(item.uri),
                          width: side,
                          height: side,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                        ),
                ),
                if (item.video && more == 0)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                if (more > 0)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '+${AutoIndexedCard._number(more)}',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
