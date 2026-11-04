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

/// The tour again, opened from Help in Settings, with no download (the models are already on the phone), so it can be
/// seen without reinstalling the app. Close and Done pop the route directly, because a maybePop would ask the tour's own
/// back handling first, which only turns the page back when the tour is not on its first page.
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
  final IdleTourDownload _download = IdleTourDownload();

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
      onFinished: () => Navigator.of(context).pop(),
    );
  }
}
