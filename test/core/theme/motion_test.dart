import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/core/theme/motion.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.calmSeen, required this.onController});

  final void Function(bool) calmSeen;
  final void Function(AnimationController) onController;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.calmSeen(calm(context));
    widget.onController(controller);
    loopUnlessCalm(context, controller, rest: 0.25);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget wrap(Widget child, {required bool disableAnimations}) =>
    MediaQuery(data: MediaQueryData(disableAnimations: disableAnimations), child: Directionality(textDirection: TextDirection.ltr, child: child));

void main() {
  testWidgets('calm is true only when the phone asks for no animations', (t) async {
    bool? seen;
    await t.pumpWidget(wrap(_Probe(calmSeen: (v) => seen = v, onController: (_) {}), disableAnimations: false));
    expect(seen, isFalse);
    await t.pumpWidget(wrap(_Probe(calmSeen: (v) => seen = v, onController: (_) {}), disableAnimations: true));
    expect(seen, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a loop keeps running normally', (t) async {
    late AnimationController c;
    await t.pumpWidget(wrap(_Probe(calmSeen: (_) {}, onController: (v) => c = v), disableAnimations: false));
    await t.pump(const Duration(milliseconds: 100));
    expect(c.isAnimating, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with no animations a loop is stopped on its resting frame', (t) async {
    late AnimationController c;
    await t.pumpWidget(wrap(_Probe(calmSeen: (_) {}, onController: (v) => c = v), disableAnimations: true));
    await t.pump(const Duration(milliseconds: 100));
    expect(c.isAnimating, isFalse);
    expect(c.value, 0.25);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a loop follows the setting when it changes', (t) async {
    late AnimationController c;
    Widget probe(bool off) => wrap(_Probe(calmSeen: (_) {}, onController: (v) => c = v), disableAnimations: off);
    await t.pumpWidget(probe(false));
    await t.pump(const Duration(milliseconds: 100));
    expect(c.isAnimating, isTrue);
    await t.pumpWidget(probe(true));
    expect(c.isAnimating, isFalse);
    await t.pumpWidget(probe(false));
    await t.pump(const Duration(milliseconds: 100));
    expect(c.isAnimating, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  group('glideTo', () {
    Future<ScrollController> scrollable(WidgetTester t, {required bool calmMode, required void Function(BuildContext) grab}) async {
      final controller = ScrollController();
      await t.pumpWidget(wrap(
        Builder(builder: (context) {
          grab(context);
          return SizedBox(height: 300, child: ListView(controller: controller, children: [for (var i = 0; i < 50; i++) SizedBox(height: 100, child: Text('$i'))]));
        }),
        disableAnimations: calmMode,
      ));
      return controller;
    }

    testWidgets('jumps at once with no animations', (t) async {
      late BuildContext ctx;
      final c = await scrollable(t, calmMode: true, grab: (x) => ctx = x);
      await glideTo(ctx, c, 500);
      expect(c.offset, 500);
      c.dispose();
    });

    testWidgets('glides otherwise, and arrives', (t) async {
      late BuildContext ctx;
      final c = await scrollable(t, calmMode: false, grab: (x) => ctx = x);
      final future = glideTo(ctx, c, 500);
      await t.pump(const Duration(milliseconds: 100));
      expect(c.offset, lessThan(500));
      await t.pumpAndSettle();
      await future;
      expect(c.offset, 500);
      c.dispose();
    });

    testWidgets('does nothing when the list is not on screen', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(wrap(Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }), disableAnimations: false));
      final c = ScrollController();
      await glideTo(ctx, c, 500);
      c.dispose();
    });
  });
}
