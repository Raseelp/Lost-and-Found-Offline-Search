import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/update/controllers/update_controller.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';
import 'package:lost_and_found/features/update/services/update_service.dart';
import 'package:lost_and_found/features/update/view/update_banner.dart';

class _FakeService implements UpdateService {
  UpdateInfo info = const UpdateInfo();
  String startAnswer = 'accepted';
  int completes = 0;
  final stream = StreamController<UpdateEvent>.broadcast();

  @override
  Future<UpdateInfo> check() async => info;

  @override
  Future<String> start() async => startAnswer;

  @override
  Future<void> complete() async => completes++;

  @override
  Stream<UpdateEvent> get events => stream.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeService service;
  late UpdateController update;

  setUp(() {
    Get.reset();
    service = _FakeService();
    update = Get.put(UpdateController(service, firstCheckAfter: null));
  });

  tearDown(() async {
    Get.reset();
    await service.stream.close();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const Scaffold(body: UpdateBanner()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing shows while there is no update', (tester) async {
    await show(tester);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('an update on offer has Update and Not now', (tester) async {
    service.info = const UpdateInfo(stage: UpdateStage.available, versionCode: 7);
    await show(tester);
    await update.check();
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('A new version of Lost & Found is ready.'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('Update starts the download, which shows a progress line and no buttons', (tester) async {
    service.info = const UpdateInfo(stage: UpdateStage.available, versionCode: 7);
    await show(tester);
    await update.check();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Downloading the update'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('a downloaded update asks to restart', (tester) async {
    service.info = const UpdateInfo(stage: UpdateStage.downloaded, versionCode: 7);
    await show(tester);
    await update.check();
    await tester.pumpAndSettle();

    expect(find.text('Update ready'), findsOneWidget);
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(service.completes, 1);
  });

  testWidgets('the card fits a narrow screen at double text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    service.info = const UpdateInfo(stage: UpdateStage.available, versionCode: 7);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: UpdateBanner()),
      ),
    );
    await update.check();
    await tester.pumpAndSettle();
    expect(find.text('Update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
