import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';
import 'package:lost_and_found/features/model_download/services/model_service.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';

class ModelDownloadController extends GetxController {
  LibraryController get _library => Get.find<LibraryController>();

  /// Whether the search (CLIP) models are ready. They are the only models downloaded, since the face models are part of
  /// the app. The setup screen shows until this is true.
  bool modelsReady = false;

  bool isCheckingModels = true;

  List<ModelStatus> modelStatuses = [];

  bool isDownloadingModels = false;

  ModelDownloadProgress downloadProgress = ModelDownloadProgress.empty();

  String downloadError = '';

  StreamSubscription<ModelDownloadProgress>? _downloadSub;

  /// The download speed in bytes per second over the last few seconds, smoothed. It is null until there is a reading.
  double? downloadBytesPerSecond;

  DateTime? _speedAt;

  int _speedBytes = 0;

  /// Time left at the current speed, or null while unknown.
  Duration? get downloadEta {
    final rate = downloadBytesPerSecond;
    final progress = downloadProgress;
    if (rate == null || rate <= 0 || progress.overallTotalBytes == 0) {
      return null;
    }
    final left = progress.overallTotalBytes - progress.overallBytesDownloaded;
    if (left <= 0) return null;
    return Duration(seconds: (left / rate).round());
  }

  void _updateDownloadSpeed(ModelDownloadProgress progress) {
    final now = DateTime.now();
    final at = _speedAt;
    if (at == null || progress.overallBytesDownloaded < _speedBytes) {
      _speedAt = now;
      _speedBytes = progress.overallBytesDownloaded;
      return;
    }
    final seconds = now.difference(at).inMilliseconds / 1000.0;
    if (seconds < 1.0) return;
    final instant = (progress.overallBytesDownloaded - _speedBytes) / seconds;
    downloadBytesPerSecond = downloadBytesPerSecond == null
        ? instant
        : downloadBytesPerSecond! * 0.6 + instant * 0.4;
    _speedAt = now;
    _speedBytes = progress.overallBytesDownloaded;
  }

  List<ModelStatus> get _searchModels =>
      modelStatuses.where((m) => m.group == 'search').toList();

  /// Size of the search (CLIP) models together.
  int get searchModelBytes =>
      _searchModels.fold<int>(0, (sum, m) => sum + m.sizeBytes);

  /// True once the search models are downloaded and verified.
  bool get searchModelsVerified =>
      _searchModels.isNotEmpty && _searchModels.every((m) => m.verified);

  /// What the setup screen's button would download (whatever isn't there yet).
  int get pendingDownloadBytes {
    var total = 0;
    if (!searchModelsVerified) total += searchModelBytes;
    return total;
  }

  /// Redoes the things computed while the models were missing. Collection counts and covers are empty then, and nothing
  /// else would redo them when the search models come back, by a finished download or a check that finds them.
  Future<void> _modelsBecameReady() async {
    await _library.refreshLibraryStats();
    _library.refreshCollections();
  }

  Future<void> checkModelsReady() async {
    final wasReady = modelsReady;
    try {
      modelsReady = await ModelService().areModelsReady();
      modelStatuses = await ModelService().getModelInfo();
    } finally {
      isCheckingModels = false;
      update();
    }
    if (!wasReady && modelsReady) unawaited(_modelsBecameReady());
  }

  /// Downloads the search models if they are not on the device yet. Whatever happened, cancelled or failed, it ends by
  /// reading what is really on the device, because the setup screen goes by that.
  Future<void> startModelDownload() async {
    if (isDownloadingModels) return;

    isDownloadingModels = true;
    downloadError = '';
    downloadProgress = ModelDownloadProgress.empty();
    downloadBytesPerSecond = null;
    _speedAt = null;
    _speedBytes = 0;
    update();

    _downloadSub = ModelService().modelDownloadProgressStream().listen((
      progress,
    ) {
      downloadProgress = progress;
      _updateDownloadSpeed(progress);
      update();
    });

    try {
      await ModelService().downloadModels();
    } on PlatformException catch (e) {
      downloadError = e.message ?? e.code;
    } catch (e) {
      downloadError = e.toString();
    } finally {
      await _downloadSub?.cancel();
      _downloadSub = null;
      final wasReady = modelsReady;
      try {
        modelsReady = await ModelService().areModelsReady();
        modelStatuses = await ModelService().getModelInfo();
      } catch (_) {}
      isDownloadingModels = false;
      update();
      if (!wasReady && modelsReady) unawaited(_modelsBecameReady());
    }
  }

  Future<void> cancelModelDownload() async {
    await ModelService().cancelModelDownload();
  }

  /// Deletes the downloaded (search) models. The app then falls back to the setup screen
  /// (see AppGate); the face models are part of the app and stay.
  Future<void> deleteModels() async {
    await ModelService().deleteModels();
    downloadError = '';
    await checkModelsReady();
  }
}
