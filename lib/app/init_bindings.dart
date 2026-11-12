import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/media/grid_video_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/tour/controllers/tour_controller.dart';
import 'package:lost_and_found/features/home/controllers/home_controller.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';
import 'package:lost_and_found/features/search/controllers/search_controller.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';
import 'package:lost_and_found/features/settings/controllers/developer_note_controller.dart';
import 'package:lost_and_found/features/viewer/controllers/viewer_controller.dart';

class InitBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(HomeController());
    Get.put(AppSearchController());
    Get.put(ViewerController());
    Get.put(SettingsController());
    Get.put(ModelDownloadController());
    Get.put(LibraryController());
    Get.put(DeveloperNoteController(Get.find<LibraryController>()));
    Get.put(CollectionsController());
    Get.put(FacesController());
    Get.put(MemoriesController());
    Get.put(StoriesController());
    Get.put(GridVideoController(), permanent: true);
    Get.put(TourController());
  }
}
