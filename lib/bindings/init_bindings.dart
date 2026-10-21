import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/controllers/tour_controller.dart';

class InitBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(NativeController());
    Get.put(CollectionsController());
    Get.put(FacesController());
    Get.put(MemoriesController());
    Get.put(TourController());
  }
}
