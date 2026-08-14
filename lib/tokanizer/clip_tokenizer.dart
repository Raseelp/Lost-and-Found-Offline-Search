import 'dart:convert';

import 'clip_vocab.dart';
import 'byte_encoder.dart';
import 'bpe.dart';

class ClipTokenizer {
  static const int maxLength = 77;
  static const int startToken = 49406;
  static const int endToken = 49407;

  final ClipVocab vocab;
  final BPE bpe;

  ClipTokenizer._(this.vocab, this.bpe);

  // Loaded once per app session; vocab/merges never change at runtime.
  static Future<ClipTokenizer>? _cached;

  static Future<ClipTokenizer> load() {
    return _cached ??= _loadUncached();
  }

  static Future<ClipTokenizer> _loadUncached() async {
    final vocab = await ClipVocab.load();
    final bpe = BPE(vocab.bpeRanks);
    return ClipTokenizer._(vocab, bpe);
  }

  List<int> tokenize(String text) {
    final normalized = _normalize(text);

    final List<int> tokens = [];
    tokens.add(startToken);

    for (final word in _splitWords(normalized)) {
      final bytes = utf8.encode(word);

      final encoded = ByteEncoder.encodeBytes(bytes);

      final bpeTokens = bpe.encode(encoded);

      for (final token in bpeTokens) {
        final id = vocab.tokenToId[token];
        if (id != null) {
          tokens.add(id);
        }
      }
    }

    tokens.add(endToken);

    return _padOrTruncate(tokens);
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Iterable<String> _splitWords(String text) {
    final regex = RegExp(
      r"""'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+""",
      unicode: true,
    );

    return regex.allMatches(text).map((m) => m.group(0)!);
  }

  List<int> _padOrTruncate(List<int> tokens) {
    if (tokens.length > maxLength) {
      return tokens.sublist(0, maxLength);
    }

    final padded = List<int>.filled(maxLength, 0);
    for (int i = 0; i < tokens.length; i++) {
      padded[i] = tokens[i];
    }
    return padded;
  }
}
