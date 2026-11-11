
/// A group of faces believed to be one person.
class Person {
  Person({
    required this.id,
    required this.name,
    required this.hidden,
    required this.faceCount,
    required this.photoCount,
    required this.coverFaceId,
    this.stackFaceIds = const [],
  });

  final int id;
  final String? name;
  final bool hidden;
  final int faceCount, photoCount;
  final int coverFaceId;

  /// Two more of their clearest faces, for the little stack on their tile (fewer for a person
  /// with few faces).
  final List<int> stackFaceIds;

  factory Person.fromMap(Map<dynamic, dynamic> m) => Person(
    id: (m['id'] as num).toInt(),
    name: m['name'] as String?,
    hidden: m['hidden'] as bool? ?? false,
    faceCount: (m['faceCount'] as num).toInt(),
    photoCount: (m['photoCount'] as num).toInt(),
    coverFaceId: (m['coverFaceId'] as num).toInt(),
    stackFaceIds: [
      for (final id in (m['stackFaceIds'] as List? ?? const []))
        (id as num).toInt(),
    ],
  );
}

/// One face of a person (for the review screen).
class PersonFace {
  PersonFace({
    required this.faceId,
    required this.good,
    required this.photoUri,
    this.isVideo = false,
  });

  final int faceId;
  /// False for small, blurry or turned-away faces that are left out of deciding who the person is.
  final bool good;
  final String photoUri;
  /// True when it was found in a video, and [photoUri] is the video.
  final bool isVideo;

  factory PersonFace.fromMap(Map<dynamic, dynamic> m) => PersonFace(
    faceId: (m['faceId'] as num).toInt(),
    good: m['good'] as bool? ?? true,
    photoUri: m['photoUri'] as String? ?? '',
    isVideo: m['isVideo'] as bool? ?? false,
  );
}
