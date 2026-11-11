import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/search/services/tokenizer/byte_encoder.dart';

void main() {
  test('every byte has its own printable character', () {
    expect(ByteEncoder.byteToUnicode.length, 256);
    expect(ByteEncoder.byteToUnicode.values.toSet().length, 256);
  });

  test('plain letters and digits stand for themselves', () {
    expect(ByteEncoder.encodeBytes(utf8.encode('Cat42')), 'Cat42');
  });

  test('a space becomes a visible mark, as in the original tokenizer', () {
    expect(ByteEncoder.encodeBytes([32]), 'Ġ');
  });

  test('decoding gives back the bytes that were encoded, for any text', () {
    for (final text in ['hello world', 'café', '你好', 'a\tb\nc']) {
      final bytes = utf8.encode(text);
      expect(ByteEncoder.decodeString(ByteEncoder.encodeBytes(bytes)), bytes);
    }
  });
}
