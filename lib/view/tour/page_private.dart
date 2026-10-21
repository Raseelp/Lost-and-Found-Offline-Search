import 'package:flutter/material.dart';
import 'package:lost_and_found/view/tour/embed_film.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

/// Page 4: how a search works. A short film that plays by itself (see [TourEmbedFilm]): the chip reads one photo,
/// the camera pulls back to all the photos read the same way, a search is typed and becomes numbers, the numbers are
/// compared with every photo's, and the closest photos come first. Nothing on it can be touched.
class PrivatePage extends StatelessWidget {
  const PrivatePage({super.key, required this.scope});

  final TourPageScope scope;

  // The least height the film is drawn in; with very large text there is hardly any room left under the title, and
  // the film then keeps its size and scrolls.
  static const double _leastFilm = 380;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TourPageFrame(
      fill: true,
      title: 'How a search really works.',
      emphasis: 'really',
      subtitle:
          'Every photo becomes a list of numbers. Your search becomes one too, and the nearest photos win.',
      child: LayoutBuilder(
        builder: (context, box) {
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FixedTextScale(
                  child: IgnorePointer(
                    child: TourEmbedFilm(active: scope.active, still: still),
                  ),
                ),
              ),
            ],
          );
          if (box.maxHeight >= _leastFilm) return body;
          return SingleChildScrollView(
            child: SizedBox(height: _leastFilm, child: body),
          );
        },
      ),
    );
  }
}
