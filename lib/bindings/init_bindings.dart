import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';

class InitBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(NativeController());
    Get.put(CollectionsController());
    Get.put(FacesController());
  }
}
