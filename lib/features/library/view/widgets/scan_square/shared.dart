part of '../scan_square.dart';

/// What a finished scan has to say.
class ScanChipSummary {
  const ScanChipSummary({required this.indexed, required this.failed, required this.people});

  final int indexed, failed, people;
}

/// The numbers a scan has to tell while it runs.
class ScanChipStats {
  const ScanChipStats({
    required this.indexed,
    required this.total,
    this.found,
    this.faceDone = 0,
    this.faceTotal = 0,
    this.people = 0,
    this.tuning = false,
    this.etaMs,
  });

  /// Items indexed so far, of [total] (0 while the folder is still being walked, when [found]
  /// says how many files it has found).
  final int indexed, total;
  final int? found;

  /// Photos done of the batch being worked on, and people found so far.
  final int faceDone, faceTotal, people;

  /// The faces are doing their one-off speed test.
  final bool tuning;

  /// How long indexing has left, in milliseconds (null until it can be told).
  final int? etaMs;
}

const Rect _photoBox = Rect.fromLTWH(30, 34, 280, 206);

const Rect _strip = Rect.fromLTWH(30, 252, 280, 56);

/// The queue strip: thumbnails from [_queueLeft] to [_queueRight] (where the last one starts).
const double _tileSize = 34;

const double _queueLeft = 36;

const double _queueRight = 270;

const double _faceCycle = 4.8;

const int _traySlots = 5;

/// Cells in the memory array along the top of the bank (two rows).
const int _memoryCellCount = 136;

/// A decoded photo.
class _Pic {
  _Pic(this.image);

  final ui.Image image;

  /// The average colour of each of the 7 x 7 patches of the photo's middle square (the part the
  /// model reads), row by row; null if they could not be read.
  List<Color>? tones;

  double get w => image.width.toDouble();
  double get h => image.height.toDouble();
}

/// The photos waiting for the next face batch, as the scan reports them.
class OrbitQueueInfo {
  const OrbitQueueInfo({
    required this.count,
    required this.ms,
    required this.photos,
    required this.windowMs,
    required this.at,
  });

  /// Photos waiting, and milliseconds since the last batch ended, as of [at].
  final int count, ms;

  /// A batch starts at this many photos, or this many milliseconds, whichever comes first.
  final int photos, windowMs;
  final DateTime at;

  /// How full the queue is, 0..1.
  double get fill {
    final waited = ms + DateTime.now().difference(at).inMilliseconds;
    return math.max(count / photos, waited / windowMs).clamp(0.0, 1.0);
  }
}

/// The part of the photo that is the face, as a square, in the photo's own pixels.
Rect _faceCrop(_Pic pic, FaceEvent e) {
  final b = e.box.length == 4 ? e.box : const [.3, .3, .7, .7];
  final cx = (b[0] + b[2]) / 2 * pic.w, cy = (b[1] + b[3]) / 2 * pic.h;
  var side = math.max((b[2] - b[0]) * pic.w, (b[3] - b[1]) * pic.h) * 1.35;
  final shortSide = math.min(pic.w, pic.h);
  side = side.clamp(math.min(8.0, shortSide), shortSide);
  final left = (cx - side / 2).clamp(0.0, pic.w - side);
  final top = (cy - side / 2).clamp(0.0, pic.h - side);
  return Rect.fromLTWH(left, top, side, side);
}
