import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/collections/models/collection_model.dart';

/// Keeps what it is asked to save, because the saving itself needs the phone's database.
class _Capturing extends CollectionsController {
  final List<SmartCollection> saved = [];

  /// The real setup loads the saved collections, so it is skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> updateCollection(SmartCollection updated) async {
    saved.add(updated);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final original = SmartCollection(
    id: 'user_1',
    name: 'Like this',
    prompts: const ['photos like the one you saved'],
    contentMode: 'both',
    createdAt: 7,
    kind: SmartCollection.kindPhotos,
    seedEmbedding: const [0.1, 0.2],
    seedUri: 'content://media/1',
    seedModel: 'older-model',
  );

  tearDown(() {
    Get.reset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a new photo is embedded, made unit length, and saved with the new name and content', () async {
    final calls = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'encodeImage') {
        calls.add(call.arguments as Map<Object?, Object?>);
        return <double>[3, 4];
      }
      return null;
    });
    final controller = _Capturing();
    final read = await controller.changePhoto(original, uri: 'content://media/9', name: 'Mine', contentMode: 'videos');

    expect(read, isTrue);
    expect(calls.single['uri'], 'content://media/9');
    final saved = controller.saved.single;
    expect(saved.id, 'user_1');
    expect(saved.name, 'Mine');
    expect(saved.contentMode, 'videos');
    expect(saved.seedUri, 'content://media/9');
    expect(saved.seedEmbedding, [0.6, 0.8]);
    expect(saved.seedModel, CollectionsController.modelVersion);
    expect(saved.seedTimestampMs, isNull);
    expect(saved.isPhotos, isTrue);
    expect(saved.createdAt, 7);
    expect(saved.prompts, original.prompts);
  });

  test('a photo that gives nothing back keeps the old photo, and the name and content are still saved', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final controller = _Capturing();
    final read = await controller.changePhoto(original, uri: 'content://media/9', name: 'Mine', contentMode: 'images');

    expect(read, isFalse);
    final saved = controller.saved.single;
    expect(saved.name, 'Mine');
    expect(saved.contentMode, 'images');
    expect(saved.seedUri, 'content://media/1');
    expect(saved.seedEmbedding, [0.1, 0.2]);
    expect(saved.seedModel, 'older-model');
  });

  test('a photo that cannot be read at all is treated the same way', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'encodeImage') throw PlatformException(code: 'ERR', message: 'unreadable');
      return null;
    });
    final controller = _Capturing();
    final read = await controller.changePhoto(original, uri: 'content://media/9', name: 'Mine', contentMode: 'both');

    expect(read, isFalse);
    expect(controller.saved.single.seedUri, 'content://media/1');
    expect(controller.saved.single.name, 'Mine');
  });
}
