import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/view/people_timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [FacesController] with no setup and no date lookup, because the real ones start a face scan and call the phone.
class _FakeFaces extends FacesController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadTimeline() async {}
}

const _title = 'Good to know';

/// A page with a button that opens the Timeline screen, the way the People tab does.
Widget _app() {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PeopleTimelineScreen()),
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

/// A first frame only starts a slide, so a wait is one frame and then the time.
Future<void> _settle(WidgetTester tester, [int ms = 400]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Options'));
  await _settle(tester);
}

Future<void> _openTimeline(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    Get.put<FacesController>(_FakeFaces());
  });

  tearDown(() {
    Get.reset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('the tip shows when the Timeline is opened for the first time, and not the second time', (tester) async {
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    expect(find.text(_title), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    Navigator.of(tester.element(find.byType(PeopleTimelineScreen))).pop();
    await tester.pump(const Duration(milliseconds: 600));

    await _openTimeline(tester);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('the options button slides the actions out, and the info action brings the tip back every time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    expect(find.text(_title), findsNothing);
    expect(find.byTooltip('About the timeline'), findsNothing);

    for (var i = 0; i < 2; i++) {
      await _openOptions(tester);
      await tester.tap(find.byTooltip('About the timeline'));
      await _settle(tester);
      expect(find.text(_title), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await _settle(tester);
      expect(find.text(_title), findsNothing);
      expect(find.byTooltip('About the timeline'), findsNothing);
    }
  });

  testWidgets('tapping anywhere else on the screen puts the actions back', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    await _openOptions(tester);
    expect(find.byTooltip('Search people'), findsOneWidget);

    await tester.tapAt(const Offset(200, 400));
    await _settle(tester);
    expect(find.byTooltip('Search people'), findsNothing);
    expect(find.text('Timeline'), findsOneWidget);
  });

  testWidgets('back puts the actions away first, and only then leaves the screen', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    await _openOptions(tester);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(PeopleTimelineScreen), findsOneWidget);
    expect(find.byTooltip('Search people'), findsNothing);

    await tester.binding.handlePopRoute();
    await _settle(tester, 600);
    expect(find.byType(PeopleTimelineScreen), findsNothing);
  });

  testWidgets('a choice that is on shows as a dot on the options button while the actions are away', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    final dot = find.byWidgetPredicate((w) => w is SizedBox && w.width == 7 && w.height == 7);
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    expect(dot, findsNothing);

    await _openOptions(tester);
    await tester.tap(find.byTooltip('Collapse the list'));
    await _settle(tester);
    expect(dot, findsOneWidget);
  });

  testWidgets('on a very narrow screen the actions scroll sideways, each one still reachable', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    tester.view.physicalSize = const Size(200, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await _openTimeline(tester);
    await _openOptions(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byTooltip('Search people'));
    await tester.pump();
    await tester.tap(find.byTooltip('Search people'));
    await _settle(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations off the actions are there at once', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const PeopleTimelineScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Options'));
    await tester.pump();

    expect(find.byTooltip('Search people'), findsOneWidget);
    expect(find.byTooltip('Search people').hitTestable(), findsOneWidget);
  });

  testWidgets('the title and the options button fit on a 320 px wide phone at larger text', (tester) async {
    SharedPreferences.setMockInitialValues({'timeline_tip_seen': true});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: const PeopleTimelineScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Timeline')).height, lessThan(40));
    await _openOptions(tester);
    expect(tester.takeException(), isNull);
  });
}
