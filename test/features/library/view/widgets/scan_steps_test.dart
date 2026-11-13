import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/library/view/widgets/scan_steps.dart';

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Future<Uint8List> _face(int id) async => Uint8List.fromList(_png);

Widget _app(Widget child, {bool calm = false, double textScale = 1}) => MaterialApp(
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: calm, textScaler: TextScaler.linear(textScale)),
    child: home!,
  ),
  home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child)),
);

ScanStepsCard _steps({
  int processed = 1240,
  int total = 3800,
  int? found,
  int? etaMs = 12 * 60000,
  int searchable = 1240,
  int people = 24,
  bool faceWork = true,
  bool findingFaces = false,
  bool tuning = false,
  double faceFraction = 0.5,
  int batchPhotos = 60,
  bool paused = false,
  bool idle = false,
  bool celebrate = false,
  List<String> photoIds = const [],
  List<int> faceIds = const [],
}) => ScanStepsCard(
  processed: processed,
  total: total,
  found: found,
  etaMs: etaMs,
  searchable: searchable,
  people: people,
  faceWork: faceWork,
  findingFaces: findingFaces,
  tuning: tuning,
  faceFraction: faceFraction,
  batchPhotos: batchPhotos,
  paused: paused,
  idle: idle,
  celebrate: celebrate,
  photoIds: photoIds,
  loadPhoto: (id) async => Uint8List.fromList(_png),
  faceIds: faceIds,
  loadFace: _face,
  semanticsLabel: 'Indexing 33 percent',
);

void main() {
  test('counts are grouped in thousands', () {
    expect(groupedCount(0), '0');
    expect(groupedCount(999), '999');
    expect(groupedCount(1240), '1,240');
    expect(groupedCount(1234567), '1,234,567');
  });

  test('the time left is rounded the way people say it', () {
    expect(timeLeftText(20 * 1000), 'under a minute left');
    expect(timeLeftText(60 * 1000), 'about a minute left');
    expect(timeLeftText(12 * 60000), 'about 12 min left');
    expect(timeLeftText(47 * 60000), 'about 45 min left');
    expect(timeLeftText(150 * 60000), 'about 2.5 h left');
    expect(timeLeftText(12 * 3600000), 'about 12 h left');
  });

  test('a speed is said per second, or per minute when it is slow', () {
    expect(speedText(14.2), '14 per second');
    expect(speedText(2.46), '2.5 per second');
    expect(speedText(0.5), '30 per minute');
  });

  testWidgets('the speed of indexing and of finding faces is shown', (tester) async {
    await tester.pumpWidget(
      _app(
        ScanStepsCard(
          processed: 1240,
          total: 3800,
          searchable: 1240,
          people: 3,
          faceWork: true,
          findingFaces: true,
          tuning: false,
          faceFraction: 0.5,
          batchPhotos: 60,
          photoRate: 14.2,
          faceRate: 6.4,
          semanticsLabel: 'x',
        ),
      ),
    );

    expect(find.text('14 per second'), findsOneWidget);
    expect(find.text('Looking at the last 60 photos  ·  6.4 per second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before the total is known the first step says it is getting ready', (tester) async {
    await tester.pumpWidget(_app(_steps(processed: 0, total: 0, etaMs: null, searchable: 0, people: 0, faceWork: false)));

    expect(find.text('Reading photos and videos'), findsOneWidget);
    expect(find.text('Getting ready'), findsOneWidget);
    expect(find.text('Finding people'), findsOneWidget);
    expect(find.text('Starts once the first photos are read'), findsOneWidget);
    expect(find.text('Search'), findsNWidgets(2));
    expect(find.text('Ready after the first photos'), findsOneWidget);
  });

  testWidgets('a walk that has found items says how many', (tester) async {
    await tester.pumpWidget(_app(_steps(processed: 0, total: 0, found: 2410, etaMs: null, searchable: 0, people: 0, faceWork: false)));
    expect(find.text('2,410 items found so far'), findsOneWidget);
  });

  testWidgets('a running scan shows its counts, the time left, the people and that search works', (tester) async {
    await tester.pumpWidget(_app(_steps()));

    expect(find.text('1,240 of 3,800  ·  about 12 min left'), findsOneWidget);
    expect(find.text('24 found so far'), findsOneWidget);
    expect(find.text('Search is ready'), findsOneWidget);
    expect(find.text('1,240 searchable now'), findsOneWidget);
  });

  testWidgets('finding the faces of a batch shows its progress', (tester) async {
    await tester.pumpWidget(_app(_steps(findingFaces: true, faceIds: [1, 2, 3])));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Looking at the last 60 photos'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each new face is shown once, and the last one stays until another is found', (tester) async {
    final faces = {for (final id in [1, 2, 3, 4]) id: Uint8List.fromList(_png)};
    final loaded = <int>[];
    Future<Uint8List> load(int id) async {
      loaded.add(id);
      return faces[id]!;
    }

    Widget card(List<int> ids) => _app(
      ScanStepsCard(
        processed: 100,
        total: 3800,
        searchable: 100,
        people: 3,
        faceWork: true,
        findingFaces: true,
        tuning: false,
        faceFraction: 0.5,
        batchPhotos: 60,
        faceIds: ids,
        loadFace: load,
        semanticsLabel: 'x',
      ),
    );

    Uint8List shown() {
      final image = tester.widgetList<Image>(find.byType(Image)).last.image as ResizeImage;
      return (image.imageProvider as MemoryImage).bytes;
    }

    await tester.pumpWidget(card([3, 2, 1]));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(identical(shown(), faces[3]), isTrue);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(identical(shown(), faces[3]), isTrue);
    expect(loaded, [1, 2, 3]);

    await tester.pumpWidget(card([4, 3, 2, 1]));
    await tester.pump(const Duration(milliseconds: 900));
    expect(identical(shown(), faces[4]), isTrue);
    expect(loaded, [1, 2, 3, 4]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while photos are read the people circle is held, and while faces are found the photo circle is', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a'])));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.pumpWidget(_app(_steps(photoIds: ['a'], findingFaces: true, faceIds: [1])));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.pause_rounded), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stopped scan holds both circles and says it is paused', (tester) async {
    await tester.pumpWidget(_app(_steps(paused: true, etaMs: null, photoIds: ['a'])));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.pause_rounded), findsNWidgets(2));
    expect(find.text('1,240 of 3,800  ·  paused'), findsOneWidget);
    expect(find.text('Looking at the last 60 photos'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each new photo is shown once, and the last one stays until another is indexed', (tester) async {
    final photos = {for (final id in ['a', 'b', 'c', 'd']) id: Uint8List.fromList(_png)};
    final loaded = <String>[];
    Widget card(List<String> ids) => _app(
      ScanStepsCard(
        processed: 100,
        total: 3800,
        searchable: 100,
        people: 0,
        faceWork: false,
        findingFaces: false,
        tuning: false,
        faceFraction: 0,
        batchPhotos: 60,
        photoIds: ids,
        loadPhoto: (id) async {
          loaded.add(id);
          return photos[id]!;
        },
        semanticsLabel: 'x',
      ),
    );

    Uint8List shown() {
      final image = tester.widgetList<Image>(find.byType(Image)).last.image as ResizeImage;
      return (image.imageProvider as MemoryImage).bytes;
    }

    await tester.pumpWidget(card(['c', 'b', 'a']));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(identical(shown(), photos['c']), isTrue);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(identical(shown(), photos['c']), isTrue);
    expect(loaded, ['a', 'b', 'c']);

    await tester.pumpWidget(card(['d', 'c', 'b', 'a']));
    await tester.pump(const Duration(milliseconds: 900));
    expect(identical(shown(), photos['d']), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the last face stays in its circle while photos are being read', (tester) async {
    Widget card(bool faces) => _app(_steps(findingFaces: faces, faceIds: faces ? [1] : const [], photoIds: ['a']));

    await tester.pumpWidget(card(true));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(card(false));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the speed test says it is one time only', (tester) async {
    await tester.pumpWidget(_app(_steps(findingFaces: true, tuning: true, people: 0)));

    expect(find.text('Preparing face search for this phone'), findsOneWidget);
    expect(find.text('One time only, about a minute'), findsOneWidget);
  });

  testWidgets('the photos just read flip inside the first circle, and the loop stops with the card', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a', 'b', 'c'])));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with motion off the photo stays still and nothing keeps running', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a', 'b', 'c']), calm: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Image), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the card fits a small phone at double text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_steps(findingFaces: true, faceIds: [1]), textScale: 2));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the work is handed over along the rail, then the next circle turns', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a'])));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(_app(_steps(photoIds: ['a'], findingFaces: true, faceIds: [1])));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a change of turn while a handoff plays goes straight to the new turn', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a'])));
    await tester.pumpWidget(_app(_steps(photoIds: ['a'], findingFaces: true, faceIds: [1])));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_app(_steps(photoIds: ['a'])));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with motion off a change of turn is at once', (tester) async {
    await tester.pumpWidget(_app(_steps(photoIds: ['a']), calm: true));
    await tester.pumpWidget(_app(_steps(photoIds: ['a'], findingFaces: true, faceIds: [1]), calm: true));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('before any scan the steps wait at 0 of 0', (tester) async {
    await tester.pumpWidget(_app(_steps(processed: 0, total: 0, etaMs: null, searchable: 0, people: 0, faceWork: false, idle: true)));

    expect(find.text('0 of 0'), findsOneWidget);
    expect(find.text('Getting ready'), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.text('Starts once the first photos are read'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished scan keeps the steps with its numbers and no pause word', (tester) async {
    await tester.pumpWidget(_app(_steps(processed: 3800, total: 3800, etaMs: null, searchable: 3800, people: 24, faceWork: false, paused: true)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('3,800 of 3,800'), findsOneWidget);
    expect(find.text('24 found so far'), findsOneWidget);
    expect(find.text('3,800 searchable now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the last circle celebrates once when the scan ends, and the card then settles', (tester) async {
    Widget card(bool celebrate) => _app(_steps(processed: 3800, total: 3800, etaMs: null, searchable: 3800, faceWork: false, paused: true, celebrate: celebrate));

    await tester.pumpWidget(card(false));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(card(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3,800 searchable now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
