part of '../depth_widgets.dart';

/// "On this day": a photo from this date in an earlier year, with the date over it. The same size as the video.
class _DayCard extends StatelessWidget {
  const _DayCard();

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: TourPalette.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/tour/photos/houseboat.jpg',
              fit: BoxFit.cover,
              cacheWidth: 400,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.transparent,
                    TourPalette.text.withValues(alpha: 0.7),
                  ],
                  stops: const [0.35, 1],
                ),
              ),
            ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ON THIS DAY',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: TourPalette.white.withValues(alpha: 0.85),
                      weight: FontWeight.w700,
                      size: 8.5,
                    ).copyWith(letterSpacing: 1),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_months[now.month - 1]} ${now.day}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: TourPalette.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'From 3 years',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: TourPalette.white.withValues(alpha: 0.85),
                      size: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
