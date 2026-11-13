import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/settings/controllers/settings_controller.dart';

/// What auto indexing picks up is chosen in Settings, and is kept by the native side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('is photos and videos until it is changed', () {
    expect(SettingsController().autoIndexContent, 'both');
  });

  test('sends the choice to the native side and keeps it', () async {
    final sent = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setAutoIndexContent') sent.add((call.arguments as Map)['mode']);
      return null;
    });
    final settings = SettingsController();

    await settings.setAutoIndexContent('images');
    await settings.setAutoIndexContent('videos');

    expect(settings.autoIndexContent, 'videos');
    expect(sent, ['images', 'videos']);
  });

  test('does not send a choice that is already made', () async {
    var sent = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setAutoIndexContent') sent++;
      return null;
    });
    final settings = SettingsController();

    await settings.setAutoIndexContent('both');

    expect(sent, 0);
  });
}
