import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/media/grid_video_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/tour/controllers/tour_controller.dart';

class InitBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(NativeController());
    Get.put(CollectionsController());
    Get.put(FacesController());
    Get.put(MemoriesController());
    Get.put(StoriesController());
    Get.put(GridVideoController(), permanent: true);
    Get.put(TourController());
  }
}
