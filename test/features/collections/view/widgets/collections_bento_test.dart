import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/collections/view/widgets/collections_bento.dart';

void main() {
  const s = BentoShape.square, t = BentoShape.tall;

  test('the biggest slots go to the items with the most in them', () {
    expect(bentoAssignment(const [s, t, s], [5, 1, 9]), [0, 2, 1]);
  });

  test('leading items take the first slots, whatever their size or count', () {
    expect(bentoAssignment(const [s, t, s, s], [2, 3, 50, 9], leading: 2), [1, 0, 2, 3]);
  });

  test('no leading items is the same as before', () {
    final shapes = bentoShapesFor(7);
    final counts = [4, 8, 1, 30, 2, 2, 16];
    expect(bentoAssignment(shapes, counts, leading: 0), bentoAssignment(shapes, counts));
  });
}
