
/// The two groups one person's faces fall into (the bigger group first).
class SplitPreview {
  SplitPreview({
    required this.first,
    required this.second,
    required this.firstCovers,
    required this.secondCovers,
  });

  /// Every face id in each group.
  final List<int> first, second;
  /// A few clear faces of each group to show.
  final List<int> firstCovers, secondCovers;

  factory SplitPreview.fromMap(Map<dynamic, dynamic> m) {
    List<int> ints(String key) =>
        (m[key] as List).map((e) => (e as num).toInt()).toList();
    return SplitPreview(
      first: ints('first'),
      second: ints('second'),
      firstCovers: ints('firstCovers'),
      secondCovers: ints('secondCovers'),
    );
  }
}

/// One merge the user made, as remembered for undo.
class MergeRecord {
  MergeRecord({
    required this.id,
    required this.keptId,
    required this.keptName,
    required this.keptCover,
    required this.removedName,
    required this.removedCover,
    required this.faceCount,
    required this.createdAt,
  });

  final int id;
  final int keptId;
  final String? keptName;
  final int? keptCover;
  final String? removedName;
  final int? removedCover;
  final int faceCount;
  /// Milliseconds since epoch.
  final int createdAt;

  factory MergeRecord.fromMap(Map<dynamic, dynamic> m) => MergeRecord(
    id: (m['id'] as num).toInt(),
    keptId: (m['keptId'] as num).toInt(),
    keptName: m['keptName'] as String?,
    keptCover: (m['keptCover'] as num?)?.toInt(),
    removedName: m['removedName'] as String?,
    removedCover: (m['removedCover'] as num?)?.toInt(),
    faceCount: (m['faceCount'] as num?)?.toInt() ?? 0,
    createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
  );
}

/// Two people who may be one.
class MergeSuggestion {
  MergeSuggestion({required this.aId, required this.bId, required this.score});

  final int aId, bId;
  /// How alike they look, roughly 0.3 (maybe) to 0.6 (very likely).
  final double score;

  factory MergeSuggestion.fromMap(Map<dynamic, dynamic> m) => MergeSuggestion(
    aId: (m['a'] as num).toInt(),
    bId: (m['b'] as num).toInt(),
    score: (m['score'] as num).toDouble(),
  );
}
