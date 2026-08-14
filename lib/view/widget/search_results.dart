import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:twentyonevision/controllers/native_controller.dart';
import 'package:twentyonevision/utils/app_colors.dart';
import 'package:twentyonevision/view/image_full_screen.dart';
import 'package:twentyonevision/view/video_full_screen.dart';

class SearchResultsView extends StatelessWidget {
  const SearchResultsView({super.key});

  @override
  Widget build(BuildContext context) {
    final NativeController nativeController = Get.find();
    return GetBuilder<NativeController>(
      init: nativeController,
      builder: (controller) {
        if (controller.isSearching) {
          return _ResultsShell(
            title: 'Results',
            badge: 'Searching',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
              decoration: _panelDecoration,
              child: const Column(
                children: [
                  CircularProgressIndicator(
                    color: AppColors.primarybuttonColor,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Finding the best semantic matches for you...',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.searchResults.isEmpty) {
          return _ResultsShell(
            title: 'Results',
            badge: 'Waiting',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: _panelDecoration,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAccent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: AppColors.primarybuttonColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Search results will appear here',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.totalEmbeddings == 0
                        ? 'Index a folder or your phone from the Home tab first, then come back to search.'
                        : 'Describe a photo, place, or moment above to see visually grouped matches.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return _ResultsShell(
          title: 'Results',
          badge: '${controller.searchResults.length} matches',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 1100
                  ? 4
                  : width >= 700
                  ? 3
                  : 2;
              final aspectRatio = width >= 700 ? 0.92 : 0.78;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: controller.searchResults.length,
                itemBuilder: (context, index) {
                  final item = controller.searchResults[index];
                  final uri = item['path'] as String;
                  final isVideo = item['isVideo'] as bool? ?? false;
                  final cacheKey = controller.cacheKeyForResult(item);
                  final bytes = controller.imageCache[cacheKey];
                  final timestampMs =
                      (item['timestampMs'] as num?)?.toInt() ?? 0;

                  if (bytes == null) {
                    return Container(
                      decoration: _panelDecoration,
                      child: const Center(
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    );
                  }

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () async {
                        if (isVideo) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoViewScreen(
                                videoUri: uri,
                                timestampMs: timestampMs,
                                thumbnailBytes: bytes,
                              ),
                            ),
                          );
                        } else {
                          controller.loadMetaDataByUri(uri: uri);
                          Get.to(() => ImageViewScreen(imageBytes: bytes));
                        }
                      },
                      child: Ink(
                        decoration: _panelDecoration,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(bytes, fit: BoxFit.cover),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.05),
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.54),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isVideo ? 'Video' : 'Image',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              if (index == 0)
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.accentGradient,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.star_rounded,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          'Best match',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.28,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    isVideo
                                        ? Icons.play_arrow_rounded
                                        : Icons.open_in_full_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

const BoxDecoration _panelDecoration = BoxDecoration(
  color: AppColors.surfaceColor,
  borderRadius: BorderRadius.all(Radius.circular(26)),
  boxShadow: [
    BoxShadow(
      color: AppColors.shadowColor,
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ],
);

class _ResultsShell extends StatelessWidget {
  const _ResultsShell({
    required this.title,
    required this.badge,
    required this.child,
  });

  final String title;
  final String badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}
