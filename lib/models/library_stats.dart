/// Everything the Library tab's stat tiles show - one round trip
/// (NativeServices.getLibraryStats) instead of separate calls per number.
class LibraryStats {
  final int totalEmbeddings;
  final int images;
  final int videos;
  final int sizeBytes;

  /// The search model that made an index the app had to drop because it now uses another one (0: none was).
  final int modelResetFrom;

  const LibraryStats({
    required this.totalEmbeddings,
    required this.images,
    required this.videos,
    required this.sizeBytes,
    this.modelResetFrom = 0,
  });

  factory LibraryStats.fromMap(Map<dynamic, dynamic> map) {
    return LibraryStats(
      totalEmbeddings: (map['totalEmbeddings'] as num?)?.toInt() ?? 0,
      images: (map['images'] as num?)?.toInt() ?? 0,
      videos: (map['videos'] as num?)?.toInt() ?? 0,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      modelResetFrom: (map['modelResetFrom'] as num?)?.toInt() ?? 0,
    );
  }

  factory LibraryStats.empty() {
    return const LibraryStats(totalEmbeddings: 0, images: 0, videos: 0, sizeBytes: 0);
  }
}
