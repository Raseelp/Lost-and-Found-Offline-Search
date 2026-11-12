import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/update/controllers/update_controller.dart';
import 'package:lost_and_found/features/update/models/update_info.dart';
import 'package:lost_and_found/features/update/services/update_service.dart';

class _FakeService implements UpdateService {
  UpdateInfo info = const UpdateInfo();
  Object? checkError;
  String startAnswer = 'accepted';
  int checks = 0;
  int completes = 0;
  int starts = 0;
  Completer<String>? gate;
  final stream = StreamController<UpdateEvent>.broadcast();

  @override
  Future<UpdateInfo> check() async {
    checks++;
    final error = checkError;
    if (error != null) throw error;
    return info;
  }

  @override
  Future<String> start() async {
    starts++;
    return gate?.future ?? startAnswer;
  }

  @override
  Future<void> complete() async => completes++;

  @override
  Stream<UpdateEvent> get events => stream.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeService service;
  late UpdateController update;

  Future<void> start() async {
    service = _FakeService();
    update = UpdateController(service, firstCheckAfter: null)..onInit();
    await pumpEventQueue();
  }

  tearDown(() {
    update.onClose();
    service.stream.close();
  });

  const waiting = UpdateInfo(stage: UpdateStage.available, versionCode: 7);

  test('there is nothing to show when no update is waiting', () async {
    await start();
    await update.check();
    expect(update.stage, UpdateStage.none);
    expect(update.visible, isFalse);
  });

  test('a waiting update is shown', () async {
    await start();
    service.info = waiting;
    await update.check();
    expect(update.stage, UpdateStage.available);
    expect(update.visible, isTrue);
  });

  test('a check that fails shows nothing', () async {
    await start();
    service.checkError = StateError('no Play');
    await update.check();
    expect(update.visible, isFalse);
  });

  test('not now hides the card for the rest of the session', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.dismiss();
    expect(update.visible, isFalse);

    await update.check();
    expect(update.visible, isFalse);
  });

  test('the card is back the next time the app is opened', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.dismiss();
    update.onClose();

    await start();
    service.info = waiting;
    await update.check();
    expect(update.visible, isTrue);
  });

  test('a newer version in the same session is shown again', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.dismiss();

    service.info = const UpdateInfo(stage: UpdateStage.available, versionCode: 8);
    await update.check();
    expect(update.visible, isTrue);
  });

  test('saying yes puts the update on its way', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.accept();
    expect(update.stage, UpdateStage.downloading);
    expect(update.visible, isTrue);
  });

  test('saying no in Google Play counts as not now', () async {
    await start();
    service.info = waiting;
    await update.check();
    service.startAnswer = 'declined';
    await update.accept();
    expect(update.visible, isFalse);
  });

  test('an update that cannot be started stays on offer', () async {
    await start();
    service.info = waiting;
    await update.check();
    service.startAnswer = 'failed';
    await update.accept();
    expect(update.stage, UpdateStage.available);
    expect(update.visible, isTrue);
  });

  test('the download is followed until the update is ready, and restart installs it', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.accept();

    service.stream.add(const UpdateEvent('downloading', progress: 0.4));
    await pumpEventQueue();
    expect(update.stage, UpdateStage.downloading);
    expect(update.progress, 0.4);

    service.stream.add(const UpdateEvent('downloaded'));
    await pumpEventQueue();
    expect(update.stage, UpdateStage.downloaded);
    expect(update.visible, isTrue);

    await update.restart();
    expect(service.completes, 1);
  });

  test('a download that fails goes back to what Google Play says', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.accept();
    final before = service.checks;

    service.stream.add(const UpdateEvent('failed'));
    await pumpEventQueue();
    expect(service.checks, before + 1);
    expect(update.stage, UpdateStage.available);
  });

  test('an update that is downloaded is shown even after not now', () async {
    await start();
    service.info = waiting;
    await update.check();
    await update.dismiss();

    service.info = const UpdateInfo(stage: UpdateStage.downloaded, versionCode: 7);
    await update.check();
    expect(update.visible, isTrue);
  });

  test('tapping Update twice starts the update once', () async {
    await start();
    service.info = waiting;
    await update.check();
    service.gate = Completer<String>();
    final first = update.accept();
    final second = update.accept();
    service.gate!.complete('accepted');
    await Future.wait([first, second]);
    expect(service.starts, 1);
    expect(update.stage, UpdateStage.downloading);
  });
}
