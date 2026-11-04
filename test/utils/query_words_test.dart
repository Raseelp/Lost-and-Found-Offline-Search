import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/utils/query_words.dart';

void main() {
  test('keeps the words that say what is in the picture', () {
    expect(extractContentWords('a birthday cake with candles'), ['birthday', 'cake', 'candles']);
  });

  test('drops stop words and words about the kind of file', () {
    expect(extractContentWords('photos of the beach in a video'), ['beach']);
  });

  test('lowercases, strips punctuation and drops very short fragments', () {
    expect(extractContentWords('Sunset, at Goa! (2019)'), ['sunset', 'goa', '2019']);
    expect(extractContentWords('it is ok'), isEmpty);
  });

  test('says each word once, in the order it first appears', () {
    expect(extractContentWords('dog and DOG and cat and dog'), ['dog', 'cat']);
  });

  test('an empty or symbols-only query has no content words', () {
    expect(extractContentWords(''), isEmpty);
    expect(extractContentWords('!!! ???'), isEmpty);
  });
}
