import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/settings/controllers/developer_note_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryController library;
  late DeveloperNoteController note;

  Future<void> start([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    library = LibraryController();
    note = DeveloperNoteController(library)..onInit();
    await pumpEventQueue();
  }

  void index({int images = 0, int videos = 0}) {
    library.totalImages = images;
    library.totalVideos = videos;
    library.update();
  }

  tearDown(() => note.onClose());

  test('the note is locked and has no dot in a new library', () async {
    await start();
    expect(note.unlocked, isFalse);
    expect(note.showDot, isFalse);
  });

  test('it stays locked just under 1000 photos and videos', () async {
    await start();
    index(images: 700, videos: 299);
    expect(note.unlocked, isFalse);
  });

  test('photos and videos count together, and the dot comes with the unlock', () async {
    await start();
    index(images: 900, videos: 100);
    expect(note.unlocked, isTrue);
    expect(note.showDot, isTrue);
  });

  test('opening the note takes the dot away for good', () async {
    await start();
    index(images: 1000);
    note.markSeen();
    expect(note.showDot, isFalse);
    expect(note.unlocked, isTrue);

    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('developer_note_seen'), isTrue);
  });

  test('opening it while it is locked does nothing', () async {
    await start();
    note.markSeen();
    index(images: 1000);
    expect(note.showDot, isTrue);
  });

  test('it stays unlocked when the index is cleared', () async {
    await start();
    index(images: 1000);
    index();
    expect(note.unlocked, isTrue);
  });

  test('an unlock from an earlier run is remembered, and so is having seen it', () async {
    await start({'developer_note_unlocked': true, 'developer_note_seen': true});
    expect(note.unlocked, isTrue);
    expect(note.seen, isTrue);
    expect(note.showDot, isFalse);
  });

  test('the unlock is saved', () async {
    await start();
    index(images: 1200);
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('developer_note_unlocked'), isTrue);
  });
}
