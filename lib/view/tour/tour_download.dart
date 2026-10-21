import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/model_status.dart';

/// Where the search-model download is, as the tour shows it.
enum TourDownloadPhase {
  idle,
  connecting,
  downloading,
  verifying,
  paused,
  done,
  error,
}

class TourDownloadState {
  const TourDownloadState({
    this.phase = TourDownloadPhase.idle,
    this.fraction = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error = '',
  });

  final TourDownloadPhase phase;

  /// 0 to 1.
  final double fraction;
  final int downloadedBytes, totalBytes;
  final String error;

  bool get running =>
      phase == TourDownloadPhase.connecting ||
      phase == TourDownloadPhase.downloading ||
      phase == TourDownloadPhase.verifying;

  bool get done => phase == TourDownloadPhase.done;

  /// Stopped by the person, with what is already downloaded kept; it carries on from there.
  bool get paused => phase == TourDownloadPhase.paused;

  int get percent => (fraction * 100).floor().clamp(0, 100);

  String get totalLabel =>
      totalBytes > 0 ? ModelDownloadProgress.formatBytes(totalBytes) : '';
}

/// What the tour needs from the download: its state, and starting it. The first run uses the real one;
/// Settings > Help uses a simulated one (so the tour can be seen again without downloading anything).
abstract class TourDownload extends ChangeNotifier {
  TourDownloadState get state;

  /// Whether this is only pretending (Help).
  bool get simulated;

  /// Starts at once (or, when it is paused, carries on).
  void start();

  /// Stops for now, keeping what has been downloaded.
  void pause();

  /// Carries on from where [pause] stopped.
  void resume();
}

/// The real thing: the app's model download (see NativeController).
class RealTourDownload extends TourDownload {
  RealTourDownload() : _native = Get.find<NativeController>() {
    _disposeListener = _native.addListener(_changed);
  }

  final NativeController _native;
  VoidCallback? _disposeListener;
  TourDownloadState _state = const TourDownloadState();

  // Paused by the person (the download underneath is stopped, its partial files are kept and picked up again).
  bool _paused = false;

  // Resume was asked for while the stopped download was still winding down: it starts as soon as that is over.
  bool _resumeWanted = false;

  @override
  TourDownloadState get state => _compute();

  @override
  bool get simulated => false;

  TourDownloadState _compute() {
    final total = _native.pendingDownloadBytes > 0
        ? _native.pendingDownloadBytes
        : _native.searchModelBytes;
    if (_native.modelsReady && !_native.isDownloadingModels) {
      return TourDownloadState(
        phase: TourDownloadPhase.done,
        fraction: 1,
        downloadedBytes: total,
        totalBytes: total,
      );
    }
    if (_paused) {
      final p = _native.downloadProgress;
      return TourDownloadState(
        phase: TourDownloadPhase.paused,
        fraction: p.overallFraction,
        downloadedBytes: p.overallBytesDownloaded,
        totalBytes: p.overallTotalBytes > 0 ? p.overallTotalBytes : total,
      );
    }
    if (_native.isDownloadingModels) {
      final p = _native.downloadProgress;
      final phase = p.overallTotalBytes == 0
          ? TourDownloadPhase.connecting
          : (p.isVerifying
                ? TourDownloadPhase.verifying
                : TourDownloadPhase.downloading);
      return TourDownloadState(
        phase: phase,
        fraction: p.overallFraction,
        downloadedBytes: p.overallBytesDownloaded,
        totalBytes: p.overallTotalBytes > 0 ? p.overallTotalBytes : total,
      );
    }
    if (_native.downloadError.isNotEmpty) {
      return TourDownloadState(
        phase: TourDownloadPhase.error,
        totalBytes: total,
        error: _native.downloadError,
      );
    }
    return TourDownloadState(totalBytes: total);
  }

  void _changed() {
    if (_resumeWanted && !_native.isDownloadingModels) {
      _resumeWanted = false;
      unawaited(_native.startModelDownload());
    }
    final next = _compute();
    if (next.phase == _state.phase &&
        next.fraction == _state.fraction &&
        next.totalBytes == _state.totalBytes) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void start() {
    if (_paused) {
      resume();
      return;
    }
    unawaited(_native.startModelDownload());
    _changed();
    notifyListeners();
  }

  @override
  void pause() {
    if (_paused || !_native.isDownloadingModels) return;
    _paused = true;
    unawaited(_native.cancelModelDownload());
    _changed();
    notifyListeners();
  }

  @override
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_native.isDownloadingModels) {
      // The stopped download has not finished stopping yet.
      _resumeWanted = true;
    } else {
      unawaited(_native.startModelDownload());
    }
    _changed();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeListener?.call();
    super.dispose();
  }
}

/// Pretends to download (about fifteen seconds), for Settings > Help: nothing is fetched and nothing is
/// stored. The size is the real one. To be removed once the tour no longer needs a stand-in.
class SimulatedTourDownload extends TourDownload {
  SimulatedTourDownload()
    : _total = Get.find<NativeController>().searchModelBytes > 0
          ? Get.find<NativeController>().searchModelBytes
          : _typicalBytes;

  // The usual size, for when the models are already on the phone and there is no size to read.
  static const int _typicalBytes = 606076928;

  final int _total;
  Timer? _timer;
  late TourDownloadState _state = TourDownloadState(totalBytes: _total);

  // Each tick moves on by a bit more than a thousandth, with the odd pause, so it looks like a real transfer.
  static const _tick = Duration(milliseconds: 120);
  static const _connectingTicks = 8;
  static const _verifyingTicks = 10;
  int _ticks = 0;

  @override
  TourDownloadState get state => _state;

  @override
  bool get simulated => true;

  @override
  void start() {
    if (_state.paused) {
      resume();
      return;
    }
    if (_timer != null || _state.done) return;
    _ticks = 0;
    _state = TourDownloadState(
      phase: TourDownloadPhase.connecting,
      totalBytes: _total,
    );
    notifyListeners();
    _timer = Timer.periodic(_tick, (_) => _step());
  }

  @override
  void pause() {
    if (_timer == null || !_state.running) return;
    _timer?.cancel();
    _timer = null;
    _state = TourDownloadState(
      phase: TourDownloadPhase.paused,
      fraction: _state.fraction,
      downloadedBytes: _state.downloadedBytes,
      totalBytes: _total,
    );
    notifyListeners();
  }

  @override
  void resume() {
    if (!_state.paused) return;
    _state = TourDownloadState(
      phase: _state.fraction > 0
          ? TourDownloadPhase.downloading
          : TourDownloadPhase.connecting,
      fraction: _state.fraction,
      downloadedBytes: _state.downloadedBytes,
      totalBytes: _total,
    );
    notifyListeners();
    _timer = Timer.periodic(_tick, (_) => _step());
  }

  void _step() {
    _ticks++;
    if (_ticks <= _connectingTicks) return;
    final downloadTicks = _ticks - _connectingTicks;
    // 100 ticks of downloading with a slight ease, then a short check.
    const length = 100;
    if (downloadTicks <= length) {
      final t = downloadTicks / length;
      final eased = t < 0.5 ? 2 * t * t : 1 - (1 - t) * (1 - t) * 2 + 0.0;
      final fraction = (0.6 * t + 0.4 * eased).clamp(0.0, 1.0);
      _state = TourDownloadState(
        phase: TourDownloadPhase.downloading,
        fraction: fraction,
        downloadedBytes: (fraction * _total).round(),
        totalBytes: _total,
      );
    } else if (downloadTicks <= length + _verifyingTicks) {
      _state = TourDownloadState(
        phase: TourDownloadPhase.verifying,
        fraction: 1,
        downloadedBytes: _total,
        totalBytes: _total,
      );
    } else {
      _timer?.cancel();
      _timer = null;
      _state = TourDownloadState(
        phase: TourDownloadPhase.done,
        fraction: 1,
        downloadedBytes: _total,
        totalBytes: _total,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
