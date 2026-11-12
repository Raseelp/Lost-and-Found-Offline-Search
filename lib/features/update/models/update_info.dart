/// Where an update of the app is: not there, waiting in Google Play, on its way, or ready to install.
enum UpdateStage { none, available, downloading, downloaded }

/// What Google Play said about an update.
class UpdateInfo {
  const UpdateInfo({this.stage = UpdateStage.none, this.versionCode = 0});

  factory UpdateInfo.fromMap(Map<Object?, Object?> map) {
    return UpdateInfo(
      stage: switch (map['state']) {
        'available' => UpdateStage.available,
        'downloading' => UpdateStage.downloading,
        'downloaded' => UpdateStage.downloaded,
        _ => UpdateStage.none,
      },
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
    );
  }

  final UpdateStage stage;

  /// The version code of the update that is waiting.
  final int versionCode;
}

/// A change in how the download is going, sent while an update is on its way.
class UpdateEvent {
  const UpdateEvent(this.status, {this.progress});

  factory UpdateEvent.fromMap(Map<Object?, Object?> map) {
    final bytes = (map['bytes'] as num?)?.toDouble();
    final total = (map['total'] as num?)?.toDouble();
    return UpdateEvent(
      map['status'] as String? ?? '',
      progress: bytes != null && total != null && total > 0 ? (bytes / total).clamp(0.0, 1.0) : null,
    );
  }

  /// 'downloading', 'downloaded', 'installed' or 'failed'.
  final String status;

  /// How much of the update has come, from 0 to 1, when it is known.
  final double? progress;
}
