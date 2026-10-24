import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

class _FakeFaces extends FacesController {
  @override
  // The real setup starts a face scan and calls the phone: skipped on purpose.
  // ignore: must_call_super
  void onInit() {}
}

Person _person({String? name}) =>
    Person(id: 1, name: name, hidden: false, faceCount: 5, photoCount: 4, coverFaceId: 7);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lostandfound/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('search shows 20 results until the user picks another number', () {
    expect(NativeController().sliderValue, 20);
  });

  group('PersonTile', () {
    var opened = 0, naming = 0;

    setUp(() {
      opened = 0;
      naming = 0;
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      Get.put<FacesController>(_FakeFaces());
    });

    tearDown(() {
      Get.reset();
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> show(WidgetTester tester, Person person, {bool selecting = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: PersonTile(
                  person: person,
                  selecting: selecting,
                  onTap: () => opened++,
                  onAddName: () => naming++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('without a name, the words under the faces ask for one', (tester) async {
      await show(tester, _person());
      await tester.tap(find.text('Add name'));
      await tester.tap(find.text('4 photos'));
      expect(naming, 2);
      expect(opened, 0);
    });

    testWidgets('the faces still open the person', (tester) async {
      await show(tester, _person());
      await tester.tap(find.byType(FaceAvatar).first, warnIfMissed: false);
      expect(opened, 1);
      expect(naming, 0);
    });

    testWidgets('with a name, its words open the person as before', (tester) async {
      await show(tester, _person(name: 'Maya'));
      await tester.tap(find.text('Maya'));
      expect(opened, 1);
      expect(naming, 0);
    });

    testWidgets('while choosing, a tap chooses', (tester) async {
      await show(tester, _person(), selecting: true);
      await tester.tap(find.text('Add name'));
      expect(opened, 1);
      expect(naming, 0);
    });
  });
}
