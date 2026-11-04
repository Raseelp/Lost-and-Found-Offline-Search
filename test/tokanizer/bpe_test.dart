import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/tokanizer/bpe.dart';

void main() {
  test('a word with no merge rules stays as single letters, the last one marked as the end', () {
    expect(BPE({}).encode('cat'), ['c', 'a', 't</w>']);
  });

  test('one letter has nothing to merge and is returned with the end marker', () {
    expect(BPE({}).encode('a'), ['a</w>']);
  });

  test('a rule that includes the end marker merges the last two letters', () {
    expect(BPE({'a b</w>': 0}).encode('ab'), ['ab</w>']);
  });

  test('the rule with the lowest rank is applied first', () {
    final bpe = BPE({'a b': 1, 'b c</w>': 0});
    expect(bpe.encode('abc'), ['a', 'bc</w>']);
  });

  test('a rule merges the pair wherever it occurs, but not across the end marker', () {
    expect(BPE({'a b': 0}).encode('abab'), ['ab', 'a', 'b</w>']);
  });

  test('merges carry on until no rule applies', () {
    final bpe = BPE({'t h': 0, 'th e</w>': 1, 'h e</w>': 5});
    expect(bpe.encode('the'), ['the</w>']);
  });

  test('the same word is answered from the cache', () {
    final bpe = BPE({'a b</w>': 0});
    expect(identical(bpe.encode('ab'), bpe.encode('ab')), isTrue);
  });
}
