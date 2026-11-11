import 'package:flutter/services.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/export/models/export_models.dart';

/// Exporting collections and people as zip files.
class ExportService {
  /// A folder to save a zip in (one the app may write to); null if the user gave up.
  Future<String?> pickExportFolder() async {
    try {
      return await nativeChannel.invokeMethod<String>('pickExportFolder');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') return null;
      rethrow;
    }
  }

  /// Name, size (bytes, -1 if it cannot be read) and dates (ms, 0 if unknown) of each of [uris].
  Future<List<ExportItemInfo>> exportItemInfo(List<String> uris) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('exportItemInfo', {
      'uris': uris,
    });
    return (list ?? const [])
        .map((e) => ExportItemInfo.fromMap(e as Map))
        .toList();
  }

  /// Room left on the phone's storage in bytes; -1 if it cannot be told.
  Future<int> exportFreeSpace() async =>
      await nativeChannel.invokeMethod<int>('exportFreeSpace') ?? -1;

  /// Whether a zip can be saved in Downloads without choosing a folder (Android 10 and later).
  Future<bool> exportDownloadsAvailable() async =>
      await nativeChannel.invokeMethod<bool>('exportDownloadsAvailable') ?? false;

  /// Starts making the zip described by [job] (see ExportController); false if one is already
  /// being made.
  Future<bool> startZipExport(String job) async =>
      await nativeChannel.invokeMethod<bool>('startZipExport', {'job': job}) ??
      false;

  Future<ZipExportStatus> zipExportStatus() async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'zipExportStatus',
    );
    return ZipExportStatus.fromMap(map ?? const {});
  }

  Future<void> cancelZipExport() =>
      nativeChannel.invokeMethod<bool>('cancelZipExport');

  Future<bool> shareZips(List<String> uris) async =>
      await nativeChannel.invokeMethod<bool>('shareZips', {'uris': uris}) ?? false;

  Future<bool> openDownloads() async =>
      await nativeChannel.invokeMethod<bool>('openDownloads') ?? false;
}
