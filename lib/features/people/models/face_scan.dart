
/// One face just found by the scan: the photo it is in, where it sits there (fractions of
/// the photo, so they hold at any size), and who it was placed with.
class FaceEvent {
  const FaceEvent({
    required this.id,
    required this.photoUri,
    required this.box,
    required this.landmarks,
    required this.score,
    required this.personId,
    required this.isNew,
    required this.personPhotos,
  });

  final int id;
  final String photoUri;

  /// left, top, right, bottom.
  final List<double> box;

  /// Left eye, right eye, nose, left mouth corner, right mouth corner (x, y each).
  final List<double> landmarks;
  final double score;
  final int? personId;

  /// The face started that person.
  final bool isNew;

  /// How many photos that person is in.
  final int personPhotos;

  factory FaceEvent.fromMap(Map<dynamic, dynamic> m) {
    List<double> floats(Object? v) => [
      for (final x in (v as List?) ?? const []) (x as num).toDouble(),
    ];
    return FaceEvent(
      id: (m['id'] as num).toInt(),
      photoUri: m['photo'] as String? ?? '',
      box: floats(m['box']),
      landmarks: floats(m['landmarks']),
      score: (m['score'] as num?)?.toDouble() ?? 0,
      personId: (m['person'] as num?)?.toInt(),
      isNew: m['isNew'] as bool? ?? false,
      personPhotos: (m['photos'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Where the automatic face scan is, plus the current totals.
class FaceStatus {
  FaceStatus({
    this.running = false,
    this.paused = false,
    this.userPaused = false,
    this.done = false,
    this.phase = 'scan',
    this.following = false,
    this.batch = false,
    this.recentFaceEvents = const [],
    this.refine = true,
    this.deferredPhotos = 0,
    this.tuning,
    this.processed = 0,
    this.total = 0,
    this.faces = 0,
    this.people = 0,
    this.failed = 0,
    this.runProcessed = 0,
    this.elapsedMs = 0,
    this.error,
    this.ready = true,
    this.thorough = false,
    this.strictness = 'balanced',
    this.modelsDir = '',
    this.scanVideos = true,
    this.videoDensity = 'balanced',
    this.videos = 0,
    this.videosTotal = 0,
  });

  /// [paused] means waiting for photo indexing to finish. [userPaused] means stopped by the user.
  final bool running, paused, userPaused, done;

  /// What the scan is doing: 'scan' (finding and recognising the clear faces), 'refine' (the small and blurry ones,
  /// afterwards) or 'tune' (a one-off speed test for this phone). While refining, processed and total count photos of
  /// that pass.
  final String phase;

  /// True while the scan is following an indexing scan that is still running, finding faces in photos as they are
  /// indexed. The total is still growing.
  final bool following;

  /// True while it is finding the faces in a batch of photos that indexing has just done. Indexing waits meanwhile,
  /// and processed and total then count that batch.
  final bool batch;

  /// The same faces with where each was found and who it joined, newest first.
  final List<FaceEvent> recentFaceEvents;

  /// Whether the refining pass is switched on, and how many photos still have faces waiting for it.
  final bool refine;
  final int deferredPhotos;

  /// What the speed test picked for this phone, for the options sheet.
  final String? tuning;
  final int processed, total, faces, people, failed, runProcessed, elapsedMs;
  final String? error;
  /// False when no recognition model is installed.
  final bool ready;
  final bool thorough;
  final String strictness;
  final String modelsDir;

  /// Videos: whether they are scanned, how many frames ('fast', 'balanced' or 'thorough'), and how many are done of
  /// how many.
  final bool scanVideos;
  final String videoDensity;
  final int videos, videosTotal;

  /// Photos (or videos, in the videos pass) left in the running pass.
  int get phaseRemaining => (total - processed).clamp(0, total);

  /// Photos still to work on overall, including faces waiting for the refining pass.
  int get remaining => phase == 'refine'
      ? phaseRemaining
      : phaseRemaining + (refine ? deferredPhotos : 0);

  FaceStatus withUserPaused(bool value) => FaceStatus(
    running: value ? false : running,
    paused: paused,
    userPaused: value,
    done: done,
    phase: phase,
    following: following,
    batch: batch,
    recentFaceEvents: recentFaceEvents,
    refine: refine,
    deferredPhotos: deferredPhotos,
    tuning: tuning,
    processed: processed,
    total: total,
    faces: faces,
    people: people,
    failed: failed,
    runProcessed: runProcessed,
    elapsedMs: elapsedMs,
    error: error,
    ready: ready,
    thorough: thorough,
    strictness: strictness,
    modelsDir: modelsDir,
    scanVideos: scanVideos,
    videoDensity: videoDensity,
    videos: videos,
    videosTotal: videosTotal,
  );

  double? get fraction =>
      total > 0 ? (processed / total).clamp(0.0, 1.0) : null;

  /// Rough time left, from this run's pace; null until there is enough to go on.
  Duration? get eta {
    if (!running ||
        paused ||
        following ||
        runProcessed < 10 ||
        elapsedMs < 4000) {
      return null;
    }
    final remaining = total - processed;
    if (remaining <= 0) return null;
    final perPhotoMs = elapsedMs / runProcessed;
    return Duration(milliseconds: (perPhotoMs * remaining).round());
  }

  /// A tick from the running scan: keeps what a tick doesn't carry from [previous].
  FaceStatus mergedOnto(FaceStatus previous) => FaceStatus(
    running: running,
    paused: paused,
    userPaused: userPaused,
    done: done,
    phase: phase,
    following: following,
    batch: batch,
    recentFaceEvents: recentFaceEvents,
    refine: previous.refine,
    deferredPhotos: previous.deferredPhotos,
    tuning: previous.tuning,
    processed: processed,
    total: total,
    faces: faces,
    people: people,
    failed: failed,
    runProcessed: runProcessed,
    elapsedMs: elapsedMs,
    error: error,
    ready: error == 'no_model' ? false : previous.ready,
    thorough: previous.thorough,
    strictness: previous.strictness,
    modelsDir: previous.modelsDir,
    scanVideos: previous.scanVideos,
    videoDensity: previous.videoDensity,
    videos: previous.videos,
    videosTotal: previous.videosTotal,
  );

  factory FaceStatus.fromMap(Map<dynamic, dynamic> m) => FaceStatus(
    running: m['running'] as bool? ?? false,
    paused: m['paused'] as bool? ?? false,
    userPaused: m['userPaused'] as bool? ?? false,
    done: m['done'] as bool? ?? false,
    phase: m['phase'] as String? ?? 'scan',
    following: m['following'] as bool? ?? false,
    batch: m['batch'] as bool? ?? false,
    recentFaceEvents: [
      for (final e in (m['recentFaceEvents'] as List?) ?? const [])
        FaceEvent.fromMap(e as Map<dynamic, dynamic>),
    ],
    refine: m['refine'] as bool? ?? true,
    deferredPhotos: (m['deferredPhotos'] as num?)?.toInt() ?? 0,
    tuning: m['tuning'] as String?,
    processed: (m['processed'] as num?)?.toInt() ?? 0,
    total: (m['total'] as num?)?.toInt() ?? 0,
    faces: (m['faces'] as num?)?.toInt() ?? 0,
    people: (m['people'] as num?)?.toInt() ?? 0,
    failed: (m['failed'] as num?)?.toInt() ?? 0,
    runProcessed: (m['runProcessed'] as num?)?.toInt() ?? 0,
    elapsedMs: (m['elapsedMs'] as num?)?.toInt() ?? 0,
    error: m['error'] as String?,
    ready: m['ready'] as bool? ?? true,
    thorough: m['thorough'] as bool? ?? false,
    strictness: m['strictness'] as String? ?? 'balanced',
    modelsDir: m['modelsDir'] as String? ?? '',
    scanVideos: m['scanVideos'] as bool? ?? true,
    videoDensity: m['videoDensity'] as String? ?? 'balanced',
    videos: (m['videos'] as num?)?.toInt() ?? 0,
    videosTotal: (m['videosTotal'] as num?)?.toInt() ?? 0,
  );
}

class FaceModelInfo {
  FaceModelInfo({
    required this.kind,
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.source,
    required this.selected,
  });

  /// 'detector' or 'embedder'.
  final String kind;
  final String id;
  final String name;
  final int sizeBytes;
  /// 'bundled' or 'device'.
  final String source;
  final bool selected;

  factory FaceModelInfo.fromMap(Map<dynamic, dynamic> m) => FaceModelInfo(
    kind: m['kind'] as String,
    id: m['id'] as String,
    name: m['name'] as String,
    sizeBytes: (m['sizeBytes'] as num).toInt(),
    source: m['source'] as String,
    selected: m['selected'] as bool,
  );
}

class FaceModels {
  FaceModels({required this.dir, required this.models});

  /// Folder on the device to drop .onnx models into.
  final String dir;
  final List<FaceModelInfo> models;

  List<FaceModelInfo> ofKind(String kind) =>
      models.where((m) => m.kind == kind).toList();

  factory FaceModels.fromMap(Map<dynamic, dynamic> m) => FaceModels(
    dir: m['dir'] as String,
    models: (m['models'] as List)
        .map((e) => FaceModelInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList(),
  );
}

/// Progress of the face scan of one photo: which step, and how many faces.
class PhotoScanStatus {
  PhotoScanStatus({
    required this.stage,
    required this.faces,
    required this.total,
    required this.more,
    this.video = false,
    this.step = 0,
    this.steps = 0,
    this.relax = 0,
  });

  /// reading, detecting, recognising or placing.
  final String stage;
  final int faces;
  /// Faces being recognised.
  final int total;
  /// True while finishing a photo scanned before.
  final bool more;
  /// True while a whole video is being scanned.
  final bool video;
  /// For a video: frames looked through so far, and how many there are.
  final int step, steps;
  /// For a video: how loose the search is, 0 standard, 1 looser, 2 loosest.
  final int
  relax;

  factory PhotoScanStatus.fromMap(Map<dynamic, dynamic> m) => PhotoScanStatus(
    stage: m['stage'] as String? ?? 'reading',
    faces: (m['faces'] as num?)?.toInt() ?? 0,
    total: (m['total'] as num?)?.toInt() ?? 0,
    more: m['more'] as bool? ?? false,
    video: m['video'] as bool? ?? false,
    step: (m['step'] as num?)?.toInt() ?? 0,
    steps: (m['steps'] as num?)?.toInt() ?? 0,
    relax: (m['relax'] as num?)?.toInt() ?? 0,
  );

  /// What to tell the person, in a few words.
  String get message {
    String faceWord(int n) => n == 1 ? '1 face' : '$n faces';
    if (video) {
      switch (stage) {
        case 'detecting':
          final mode = relax >= 2
              ? 'Loosest search'
              : relax == 1
              ? 'Looser search'
              : 'Scanning';
          return steps > 0
              ? '$mode · frame $step of $steps${faces > 0 ? ' · ${faceWord(faces)} spotted' : ''}'
              : 'Opening the video';
        case 'recognising':
          return 'Identifying ${faceWord(total)}';
        case 'placing':
          return 'Matching faces to people';
        default:
          return 'Opening the video';
      }
    }
    switch (stage) {
      case 'reading':
        return 'Opening the photo';
      case 'detecting':
        return 'Looking for faces';
      case 'recognising':
        return more
            ? 'Identifying ${total == 1 ? '1 more face' : '$total more faces'}'
            : 'Found ${faceWord(faces)} · identifying';
      case 'placing':
        return faces == 0
            ? 'No faces here'
            : 'Matching ${faceWord(total == 0 ? faces : total)} to people';
      default:
        return 'Looking for faces';
    }
  }
}

/// What tapping a video's scan button would do.
class VideoScanInfo {
  VideoScanInfo(this.state, this.level, this.lastFaces);

  /// 'needs', 'done' or 'unavailable'.
  final String state;
  /// How loose the next scan is: 0 standard, 1 looser, 2 loosest.
  final int
  level;
  /// Faces the last scan kept, or null when it was never scanned.
  final int? lastFaces;

  factory VideoScanInfo.fromMap(Map<dynamic, dynamic> m) => VideoScanInfo(
    m['state'] as String? ?? 'unavailable',
    (m['level'] as num?)?.toInt() ?? 0,
    (m['lastFaces'] as num?)?.toInt(),
  );
}

/// How a video scan went.
class VideoScanResult {
  VideoScanResult(this.scanned, this.level, this.faces);

  final bool scanned;
  /// The level the scan used, as in [VideoScanInfo.level].
  final int level;
  final int faces;

  factory VideoScanResult.fromMap(Map<dynamic, dynamic> m) => VideoScanResult(
    m['scanned'] as bool? ?? false,
    (m['level'] as num?)?.toInt() ?? 0,
    (m['faces'] as num?)?.toInt() ?? 0,
  );
}
