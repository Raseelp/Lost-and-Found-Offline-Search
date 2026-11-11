import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';

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

/// What the tour needs from the download: its state, and starting it. The first run uses the real one. The Help
/// section of Settings has none to show (see [IdleTourDownload]).
abstract class TourDownload extends ChangeNotifier {
  TourDownloadState get state;

  /// Starts at once (or, when it is paused, carries on).
  void start();

  /// Stops for now, keeping what has been downloaded.
  void pause();

  /// Carries on from where [pause] stopped.
  void resume();
}

/// The app's real model download, taken from [NativeController].
class RealTourDownload extends TourDownload {
  RealTourDownload() : _native = Get.find<NativeController>() {
    _disposeListener = _native.addListener(_changed);
  }

  final NativeController _native;
  VoidCallback? _disposeListener;
  TourDownloadState _state = const TourDownloadState();

  /// True when the person paused it. The download underneath is stopped, and its partial files are kept and picked up
  /// again.
  bool _paused = false;

  /// True when [resume] was called while the stopped download was still winding down. The download then starts as
  /// soon as that is over.
  bool _resumeWanted = false;

  @override
  TourDownloadState get state => _compute();

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

/// For the Help section of Settings. The tour is seen again with no download to show, because the models are already
/// on the phone.
class IdleTourDownload extends TourDownload {
  @override
  TourDownloadState get state => const TourDownloadState();

  @override
  void start() {}

  @override
  void pause() {}

  @override
  void resume() {}
}
