import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/media_view_route.dart';
import 'package:lost_and_found/view/image_full_screen.dart';
import 'package:lost_and_found/view/video_full_screen.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

/// Opens [photo] in the viewer for its kind, from the small picture [loader] already has (so it opens
/// at once and sharpens as the full photo loads).
Future<void> openMemoryPhoto(
  BuildContext context,
  PreviewLoader loader,
  PreviewPhoto photo,
) async {
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  final native = Get.find<NativeController>();
  final bytes =
      loader.peek(photo, large: true, sharp: true) ??
      loader.peek(photo, large: true) ??
      loader.peek(photo, large: false) ??
      await loader.get(photo, large: false);
  if (bytes == null || !context.mounted) return;
  unawaited(native.loadMetaDataByUri(uri: photo.uri, isVideo: photo.isVideo));
  if (photo.isVideo) {
    Navigator.of(context).push(
      mediaViewRoute(
        (_) => VideoViewScreen(
          videoUri: photo.uri,
          timestampMs: photo.tsMs,
          thumbnailBytes: bytes,
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      mediaViewRoute(
        (_) => ImageViewScreen(
          imageBytes: bytes,
          uri: photo.uri,
          loadFullRes: true,
        ),
      ),
    );
  }
}

/// One photo or video of a memory: its picture (sharp when [large]), a play mark on a video.
class MemoryTile extends StatelessWidget {
  const MemoryTile({
    super.key,
    required this.photo,
    required this.loader,
    this.large = false,
    this.sharp = false,
    this.radius = 14,
    this.onTap,
    this.overlay,
  });

  final PreviewPhoto photo;
  final PreviewLoader loader;
  final bool large;

  /// Shown big enough that the large version is not sharp: the biggest one is fetched and faded in too.
  final bool sharp;
  final double radius;
  final VoidCallback? onTap;

  /// Something laid over the picture (the "+12" of a tile that stands for more).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PreviewImage(
              photo: photo,
              loader: loader,
              large: large,
              sharp: sharp,
              fill: AppColors.parchment,
              alignment: const Alignment(0, -0.25),
            ),
            if (photo.isVideo)
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 20,
                  color: AppColors.onMedia,
                ),
              ),
            if (overlay != null) Positioned.fill(child: overlay!),
          ],
        ),
      ),
    );
  }
}
