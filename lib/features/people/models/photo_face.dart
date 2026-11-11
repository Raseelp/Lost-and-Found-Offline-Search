import 'package:lost_and_found/features/people/models/person.dart';

/// A recognised face in a photo: where it is (0..1 fractions of the upright photo) and who it is.
class PhotoFace {
  PhotoFace({
    required this.faceId,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.photoW,
    required this.photoH,
    required this.person,
  });

  final int faceId;
  final double left, top, right, bottom;
  /// 0 if unknown.
  final int photoW, photoH;
  final Person person;

  factory PhotoFace.fromMap(Map<dynamic, dynamic> m) => PhotoFace(
    faceId: (m['faceId'] as num).toInt(),
    left: (m['left'] as num).toDouble(),
    top: (m['top'] as num).toDouble(),
    right: (m['right'] as num).toDouble(),
    bottom: (m['bottom'] as num).toDouble(),
    photoW: (m['photoW'] as num?)?.toInt() ?? 0,
    photoH: (m['photoH'] as num?)?.toInt() ?? 0,
    person: Person.fromMap(m['person'] as Map<dynamic, dynamic>),
  );
}

/// Stored faces of one video frame. [exact] says the scan read exact frames, so they line up on screen.
class VideoFrameFaces {
  VideoFrameFaces(this.exact, this.faces);

  final bool exact;
  final List<PhotoFace> faces;
}

/// A person seen in a video, and at which moments (ms).
class VideoPerson {
  VideoPerson({
    required this.person,
    required this.times,
    this.storedTimes = const [],
  });

  final Person person;
  final List<int> times;

  /// The moments where a face of theirs is stored (a position to point at), a subset of [times].
  final List<int> storedTimes;

  factory VideoPerson.fromMap(Map<dynamic, dynamic> m) => VideoPerson(
    person: Person.fromMap(m['person'] as Map<dynamic, dynamic>),
    times: (m['times'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
    storedTimes: (m['stored'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
  );
}
