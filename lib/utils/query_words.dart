/// Common words filtered out before asking why a word matched. Scoring "the" or "a" against an image is
/// meaningless noise. The list is short and generic on purpose, because it only needs to remove the obvious
/// non-content words.
const Set<String> _stopwords = {
  'a', 'an', 'the', 'of', 'in', 'on', 'at', 'to', 'for', 'with', 'and', 'or',
  'is', 'are', 'was', 'were', 'be', 'been', 'my', 'me', 'i', 'this', 'that',
  'these', 'those', 'some', 'near', 'by', 'from', 'it', 'its', 'as', 'into',
  'photo', 'photos', 'picture', 'pictures', 'image', 'images', 'video', 'videos',
};

/// The query words worth explaining a match by: lowercased, deduplicated, stripped of punctuation, with stopwords and
/// very short fragments dropped. They decide whether there is anything worth asking native to score, and are the
/// candidate list sent over.
List<String> extractContentWords(String query) {
  final seen = <String>{};
  final words = <String>[];

  for (final raw in query.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (raw.length <= 2) continue;
    if (_stopwords.contains(raw)) continue;
    if (seen.add(raw)) words.add(raw);
  }

  return words;
}
