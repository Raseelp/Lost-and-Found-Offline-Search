import 'dart:collection';

/// Byte Pair Encoding, ported from OpenAI's CLIP tokenizer.
class BPE {
  final Map<String, int> bpeRanks;
  final Map<String, List<String>> cache = {};

  BPE(this.bpeRanks);

  /// Splits one word into its byte pair tokens. CLIP marks the end of a word by appending `</w>` to its last character
  /// before merging, and the vocab and merge ranks were trained that way. `the</w>` is a different token from a
  /// mid-word "the", so leaving the marker out gives wrong tokens for almost every word.
  List<String> encode(String token) {
    if (cache.containsKey(token)) {
      return cache[token]!;
    }

    List<String> word = token.split('');
    if (word.isNotEmpty) {
      word[word.length - 1] = '${word.last}</w>';
    }
    Set<List<String>> pairs = _getPairs(word);

    if (pairs.isEmpty) {
      return [word.isNotEmpty ? word.first : token];
    }

    while (true) {
      List<String>? minPair;
      int minRank = 1 << 30;

      for (final pair in pairs) {
        final key = '${pair[0]} ${pair[1]}';
        final rank = bpeRanks[key];
        if (rank != null && rank < minRank) {
          minRank = rank;
          minPair = pair;
        }
      }

      if (minPair == null) {
        break;
      }

      final first = minPair[0];
      final second = minPair[1];

      final List<String> newWord = [];
      int i = 0;

      while (i < word.length) {
        int j = word.indexOf(first, i);
        if (j == -1) {
          newWord.addAll(word.sublist(i));
          break;
        }

        newWord.addAll(word.sublist(i, j));
        i = j;

        if (i < word.length - 1 && word[i] == first && word[i + 1] == second) {
          newWord.add(first + second);
          i += 2;
        } else {
          newWord.add(word[i]);
          i += 1;
        }
      }

      word = newWord;

      if (word.length == 1) {
        break;
      } else {
        pairs = _getPairs(word);
      }
    }

    cache[token] = word;
    return word;
  }

  Set<List<String>> _getPairs(List<String> word) {
    final Set<List<String>> pairs = HashSet(
      equals: (a, b) => a[0] == b[0] && a[1] == b[1],
      hashCode: (a) => Object.hash(a[0], a[1]),
    );

    for (int i = 0; i < word.length - 1; i++) {
      pairs.add([word[i], word[i + 1]]);
    }
    return pairs;
  }
}
