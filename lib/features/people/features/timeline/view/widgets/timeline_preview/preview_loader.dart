part of '../timeline_preview.dart';

/// Small, large and sharp versions of the timeline's photos, kept in memory.
///
/// Everything is made to show at once. Small versions of every chosen photo are fetched in the background, the ones
/// nearest the playhead first. The sharp version of the middle ones is only asked for once the playhead has slowed
/// down. At most a few are made at once, because more only slow each other down. The latest request goes first, since
/// it is what is on screen, and a request nobody wants is dropped before it starts.
class PreviewLoader {
  static const int smallSize = 120;
  static const int largeSize = 400;

  /// For a picture shown big, such as the middle of the lens or a memory's main photo, where the large one is not
  /// enough.
  static const int sharpSize = 1080;
  static const int _maxRunning = 3;
  static const int _keepSmall = 900;
  static const int _keepLarge = 40;
  static const int _keepSharp = 10;

  /// Whether a picture shown [logical] big, on a screen with [pixelRatio], needs more than the large version.
  static bool wantsSharp(Size logical, double pixelRatio) => logical.longestSide * pixelRatio > largeSize * 1.1;

  final LinkedHashMap<String, Uint8List> _small = LinkedHashMap();
  final LinkedHashMap<String, Uint8List> _large = LinkedHashMap();
  final LinkedHashMap<String, Uint8List> _sharp = LinkedHashMap();
  final Map<String, _Job> _jobs = {};
  /// The jobs that are wanted, newest last.
  final List<_Job> _now = [];

  /// The jobs made ahead of time, in the order given.
  final List<_Job> _ahead = [];
  final Set<String> _failed = {};
  int _running = 0;

  /// What is in memory already: the sharpest version when [sharp], the large one when [large], else the small one. The
  /// picture counts as most recently used.
  Uint8List? peek(PreviewPhoto photo, {required bool large, bool sharp = false}) {
    final cache = sharp ? _sharp : (large ? _large : _small);
    final bytes = cache.remove(photo.cacheKey);
    if (bytes != null) cache[photo.cacheKey] = bytes;
    return bytes;
  }

  bool failed(PreviewPhoto photo) => _failed.contains('S${photo.cacheKey}');

  /// The picture, from memory or made on request. [wanted] says whether it is still needed once its turn comes, since
  /// a frame that has slid away does not need it any more.
  Future<Uint8List?> get(PreviewPhoto photo, {required bool large, bool sharp = false, bool Function()? wanted}) {
    final cached = peek(photo, large: large, sharp: sharp);
    if (cached != null) return Future.value(cached);
    final id = '${sharp ? 'H' : (large ? 'L' : 'S')}${photo.cacheKey}';
    if (_failed.contains(id)) return Future.value(null);

    var job = _jobs[id];
    if (job == null) {
      job = _Job(photo, large, sharp);
      _jobs[id] = job;
      _now.add(job);
    } else if (_ahead.remove(job)) {
      _now.add(job);
    }
    final completer = Completer<Uint8List?>();
    job.waiters.add(completer);
    job.wanted.add(wanted ?? () => true);
    _pump();
    return completer.future;
  }

  /// Makes the small versions of [photos] when there is nothing more urgent. With [front] they go before what is
  /// already waiting, for the ones near the playhead.
  void prefetch(Iterable<PreviewPhoto> photos, {bool front = false}) {
    final fresh = <_Job>[];
    for (final photo in photos) {
      final id = 'S${photo.cacheKey}';
      if (_small.containsKey(photo.cacheKey) || _jobs.containsKey(id) || _failed.contains(id)) continue;
      final job = _Job(photo, false)..ahead = true;
      _jobs[id] = job;
      fresh.add(job);
    }
    if (front) {
      _ahead.insertAll(0, fresh);
    } else {
      _ahead.addAll(fresh);
    }
    _pump();
  }

  void _pump() {
    while (_running < _maxRunning) {
      final _Job job;
      if (_now.isNotEmpty) {
        job = _now.removeLast();
      } else if (_ahead.isNotEmpty) {
        job = _ahead.removeAt(0);
      } else {
        return;
      }
      if (!job.stillWanted) {
        _jobs.remove(job.id);
        job.finish(null);
        continue;
      }
      _running++;
      MediaService()
          .loadThumbnail(
            uri: job.photo.uri,
            isVideo: job.photo.isVideo,
            timestampMs: job.photo.tsMs,
            size: job.sharp ? sharpSize : (job.large ? largeSize : smallSize),
          )
          .then<Uint8List?>((bytes) => bytes)
          .catchError((_) => null)
          .then((bytes) {
            _running--;
            _jobs.remove(job.id);
            if (bytes == null) {
              _failed.add(job.id);
            } else {
              final cache = job.sharp ? _sharp : (job.large ? _large : _small);
              cache[job.photo.cacheKey] = bytes;
              final keep = job.sharp ? _keepSharp : (job.large ? _keepLarge : _keepSmall);
              while (cache.length > keep) {
                cache.remove(cache.keys.first);
              }
            }
            job.finish(bytes);
            _pump();
          });
    }
  }
}

class _Job {
  _Job(this.photo, this.large, [this.sharp = false]);

  final PreviewPhoto photo;
  final bool large;

  /// The biggest version, which is [large] too. A picture shown big is finally sharpened to it.
  final bool sharp;
  final List<Completer<Uint8List?>> waiters = [];
  final List<bool Function()> wanted = [];
  bool ahead = false;

  String get id => '${sharp ? 'H' : (large ? 'L' : 'S')}${photo.cacheKey}';

  /// True when it is made ahead of time, or somebody still wants it.
  bool get stillWanted => ahead && waiters.isEmpty || wanted.any((w) => w());

  void finish(Uint8List? bytes) {
    for (final w in waiters) {
      if (!w.isCompleted) w.complete(bytes);
    }
    waiters.clear();
  }
}
