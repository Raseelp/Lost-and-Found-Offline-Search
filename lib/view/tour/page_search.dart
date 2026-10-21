import 'package:flutter/material.dart';
import 'package:lost_and_found/view/tour/search_demo.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

/// Page 2: the search. A query is typed and the sample photos move into the order of how well they match.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.scope});

  final TourPageScope scope;

  @override
  Widget build(BuildContext context) {
    return TourPageFrame(
      title: 'Type what you remember. Get the photo or video.',
      emphasis: 'remember',
      subtitle:
          'Search every photo and video on your phone in plain words, without scrolling through the gallery.',
      child: TourSearchDemo(
        active: scope.active,
        height: 300,
        startWith: kMentionQuery,
      ),
    );
  }
}
