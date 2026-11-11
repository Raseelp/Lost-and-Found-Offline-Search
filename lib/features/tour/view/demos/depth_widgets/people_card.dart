part of '../depth_widgets.dart';

class _PeopleCard extends StatelessWidget {
  const _PeopleCard();

  static const _faces = ['messi', 'sam', 'leo'];

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26 + 2 * 12.0,
            height: 26,
            child: Stack(
              children: [
                for (var i = 0; i < _faces.length; i++)
                  Positioned(
                    left: i * 12.0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: TourPalette.white, width: 2),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/tour/faces/${_faces[i]}.jpg',
                          fit: BoxFit.cover,
                          cacheWidth: 80,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Leo and 57 others',
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
                  '248 photos',
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
