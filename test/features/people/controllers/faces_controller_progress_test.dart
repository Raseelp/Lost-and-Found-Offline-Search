// The stand-in controller skips the real onInit on purpose: it opens channels, which a test does not have.
// ignore_for_file: must_call_super

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';

class _Faces extends FacesController {
  @override
  void onInit() {}
}

void main() {
  late _Faces faces;

  setUp(() {
    Get.reset();
    faces = Get.put<FacesController>(_Faces()) as _Faces;
  });

  tearDown(Get.reset);

  test('nothing is shown while the face scan is not running', () {
    faces.status = FaceStatus();
    expect(faces.showsProgress, isFalse);
  });

  test('a scan that is catching up on its own shows its progress', () {
    faces.status = FaceStatus(running: true, following: false);
    expect(faces.showsProgress, isTrue);
  });

  test('a scan that follows an indexing scan is shown on the Library, not here', () {
    faces.status = FaceStatus(running: true, following: true);
    expect(faces.showsProgress, isFalse);
  });

  test('after Update people the progress shows', () {
    faces.syncing = true;
    faces.status = FaceStatus(running: true, following: true);
    expect(faces.showsProgress, isTrue);
  });

  test('a scan the person stopped, or that failed, shows no progress', () {
    faces.status = FaceStatus(running: true, userPaused: true);
    expect(faces.showsProgress, isFalse);

    faces.status = FaceStatus(running: true, error: 'no_model');
    expect(faces.showsProgress, isFalse);
  });
}
