part of '../depth_widgets.dart';

/// A search with its results, as the results page lists them: the words that were typed, then the photos and
/// videos that match, the best one largest.
class _SearchResultsCard extends StatelessWidget {
  const _SearchResultsCard();

  Widget _tile(String asset, {bool video = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset, fit: BoxFit.cover, cacheWidth: 300),
        if (video)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: TourPalette.text.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 11,
                  color: TourPalette.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: TourPalette.white),
      ),
      child: Column(
        children: [
          Container(
            height: 24,
            decoration: BoxDecoration(
              color: TourPalette.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: TourPalette.mint900A10),
              boxShadow: const [
                BoxShadow(
                  color: TourPalette.mint900A8,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 3),
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: TourPalette.teal750A7,
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    size: 12,
                    color: TourPalette.teal,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'surfing at sunset',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _small(context, color: TourPalette.text, size: 10.5),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: TourPalette.teal,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 11,
                    color: TourPalette.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _tile('assets/tour/videos/v_surf.jpg', video: true),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(child: _tile('assets/tour/photos/kayak.jpg')),
                      const SizedBox(height: 4),
                      Expanded(child: _tile('assets/tour/photos/sunset.jpg')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
