import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/models/collection_model.dart';

void main() {
  group('SmartCollection.withSeed', () {
    final original = SmartCollection(
      id: 'user_1',
      name: 'Like this',
      prompts: const ['photos like the one you saved'],
      contentMode: 'images',
      sensitivity: 2.8,
      createdAt: 5,
      kind: SmartCollection.kindPhotos,
      seedEmbedding: const [0.1, 0.2],
      seedUri: 'content://media/1',
      seedTimestampMs: 4000,
      seedModel: 'old',
      personIds: const [3],
    );

    test('a collection looks like the new photo and nothing else about it changes', () {
      final changed = original.withSeed(uri: 'content://media/9', embedding: const [0.7, 0.3], model: 'new');
      expect(changed.seedUri, 'content://media/9');
      expect(changed.seedEmbedding, [0.7, 0.3]);
      expect(changed.seedModel, 'new');
      expect(changed.seedTimestampMs, isNull, reason: 'a picture has no moment');
      expect(changed.id, original.id);
      expect(changed.name, original.name);
      expect(changed.prompts, original.prompts);
      expect(changed.contentMode, 'images');
      expect(changed.sensitivity, 2.8);
      expect(changed.createdAt, 5);
      expect(changed.isPhotos, isTrue);
      expect(changed.personIds, [3]);
    });

    test('the moment of a video frame is kept when it is given', () {
      final changed = original.withSeed(uri: 'content://media/9', timestampMs: 1500, embedding: const [1.0], model: 'new');
      expect(changed.seedTimestampMs, 1500);
    });

    test('the new photo is what is saved and read back', () {
      final changed = original.withSeed(uri: 'content://media/9', embedding: const [0.7, 0.3], model: 'new');
      final back = SmartCollection.fromRow(changed.toRow());
      expect(back.seedUri, 'content://media/9');
      expect(back.seedEmbedding, [0.7, 0.3]);
      expect(back.seedModel, 'new');
      expect(back.isPhotos, isTrue);
    });

    test('a name and what is included can change along with the photo', () {
      final changed = original
          .copyWith(name: 'Other', contentMode: 'videos')
          .withSeed(uri: 'content://media/9', embedding: const [0.5], model: 'new');
      expect(changed.name, 'Other');
      expect(changed.contentMode, 'videos');
      expect(changed.seedUri, 'content://media/9');
    });
  });
}
