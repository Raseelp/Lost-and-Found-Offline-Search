import 'package:get/get.dart';

class HomeController extends GetxController {
  /// Which home tab is showing: 0 Search, 1 Collections, 2 Library. It lives here and not in the state of the home
  /// screen, so that something opened from another tab, such as a photo inside a collection, can send the person to
  /// Search.
  int homeTab = 0;

  void setHomeTab(int index) {
    if (homeTab == index) return;
    homeTab = index;
    update();
  }
}
