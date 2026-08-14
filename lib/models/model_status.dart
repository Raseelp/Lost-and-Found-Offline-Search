class ModelStatus {
  final String id;
  final String fileName;
  final int sizeBytes;
  final bool downloaded;
  final bool verified;

  const ModelStatus({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.downloaded,
    required this.verified,
  });

  factory ModelStatus.fromMap(Map<dynamic, dynamic> map) {
    return ModelStatus(
      id: map['id'] ?? '',
      fileName: map['fileName'] ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      downloaded: map['downloaded'] as bool? ?? false,
      verified: map['verified'] as bool? ?? false,
    );
  }
}

class ModelDownloadProgress {
  final String modelId;
  final String modelFileName;
  final int bytesForModel;
  final int totalBytesForModel;
  final int overallBytesDownloaded;
  final int overallTotalBytes;
  final bool done;

  const ModelDownloadProgress({
    required this.modelId,
    required this.modelFileName,
    required this.bytesForModel,
    required this.totalBytesForModel,
    required this.overallBytesDownloaded,
    required this.overallTotalBytes,
    required this.done,
  });

  factory ModelDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return ModelDownloadProgress(
      modelId: map['modelId'] ?? '',
      modelFileName: map['modelFileName'] ?? '',
      bytesForModel: (map['bytesForModel'] as num?)?.toInt() ?? 0,
      totalBytesForModel: (map['totalBytesForModel'] as num?)?.toInt() ?? 0,
      overallBytesDownloaded:
          (map['overallBytesDownloaded'] as num?)?.toInt() ?? 0,
      overallTotalBytes: (map['overallTotalBytes'] as num?)?.toInt() ?? 0,
      done: map['done'] as bool? ?? false,
    );
  }

  factory ModelDownloadProgress.empty() {
    return const ModelDownloadProgress(
      modelId: '',
      modelFileName: '',
      bytesForModel: 0,
      totalBytesForModel: 0,
      overallBytesDownloaded: 0,
      overallTotalBytes: 0,
      done: false,
    );
  }

  double get overallFraction => overallTotalBytes == 0
      ? 0.0
      : (overallBytesDownloaded / overallTotalBytes).clamp(0.0, 1.0);

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
