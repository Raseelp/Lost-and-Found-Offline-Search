import 'dart:convert';
import 'package:flutter/services.dart';

class ClipVocab {
  final Map<String, int> tokenToId;
  final List<String> idToToken;
  final Map<String, int> bpeRanks;

  ClipVocab._(this.tokenToId, this.idToToken, this.bpeRanks);

  static Future<ClipVocab> load() async {
    final vocabJson = await rootBundle.loadString(
      'assets/clip_tokenizer/vocab.json',
    );
    final Map<String, dynamic> vocabMap = jsonDecode(vocabJson);

    final Map<String, int> tokenToId = {};
    final List<String> idToToken = List.filled(vocabMap.length, '');

    vocabMap.forEach((token, id) {
      final intId = id as int;
      tokenToId[token] = intId;
      idToToken[intId] = token;
    });

    final mergesTxt = await rootBundle.loadString(
      'assets/clip_tokenizer/merges.txt',
    );
    final lines = mergesTxt.split('\n');

    final Map<String, int> bpeRanks = {};
    int rank = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#')) continue;

      bpeRanks[trimmed] = rank;
      rank++;
    }

    return ClipVocab._(tokenToId, idToToken, bpeRanks);
  }
}
