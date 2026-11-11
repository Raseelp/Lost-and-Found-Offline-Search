import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/settings/view/developer_note/developer_note_screen.dart';
import 'package:lost_and_found/features/settings/view/developer_note/log_viewer_screen.dart';

const _mb = 1024 * 1024;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  var picked = <Map<String, Object>>[];
  var logs = 'Lost & Found log\nApp: 1.0.0\nline one\nline two\n';
  var mailAnswer = 'opened';

  setUp(() {
    calls.clear();
    picked = [];
    mailAnswer = 'opened';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'pickReportFiles':
              return picked;
            case 'sendReport':
              return mailAnswer;
            case 'appLogs':
              return logs;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder send() => find.widgetWithText(FilledButton, 'Send');

  testWidgets('the page greets by name and says where the report goes', (tester) async {
    await open(tester, const DeveloperNoteScreen());

    expect(find.textContaining("Hi, I'm Raseel"), findsOneWidget);
    expect(find.textContaining('raselp321@gmail.com'), findsOneWidget);
    expect(find.text('Logs attached'), findsOneWidget);
    expect(find.text('Keep the files under 20 MB.'), findsOneWidget);
  });

  testWidgets('the coffee button comes right after the line asking for support', (tester) async {
    await open(tester, const DeveloperNoteScreen());

    final support = tester.getBottomLeft(find.textContaining('Your support buys me more of that time')).dy;
    final button = find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/support/buy_me_a_coffee.png',
    );
    final coffee = tester.getTopLeft(button).dy;
    expect(coffee, greaterThan(support));
    expect(coffee - support, lessThan(60));
    expect(find.textContaining('effort. Your support'), findsOneWidget);
  });

  testWidgets('Send waits for a message, then hands the report to the mail app', (tester) async {
    await open(tester, const DeveloperNoteScreen());
    expect(tester.widget<FilledButton>(send()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'The scan stops at 40 percent.');
    await tester.pump();
    expect(tester.widget<FilledButton>(send()).onPressed, isNotNull);

    await tester.tap(send());
    await tester.pumpAndSettle();

    final sent = calls.singleWhere((c) => c.method == 'sendReport').arguments as Map;
    expect(sent['to'], 'raselp321@gmail.com');
    expect(sent['message'], 'The scan stops at 40 percent.');
    expect(sent['includeLogs'], true);
    expect(sent['uris'], isEmpty);
  });

  testWidgets('the logs can be turned off', (tester) async {
    await open(tester, const DeveloperNoteScreen());

    await tester.tap(find.byTooltip('Leave the logs out'));
    await tester.pumpAndSettle();
    expect(find.text('Logs attached'), findsNothing);
    expect(find.text('Attach logs'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Something broke.');
    await tester.pump();
    await tester.tap(send());
    await tester.pumpAndSettle();

    final sent = calls.singleWhere((c) => c.method == 'sendReport').arguments as Map;
    expect(sent['includeLogs'], false);
  });

  testWidgets('the logs can be attached again', (tester) async {
    await open(tester, const DeveloperNoteScreen());

    await tester.tap(find.byTooltip('Leave the logs out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach logs'));
    await tester.pumpAndSettle();
    expect(find.text('Logs attached'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Back on.');
    await tester.pump();
    await tester.tap(send());
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((c) => c.method == 'sendReport').arguments as Map;
    expect(sent['includeLogs'], true);
  });

  testWidgets('with animations off the page is there at once', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: DeveloperNoteScreen()),
      ),
    );
    await tester.pump();

    final fades = tester.widgetList<FadeTransition>(find.byType(FadeTransition));
    expect(fades.where((f) => f.opacity.value < 1), isEmpty);
  });

  testWidgets('attachments are listed with their size, and can be removed', (tester) async {
    picked = [
      {'uri': 'content://a', 'name': 'shot.png', 'size': 2 * _mb, 'video': false},
      {'uri': 'content://b', 'name': 'clip.mp4', 'size': 5 * _mb, 'video': true},
    ];
    await open(tester, const DeveloperNoteScreen());

    await tester.tap(find.text('Add a screenshot or recording'));
    await tester.pumpAndSettle();
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('7 MB of 20 MB.'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove clip.mp4'));
    await tester.pump();
    expect(find.text('clip.mp4'), findsNothing);
    expect(find.text('2 MB of 20 MB.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'See the screenshot.');
    await tester.pump();
    await tester.tap(send());
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((c) => c.method == 'sendReport').arguments as Map;
    expect(sent['uris'], ['content://a']);
  });

  testWidgets('more than 20 MB of attachments cannot be sent', (tester) async {
    picked = [
      {'uri': 'content://big', 'name': 'long.mp4', 'size': 21 * _mb, 'video': true},
    ];
    await open(tester, const DeveloperNoteScreen());

    await tester.tap(find.text('Add a screenshot or recording'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'It is slow.');
    await tester.pump();

    expect(find.text('The files are 21 MB. Keep them under 20 MB.'), findsOneWidget);
    expect(tester.widget<FilledButton>(send()).onPressed, isNull);
  });

  testWidgets('with no mail app the report does not crash and the button comes back', (tester) async {
    mailAnswer = 'no_mail_app';
    await open(tester, const DeveloperNoteScreen());

    await tester.enterText(find.byType(TextField), 'No mail app here.');
    await tester.pump();
    await tester.tap(send());
    await tester.pumpAndSettle();

    expect(calls.where((c) => c.method == 'sendReport'), hasLength(1));
    expect(tester.widget<FilledButton>(send()).onPressed, isNotNull);
  });

  testWidgets('tapping the logs row opens the log, which can be copied', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await open(tester, const DeveloperNoteScreen());
    await tester.tap(find.text('Logs attached'));
    await tester.pumpAndSettle();

    expect(find.byType(LogViewerScreen), findsOneWidget);
    expect(find.text('line two'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy logs'));
    await tester.pump();
    expect(copied, logs);
  });

  testWidgets('an empty log says so', (tester) async {
    logs = '';
    await open(tester, const LogViewerScreen());
    expect(find.text('There is no log yet.'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.content_copy_rounded)).onPressed, isNull);
  });
}
