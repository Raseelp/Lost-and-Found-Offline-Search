import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/view/widget/collections_bento.dart';

void main() {
  const s = BentoShape.square, t = BentoShape.tall;

  test('the biggest slots go to the items with the most in them', () {
    // Slot 1 is the big one: item 2 (the most) goes there.
    expect(bentoAssignment(const [s, t, s], [5, 1, 9]), [0, 2, 1]);
  });

  test('leading items take the first slots, whatever their size or count', () {
    // Items 0 and 1 are leading: they fill slots 0 and 1 (the one with more first), and the
    // big slot 1 goes to leading item 1, not to item 2 with the most.
    expect(bentoAssignment(const [s, t, s, s], [2, 3, 50, 9], leading: 2), [1, 0, 2, 3]);
  });

  test('no leading items is the same as before', () {
    final shapes = bentoShapesFor(7);
    final counts = [4, 8, 1, 30, 2, 2, 16];
    expect(bentoAssignment(shapes, counts, leading: 0), bentoAssignment(shapes, counts));
  });
}
