import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lost_and_found/features/model_download/models/model_status.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

/// Downloading, checking and deleting the search model.
class ModelService {
  static const _modelDownloadChannel = EventChannel(
    'lostandfound/modelDownload',
  );

  /// The search (CLIP) models are downloaded and verified.
  Future<bool> areModelsReady() async {
    return await nativeChannel.invokeMethod<bool>('areModelsReady') ?? false;
  }

  Future<List<ModelStatus>> getModelInfo() async {
    final results = await nativeChannel.invokeMethod<List<dynamic>>('getModelInfo');
    return (results ?? [])
        .cast<Map>()
        .map((e) => ModelStatus.fromMap(e))
        .toList();
  }

  /// Downloads the search (CLIP) models, the only ones that are downloaded. The result says whether they are on the
  /// device. Progress is reported via [modelDownloadProgressStream]; this only resolves once the download finishes or
  /// fails.
  Future<bool> downloadModels() async {
    try {
      return await nativeChannel.invokeMethod<bool>('downloadModels') ?? false;
    } on PlatformException catch (e) {
      debugPrint('downloadModels failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  Future<void> cancelModelDownload() async {
    await nativeChannel.invokeMethod('cancelModelDownload');
  }

  /// Deletes the downloaded (search) models; the face models are part of the app.
  Future<void> deleteModels() async {
    await nativeChannel.invokeMethod('deleteModels');
  }

  Stream<ModelDownloadProgress> modelDownloadProgressStream() {
    return _modelDownloadChannel.receiveBroadcastStream().map(
      (event) =>
          ModelDownloadProgress.fromMap(Map<dynamic, dynamic>.from(event)),
    );
  }
}
