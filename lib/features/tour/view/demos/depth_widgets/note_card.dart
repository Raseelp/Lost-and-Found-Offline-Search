part of '../depth_widgets.dart';

/// The daily memory: a photo from this day in an earlier year, with what it is.
class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/tour/photos/tajmahal.jpg',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              cacheWidth: 120,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'A memory from this day',
                    maxLines: 1,
                    style: _small(
                      context,
                      color: TourPalette.text,
                      weight: FontWeight.w700,
                      size: 10.5,
                    ),
                  ),
                ),
                Text(
                  '3 years ago',
                  maxLines: 1,
                  style: _small(context, size: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
