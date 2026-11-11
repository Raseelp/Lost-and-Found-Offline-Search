import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/search/services/tokenizer/clip_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ClipTokenizer> tokenizer() => ClipTokenizer.load();

  List<int> padded(List<int> ids) => [...ids, ...List.filled(ClipTokenizer.maxLength - ids.length, 0)];

  test('"a photo of a cat" gives the ids the original CLIP tokenizer gives', () async {
    final t = await tokenizer();
    expect(t.tokenize('a photo of a cat'), padded([49406, 320, 1125, 539, 320, 2368, 49407]));
  });

  test('"hello world" gives the ids the original CLIP tokenizer gives', () async {
    final t = await tokenizer();
    expect(t.tokenize('hello world'), padded([49406, 3306, 1002, 49407]));
  });

  test('every result is 77 long, starts with the start token and ends the text with the end token', () async {
    final t = await tokenizer();
    final ids = t.tokenize('sunset over the sea');
    expect(ids.length, ClipTokenizer.maxLength);
    expect(ids.first, ClipTokenizer.startToken);
    expect(ids.contains(ClipTokenizer.endToken), isTrue);
  });

  test('an empty text is just the start and end tokens', () async {
    final t = await tokenizer();
    expect(t.tokenize(''), padded([ClipTokenizer.startToken, ClipTokenizer.endToken]));
  });

  test('case and extra spaces do not change the result', () async {
    final t = await tokenizer();
    expect(t.tokenize('  A   CAT  '), t.tokenize('a cat'));
  });

  test('a number is cut into single digits', () async {
    final t = await tokenizer();
    expect(t.tokenize('42'), t.tokenize('4 2'));
  });

  test('a text that is too long is cut to 77 and still ends with the end token', () async {
    final t = await tokenizer();
    final ids = t.tokenize(List.filled(120, 'dog').join(' '));
    expect(ids.length, ClipTokenizer.maxLength);
    expect(ids.last, ClipTokenizer.endToken);
    expect(ids.first, ClipTokenizer.startToken);
  });
}
