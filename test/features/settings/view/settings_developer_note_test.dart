// The stand-in controllers skip the real onInit on purpose: it reads the phone, which a test does not have.
// ignore_for_file: must_call_super

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/media/grid_video_controller.dart';
import 'package:lost_and_found/core/widgets/new_tag.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/features/memories/features/stories/controllers/stories_controller.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/settings/controllers/developer_note_controller.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';
import 'package:lost_and_found/features/settings/view/settings_screen.dart';
import 'package:lost_and_found/features/update/controllers/update_controller.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';
import 'package:lost_and_found/features/update/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Models extends ModelDownloadController {
  @override
  void onInit() {}
}

class _Library extends LibraryController {
  @override
  void onInit() {}
}

class _Settings extends SettingsController {
  @override
  onInit() async {}
}

class _Collections extends CollectionsController {
  @override
  void onInit() {}
}

class _Memories extends MemoriesController {
  @override
  void onInit() {}
}

class _Faces extends FacesController {
  @override
  void onInit() {}
}

class _Stories extends StoriesController {
  @override
  void onInit() {}
}

class _Grid extends GridVideoController {
  @override
  void onInit() {}
}

class _UpdateService implements UpdateService {
  int starts = 0;

  @override
  Future<UpdateInfo> check() async => const UpdateInfo(stage: UpdateStage.available, versionCode: 7);

  @override
  Future<String> start() async {
    starts++;
    return 'accepted';
  }

  @override
  Future<void> complete() async {}

  @override
  Stream<UpdateEvent> get events => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lostandfound/native'), (call) async => null);
  });

  testWidgets('the About tile follows the unlock, and its dot goes after one visit', (tester) async {
    final library = Get.put<LibraryController>(_Library());
    Get.put<ModelDownloadController>(_Models());
    Get.put<SettingsController>(_Settings());
    Get.put<CollectionsController>(_Collections());
    Get.put<MemoriesController>(_Memories());
    Get.put<FacesController>(_Faces());
    Get.put<StoriesController>(_Stories());
    Get.put<GridVideoController>(_Grid());
    final note = Get.put(DeveloperNoteController(library));

    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Note from the developer'), findsNothing);
    expect(find.byType(NewTag), findsNothing);

    library.totalImages = DeveloperNoteController.unlockAt - 100;
    library.totalVideos = 100;
    library.update();
    await tester.pumpAndSettle();

    expect(find.text('Note from the developer'), findsOneWidget);
    expect(find.text('Report an issue'), findsNothing);
    expect(find.byType(NewTag), findsOneWidget);

    await tester.tap(find.text('Note from the developer'));
    await tester.pumpAndSettle();
    expect(note.showDot, isFalse);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.textContaining("Hi, I'm Raseel"), findsOneWidget);

    Navigator.of(tester.element(find.text('Report a problem'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(NewTag), findsNothing);
  });

  testWidgets('before the unlock the tile opens the short page', (tester) async {
    final library = Get.put<LibraryController>(_Library());
    Get.put<ModelDownloadController>(_Models());
    Get.put<SettingsController>(_Settings());
    Get.put<CollectionsController>(_Collections());
    Get.put<MemoriesController>(_Memories());
    Get.put<FacesController>(_Faces());
    Get.put<StoriesController>(_Stories());
    Get.put<GridVideoController>(_Grid());
    Get.put(DeveloperNoteController(library));

    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report an issue'));
    await tester.pumpAndSettle();

    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.textContaining("Hi, I'm Raseel"), findsNothing);
  });

  testWidgets('a waiting update is the top section of Settings, also after Not now', (tester) async {
    final library = Get.put<LibraryController>(_Library());
    Get.put<ModelDownloadController>(_Models());
    Get.put<SettingsController>(_Settings());
    Get.put<CollectionsController>(_Collections());
    Get.put<MemoriesController>(_Memories());
    Get.put<FacesController>(_Faces());
    Get.put<StoriesController>(_Stories());
    Get.put<GridVideoController>(_Grid());
    Get.put(DeveloperNoteController(library));
    final service = _UpdateService();
    final update = Get.put(UpdateController(service, firstCheckAfter: null));

    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    await update.check();
    await update.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('A new version of Lost & Found is ready'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Update available')).dy, lessThan(tester.getTopLeft(find.text('MODELS')).dy));

    await tester.tap(find.text('Update available'));
    await tester.pumpAndSettle();
    expect(service.starts, 1);
    expect(find.text('Downloading the update'), findsOneWidget);
  });
}
