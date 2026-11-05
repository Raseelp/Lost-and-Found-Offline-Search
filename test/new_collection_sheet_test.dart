import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/view/widget/new_collection_sheet.dart';

/// The people the fake library knows.
final _maya = Person(id: 1, name: 'Maya', hidden: false, faceCount: 40, photoCount: 38, coverFaceId: 11);
final _anna = Person(id: 2, name: 'Anna', hidden: false, faceCount: 22, photoCount: 21, coverFaceId: 12);

class _FakeFaces extends FacesController {
  /// The real setup starts a face scan and calls the phone, so it is skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {
    people = [_maya, _anna];
  }
}

class _FakeNative extends NativeController {
  /// The real setup loads from the phone, so it is skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Answers the preview with a fixed library, and records what is saved.
class _FakeCollections extends CollectionsController {
  final List<Map<String, Object?>> previews = [];
  final List<Map<String, Object?>> created = [];
  final List<SmartCollection> updated = [];
  final List<Map<String, Object?>> photoChanges = [];

  /// The real setup loads the saved collections, so it is skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<CollectionPreview?> previewCollection({
    List<String> prompts = const [],
    String? seedUri,
    int? seedTimestampMs,
    String contentMode = 'both',
    List<int> personIds = const [],
    double sensitivity = SmartCollection.defaultSensitivity,
    int shown = 5,
  }) async {
    previews.add({
      'prompts': prompts,
      'contentMode': contentMode,
      'personIds': personIds,
      'sensitivity': sensitivity,
      'seedUri': seedUri,
    });
    return const CollectionPreview(
      count: 142,
      items: [],
      people: [(personId: 1, count: 38), (personId: 2, count: 21), (personId: 99, count: 3)],
    );
  }

  @override
  Future<void> updateCollection(SmartCollection collection) async {
    updated.add(collection);
  }

  @override
  Future<bool> changePhoto(
    SmartCollection collection, {
    required String uri,
    required String name,
    required String contentMode,
  }) async {
    photoChanges.add({'id': collection.id, 'uri': uri, 'name': name, 'contentMode': contentMode});
    return true;
  }

  @override
  Future<SmartCollection> createCollection({
    required String name,
    required String query,
    String contentMode = 'both',
    List<int> personIds = const [],
    List<String> morePrompts = const [],
  }) async {
    created.add({
      'name': name,
      'query': query,
      'contentMode': contentMode,
      'personIds': personIds,
      'morePrompts': morePrompts,
    });
    return SmartCollection(id: 'x', name: name, prompts: [query]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('labels', () {
    test('how many items, by what is included', () {
      expect(countLabel(142, 'both'), '142 photos and videos');
      expect(countLabel(1, 'both'), '1 photo or video');
      expect(countLabel(9, 'images'), '9 photos');
      expect(countLabel(1, 'videos'), '1 video');
    });

    test('who is in the matches', () {
      expect(peopleLine(['Maya']), 'With Maya');
      expect(peopleLine(['Maya', 'Anna']), 'With Maya and Anna');
      expect(peopleLine(['Maya', 'Anna', 'Rose']), 'With Maya, Anna and Rose');
      expect(peopleLine(['Maya', 'Anna', 'Rose', 'Lia', null]), 'With Maya, Anna, Rose and 2 others');
      expect(peopleLine(['Maya', null]), 'With Maya and 1 other');
      expect(peopleLine([null, null, null]), 'With 3 people');
      expect(peopleLine([null]), 'With 1 person');
    });
  });

  group('the sheet', () {
    late _FakeCollections collections;

    setUp(() {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      Get.put<FacesController>(_FakeFaces());
      Get.put<NativeController>(_FakeNative()..totalEmbeddings = 5000);
      collections = _FakeCollections();
    });

    tearDown(() {
      Get.reset();
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNewCollectionSheet(context, collections),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers ideas and a photo before anything is typed, and cannot be saved yet', (tester) async {
      await open(tester);
      expect(find.text('TRY ONE'), findsOneWidget);
      expect(find.text('Sunsets'), findsOneWidget);
      expect(find.text('Maya at the beach'), findsOneWidget);
      expect(find.text('Start from a photo'), findsOneWidget);
      expect(find.text('NAME'), findsNothing);

      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(collections.created, isEmpty);
      expect(find.text('New collection'), findsOneWidget, reason: 'still open');
    });

    testWidgets('an idea fills the words and the name, and shows what it finds and who is in it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump();
      expect(find.text('TRY ONE'), findsNothing);
      expect(find.widgetWithText(TextField, 'Sunsets'), findsNWidgets(2), reason: 'the words and the name');

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('142 photos and videos'), findsOneWidget);
      expect(find.text('With Maya and Anna'), findsOneWidget);
    });

    testWidgets('choosing images previews again and is saved with the words', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Images'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(collections.previews.last['contentMode'], 'images');
      expect(find.text('142 photos'), findsOneWidget);

      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(collections.created, [
        {'name': 'Sunsets', 'query': 'Sunsets', 'contentMode': 'images', 'personIds': <int>[], 'morePrompts': <String>[]},
      ]);
      expect(find.text('New collection'), findsNothing, reason: 'closed');
    });

    testWidgets('other ways of saying it are previewed and saved', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump();
      await tester.tap(find.text('+ Add'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'e.g. "coast"'), 'golden hour');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('golden hour'), findsOneWidget);
      expect(collections.previews.last['prompts'], ['Sunsets', 'golden hour']);

      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(collections.created.single['morePrompts'], ['golden hour']);
    });

    testWidgets('an emptied name is saved as the suggested one', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Sunsets').last, '');
      await tester.pump();
      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(collections.created.single['name'], 'Sunsets');
    });

    testWidgets('a phrase still being typed is kept when saving', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump();
      await tester.tap(find.text('+ Add'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'e.g. "coast"'), 'dusk');
      await tester.pump();
      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(collections.created.single['morePrompts'], ['dusk']);
    });

    testWidgets('a name typed over the suggested one is kept', (tester) async {
      await open(tester);
      await tester.tap(find.text('Sunsets'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Sunsets').last, 'Evenings');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'beach');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Evenings'), findsOneWidget);
    });

    Future<void> openEdit(WidgetTester tester, SmartCollection collection) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showCollectionSheet(context, collections, editing: collection),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    Future<void> saveChanges(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
    }

    final mine = SmartCollection(
      id: 'user_1',
      name: 'Evenings',
      prompts: const ['sunsets', 'golden hour'],
      contentMode: 'images',
      createdAt: 1,
    );

    final beach = SmartCollection(
      id: 'builtin_beach',
      name: 'Beach',
      prompts: const ['a beach', 'sand and sea', 'waves'],
      sensitivity: 2.8,
      isBuiltIn: true,
    );

    group('editing', () {
      testWidgets('a collection you made opens filled in, with what it finds', (tester) async {
        await openEdit(tester, mine);
        expect(find.text('Edit collection'), findsOneWidget);
        expect(find.text('New collection'), findsNothing);
        expect(find.text('TRY ONE'), findsNothing);
        expect(find.text('Start from a photo'), findsNothing);
        expect(find.widgetWithText(TextField, 'sunsets'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Evenings'), findsOneWidget);
        expect(find.text('golden hour'), findsOneWidget);
        expect(find.text('Save changes'), findsOneWidget);
        expect(find.text('Save collection'), findsNothing);
        expect(collections.previews.last['prompts'], ['sunsets', 'golden hour']);
        expect(collections.previews.last['contentMode'], 'images');
        expect(find.text('142 photos'), findsOneWidget);
      });

      testWidgets('a new name alone changes only the name', (tester) async {
        await openEdit(tester, mine);
        await tester.enterText(find.widgetWithText(TextField, 'Evenings'), 'Nights');
        await tester.pump();
        await saveChanges(tester);
        final saved = collections.updated.single;
        expect(saved.name, 'Nights');
        expect(saved.prompts, ['sunsets', 'golden hour']);
        expect(saved.contentMode, 'images');
        expect(saved.personIds, isEmpty);
        expect(find.text('Edit collection'), findsNothing, reason: 'closed');
      });

      testWidgets('what is included can be changed and is previewed again', (tester) async {
        await openEdit(tester, mine);
        await tester.tap(find.text('Videos'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(collections.previews.last['contentMode'], 'videos');
        await saveChanges(tester);
        expect(collections.updated.single.contentMode, 'videos');
      });

      testWidgets('the words and other ways of saying it can be changed', (tester) async {
        await openEdit(tester, mine);
        await tester.enterText(find.widgetWithText(TextField, 'sunsets'), 'dusk');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove golden hour'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(collections.previews.last['prompts'], ['dusk']);
        await saveChanges(tester);
        expect(collections.updated.single.prompts, ['dusk']);
      });

      testWidgets('a person it filters by is put back in the words and kept when saving', (tester) async {
        final withMaya = SmartCollection(id: 'user_2', name: 'Maya outdoors', prompts: const ['sunsets'], personIds: const [1]);
        await openEdit(tester, withMaya);
        expect(find.widgetWithText(TextField, 'Maya sunsets'), findsOneWidget);
        expect(collections.previews.last['prompts'], ['sunsets']);
        expect(collections.previews.last['personIds'], [1]);
        await saveChanges(tester);
        expect(collections.updated.single.personIds, [1]);
        expect(collections.updated.single.prompts, ['sunsets']);
      });

      testWidgets('a collection of people only shows only their names, and saves the same phrase', (tester) async {
        final onlyMaya = SmartCollection(id: 'user_3', name: 'Maya', prompts: const ['a photo'], personIds: const [1]);
        await openEdit(tester, onlyMaya);
        expect(find.widgetWithText(TextField, 'Maya'), findsNWidgets(2), reason: 'the words and the name');
        await saveChanges(tester);
        expect(collections.updated.single.prompts, ['a photo']);
        expect(collections.updated.single.personIds, [1]);
      });

      testWidgets('a person who has no name cannot be typed again, so saving keeps them', (tester) async {
        final withUnnamed = SmartCollection(id: 'user_4', name: 'Someone', prompts: const ['sunsets'], personIds: const [7]);
        await openEdit(tester, withUnnamed);
        expect(collections.previews.last['personIds'], [7]);
        await saveChanges(tester);
        expect(collections.updated.single.personIds, [7]);
      });

      testWidgets('a built-in shows its short phrase, is previewed as it really is, and keeps its phrasings', (tester) async {
        await openEdit(tester, beach);
        expect(find.widgetWithText(TextField, 'a beach'), findsOneWidget);
        expect(find.text('sand and sea'), findsNothing);
        expect(collections.previews.last['prompts'], ['a beach', 'sand and sea', 'waves']);
        expect(collections.previews.last['sensitivity'], 2.8);
        await tester.enterText(find.widgetWithText(TextField, 'Beach'), 'Seaside');
        await tester.pump();
        await saveChanges(tester);
        final saved = collections.updated.single;
        expect(saved.name, 'Seaside');
        expect(saved.prompts, ['a beach', 'sand and sea', 'waves']);
        expect(saved.sensitivity, 2.8);
        expect(saved.isBuiltIn, isTrue);
      });

      testWidgets('a built-in whose words are changed gets the new words', (tester) async {
        await openEdit(tester, beach);
        await tester.enterText(find.widgetWithText(TextField, 'a beach'), 'coast');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(collections.previews.last['prompts'], ['coast']);
        await saveChanges(tester);
        expect(collections.updated.single.prompts, ['coast']);
      });

      testWidgets('a phrase added to a built-in comes after its own', (tester) async {
        await openEdit(tester, beach);
        await tester.tap(find.text('+ Add'));
        await tester.pump();
        await tester.enterText(find.widgetWithText(TextField, 'e.g. "coast"'), 'surf');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        await saveChanges(tester);
        expect(collections.updated.single.prompts, ['a beach', 'sand and sea', 'waves', 'surf']);
      });

      testWidgets('a photo collection keeps its photo and can change its name and what it includes', (tester) async {
        final photos = SmartCollection(
          id: 'user_5',
          name: 'Like this',
          prompts: const ['photos like the one you saved'],
          kind: SmartCollection.kindPhotos,
          seedUri: 'content://media/1',
          seedEmbedding: const [0.1, 0.2],
        );
        await openEdit(tester, photos);
        expect(find.text('Photos that look like this'), findsOneWidget);
        expect(find.byTooltip('Describe in words instead'), findsNothing);
        expect(find.byTooltip('Choose another photo'), findsOneWidget);
        expect(find.text('Describe what to find'), findsNothing);
        expect(find.text('INCLUDE'), findsOneWidget);
        expect(find.text('NAME'), findsOneWidget);
        expect(collections.previews, isEmpty);
        await tester.enterText(find.widgetWithText(TextField, 'Like this'), 'Mine');
        await tester.tap(find.text('Images'));
        await tester.pump();
        await saveChanges(tester);
        final saved = collections.updated.single;
        expect(saved.name, 'Mine');
        expect(saved.contentMode, 'images');
        expect(saved.isPhotos, isTrue);
        expect(saved.prompts, ['photos like the one you saved']);
        expect(saved.seedEmbedding, [0.1, 0.2]);
      });

      testWidgets('a photo collection can look like another photo, previewed and saved', (tester) async {
        messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'pickImage' ? 'content://media/9' : null);
        final photos = SmartCollection(
          id: 'user_6',
          name: 'Like this',
          prompts: const ['photos like the one you saved'],
          kind: SmartCollection.kindPhotos,
          seedUri: 'content://media/1',
          seedEmbedding: const [0.1, 0.2],
        );
        await openEdit(tester, photos);
        await tester.tap(find.byTooltip('Choose another photo'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(collections.previews.last['seedUri'], 'content://media/9');
        expect(find.text('142 photos and videos'), findsOneWidget);
        await saveChanges(tester);
        expect(collections.updated, isEmpty);
        expect(collections.photoChanges, [
          {'id': 'user_6', 'uri': 'content://media/9', 'name': 'Like this', 'contentMode': 'both'},
        ]);
      });

      testWidgets('picking no photo leaves a photo collection with the one it has', (tester) async {
        messenger.setMockMethodCallHandler(channel, (call) async => null);
        final photos = SmartCollection(
          id: 'user_7',
          name: 'Like this',
          prompts: const ['photos like the one you saved'],
          kind: SmartCollection.kindPhotos,
          seedUri: 'content://media/1',
          seedEmbedding: const [0.1, 0.2],
        );
        await openEdit(tester, photos);
        await tester.tap(find.byTooltip('Choose another photo'));
        await tester.pumpAndSettle();
        await saveChanges(tester);
        expect(collections.photoChanges, isEmpty);
        expect(collections.updated.single.seedUri, 'content://media/1');
      });

      testWidgets('words left alone are saved as they were, even when they hold a name that was never a filter', (tester) async {
        final plain = SmartCollection(id: 'user_8', name: 'Trip', prompts: const ['a photo of Maya at the beach']);
        await openEdit(tester, plain);
        expect(collections.previews.last['prompts'], ['a photo of Maya at the beach']);
        expect(collections.previews.last['personIds'], isEmpty);
        await tester.enterText(find.widgetWithText(TextField, 'Trip'), 'Beach trip');
        await tester.pump();
        await saveChanges(tester);
        final saved = collections.updated.single;
        expect(saved.prompts, ['a photo of Maya at the beach']);
        expect(saved.personIds, isEmpty);
        expect(saved.name, 'Beach trip');
      });

      testWidgets('words that are changed have their names recognised as people', (tester) async {
        final plain = SmartCollection(id: 'user_9', name: 'Trip', prompts: const ['sunsets']);
        await openEdit(tester, plain);
        await tester.enterText(find.widgetWithText(TextField, 'sunsets'), 'Maya sunsets');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(collections.previews.last['personIds'], [1]);
        await saveChanges(tester);
        expect(collections.updated.single.personIds, [1]);
        expect(collections.updated.single.prompts, ['sunsets']);
      });

      testWidgets('a built-in keeps its short phrase when a phrasing is added to it', (tester) async {
        final withShort = SmartCollection(
          id: 'builtin_food',
          name: 'Food',
          prompts: const ['a plate of food on a table', 'a meal'],
          explainQuery: 'food',
          isBuiltIn: true,
        );
        await openEdit(tester, withShort);
        expect(find.widgetWithText(TextField, 'food'), findsOneWidget);
        await tester.tap(find.text('+ Add'));
        await tester.pump();
        await tester.enterText(find.widgetWithText(TextField, 'e.g. "coast"'), 'dinner');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        await saveChanges(tester);
        final saved = collections.updated.single;
        expect(saved.prompts, ['a plate of food on a table', 'a meal', 'dinner']);
        expect(saved.explainQuery, 'food');
        expect(saved.queryText, 'food');
      });

      testWidgets('an emptied name falls back to the words', (tester) async {
        await openEdit(tester, mine);
        await tester.enterText(find.widgetWithText(TextField, 'Evenings'), '');
        await tester.pump();
        await saveChanges(tester);
        expect(collections.updated.single.name, 'Sunsets');
      });
    });
  });
}
