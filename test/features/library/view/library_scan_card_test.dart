// The stand-in controllers skip the real onInit on purpose: it reads the phone, which a test does not have.
// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';
import 'package:lost_and_found/features/library/models/scan_models.dart';
import 'package:lost_and_found/features/library/view/library_tab.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Library extends LibraryController {
  @override
  void onInit() {}
}

class _Faces extends FacesController {
  @override
  void onInit() {}
}

class _Settings extends SettingsController {
  @override
  onInit() async {}
}

IndexedFolder _folder({int total = 3800, int processed = 3800, int updatedAt = 1, String id = 'device'}) => IndexedFolder(
  id: id,
  total: total,
  embedded: processed,
  skipped: 0,
  elapsedMs: 1000,
  path: 'Phone',
  processed: processed,
  done: true,
  updatedAt: updatedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Library library;
  late _Faces faces;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lostandfound/native'), (call) async => null);
    library = Get.put<LibraryController>(_Library()) as _Library;
    faces = Get.put<FacesController>(_Faces()) as _Faces;
    Get.put<SettingsController>(_Settings());
  });

  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, {double textScale = 1, bool calm = false}) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: calm, textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: GetBuilder<LibraryController>(builder: (c) => LibraryTab(controller: c)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('before any scan the steps wait at 0 of 0 with a way to start one', (tester) async {
    await show(tester);

    expect(find.text('0 of 0'), findsOneWidget);
    expect(find.text('Start indexing'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await done(tester);
  });

  testWidgets('with one folder chosen the button says so', (tester) async {
    library.scanWholePhone = false;
    await show(tester);

    expect(find.text('Choose a folder'), findsOneWidget);
    expect(find.text('Start indexing'), findsNothing);
    await done(tester);
  });

  testWidgets('a running scan shows its progress and no button to start another', (tester) async {
    library.isScanning = true;
    library.scanResult = _folder(total: 1000, processed: 100);
    library.totalEmbeddings = 100;
    faces.status = FaceStatus(running: true, people: 3);
    await show(tester);

    expect(find.text('100 of 1,000'), findsOneWidget);
    expect(find.text('Start indexing'), findsNothing);
    expect(find.text('Continue indexing'), findsNothing);
    expect(find.text('Stop indexing'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await done(tester);
  });

  testWidgets('a scan that was stopped is held where it stopped, with a way to continue', (tester) async {
    library.scanResult = _folder(total: 1000, processed: 400);
    library.totalEmbeddings = 400;
    faces.status = FaceStatus(people: 3);
    await show(tester);

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('400 of 1,000 indexed.'), findsOneWidget);
    expect(find.text('400 read'), findsOneWidget);
    expect(find.text('Continue indexing'), findsOneWidget);
    await done(tester);
  });

  testWidgets('when the app is opened again the last scan shows from the saved record', (tester) async {
    library.allIndexedFoldersList = [_folder(total: 1000, processed: 400, updatedAt: 5), _folder(total: 50, processed: 50, updatedAt: 2, id: 'old')];
    library.totalEmbeddings = 400;
    faces.status = FaceStatus(people: 3);
    await show(tester);

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('400 of 1,000 indexed.'), findsOneWidget);
    expect(find.text('Continue indexing'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a finished scan keeps the steps with the final numbers and offers to index again', (tester) async {
    library.allIndexedFoldersList = [_folder()];
    library.totalEmbeddings = 3800;
    await show(tester);

    expect(find.text('3,800 of 3,800'), findsOneWidget);
    expect(find.textContaining('paused'), findsNothing);
    expect(find.text('Index again'), findsOneWidget);
    await done(tester);
  });

  testWidgets('when a scan finishes on screen the end plays once and the card settles', (tester) async {
    library.isScanning = true;
    library.scanResult = _folder(total: 1000, processed: 990);
    library.totalEmbeddings = 990;
    await show(tester);

    library.isScanning = false;
    library.scanResult = _folder(total: 1000, processed: 1000);
    library.scanSummary = const ScanSummary(total: 1000, failed: 0);
    library.totalEmbeddings = 1000;
    library.update();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Index again'), findsOneWidget);
    expect(find.text('1,000 of 1,000'), findsOneWidget);
    await done(tester);
  });

  testWidgets('the faces found so far show with the card, from the face scan', (tester) async {
    library.allIndexedFoldersList = [_folder()];
    faces.status = FaceStatus(people: 24);
    await show(tester);

    expect(find.text('24 found so far'), findsOneWidget);
    await done(tester);
  });

  testWidgets('the card fits a small phone at double text size in every state', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    library.isScanning = true;
    library.scanResult = _folder(total: 1000, processed: 100);
    faces.status = FaceStatus(running: true, batch: true, total: 60, processed: 20, people: 5);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: Scaffold(body: GetBuilder<LibraryController>(builder: (c) => LibraryTab(controller: c))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    await done(tester);
  });
}
