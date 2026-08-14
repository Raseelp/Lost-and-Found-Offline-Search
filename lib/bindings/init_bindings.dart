import 'package:get/get.dart';
import 'package:twentyonevision/controllers/native_controller.dart';

class InitBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(NativeController());
  }
}
