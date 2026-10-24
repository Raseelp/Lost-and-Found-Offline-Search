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

// The people the fake library knows.
final _maya = Person(id: 1, name: 'Maya', hidden: false, faceCount: 40, photoCount: 38, coverFaceId: 11);
final _anna = Person(id: 2, name: 'Anna', hidden: false, faceCount: 22, photoCount: 21, coverFaceId: 12);

class _FakeFaces extends FacesController {
  // The real setup starts a face scan and calls the phone: skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {
    people = [_maya, _anna];
  }
}

class _FakeNative extends NativeController {
  // The real setup loads from the phone: skipped on purpose.
  @override
  // ignore: must_call_super
  void onInit() {}
}

// Answers the preview with a fixed library, and records what is saved.
class _FakeCollections extends CollectionsController {
  final List<Map<String, Object?>> previews = [];
  final List<Map<String, Object?>> created = [];

  // The real setup loads the saved collections: skipped on purpose.
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
    int shown = 5,
  }) async {
    previews.add({'prompts': prompts, 'contentMode': contentMode, 'personIds': personIds});
    return const CollectionPreview(
      count: 142,
      items: [],
      people: [(personId: 1, count: 38), (personId: 2, count: 21), (personId: 99, count: 3)],
    );
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
      // Face pictures and anything else native: nothing to give.
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
      // A phone's screen.
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
      // Person 99 is not listed (hidden, say), so only the two known people are named.
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
  });
}
