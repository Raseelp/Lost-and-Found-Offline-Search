import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/tour_controller.dart';
import 'package:lost_and_found/view/tour/page_compare.dart';
import 'package:lost_and_found/view/tour/page_people.dart';
import 'package:lost_and_found/view/tour/page_private.dart';
import 'package:lost_and_found/view/tour/page_search.dart';
import 'package:lost_and_found/view/tour/page_start.dart';
import 'package:lost_and_found/view/tour/tour_download.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';

/// The five pages of the introduction.
List<TourPage> introPages() => [
  TourPage((context, scope) => StartPage(scope: scope)),
  TourPage((context, scope) => SearchPage(scope: scope)),
  TourPage((context, scope) => PeoplePage(scope: scope)),
  TourPage((context, scope) => PrivatePage(scope: scope)),
  TourPage((context, scope) => ComparePage(scope: scope)),
];

/// The tour on a first run: in place of the download screen, it starts the real download with its first
/// button and shows how it is going on every page. Stays until finished (see [TourController]).
class FirstRunTour extends StatefulWidget {
  const FirstRunTour({super.key});

  @override
  State<FirstRunTour> createState() => _FirstRunTourState();
}

class _FirstRunTourState extends State<FirstRunTour> {
  final RealTourDownload _download = RealTourDownload();

  @override
  void dispose() {
    _download.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TourScreen(
      pages: introPages(),
      download: _download,
      onFinished: () => Get.find<TourController>().finish(),
    );
  }
}

/// Settings > Help: the same tour again, with a pretend download (nothing is fetched or kept), so it can be
/// seen without reinstalling the app.
Future<void> openHelpTour(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const _HelpTour()));
}

class _HelpTour extends StatefulWidget {
  const _HelpTour();

  @override
  State<_HelpTour> createState() => _HelpTourState();
}

class _HelpTourState extends State<_HelpTour> {
  final SimulatedTourDownload _download = SimulatedTourDownload();

  @override
  void dispose() {
    _download.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TourScreen(
      pages: introPages(),
      download: _download,
      mode: TourMode.help,
      // pop, not maybePop: maybePop asks the tour's own back handling first, which (away from the first page) only
      // turns the page back, so Close and Done would not leave.
      onFinished: () => Navigator.of(context).pop(),
    );
  }
}
