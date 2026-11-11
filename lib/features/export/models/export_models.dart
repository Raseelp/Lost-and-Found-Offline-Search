
/// What the zip export needs to know about one photo or video.
class ExportItemInfo {
  const ExportItemInfo({
    required this.name,
    required this.size,
    required this.takenMs,
    required this.modifiedMs,
  });

  final String name;

  /// Bytes; -1 when the file cannot be read.
  final int size;
  final int takenMs, modifiedMs;

  bool get readable => size >= 0;

  factory ExportItemInfo.fromMap(Map<dynamic, dynamic> m) => ExportItemInfo(
    name: m['name'] as String? ?? 'file',
    size: (m['size'] as num?)?.toInt() ?? -1,
    takenMs: (m['takenMs'] as num?)?.toInt() ?? 0,
    modifiedMs: (m['modifiedMs'] as num?)?.toInt() ?? 0,
  );
}

/// A zip that has been made.
class ZipExportResult {
  const ZipExportResult({
    required this.name,
    required this.uri,
    required this.bytes,
  });

  final String name, uri;
  final int bytes;
}

/// What the zip export is doing (see ZipExportState in the native code).
class ZipExportStatus {
  const ZipExportStatus({
    required this.id,
    required this.phase,
    required this.filesTotal,
    required this.filesDone,
    required this.bytesTotal,
    required this.bytesDone,
    required this.partsTotal,
    required this.part,
    required this.skipped,
    required this.currentName,
    required this.error,
    required this.results,
  });

  final int id;

  /// idle, preparing, writing, done, failed or cancelled.
  final String phase;
  final int filesTotal,
      filesDone,
      bytesTotal,
      bytesDone,
      partsTotal,
      part,
      skipped;
  final String currentName, error;
  final List<ZipExportResult> results;

  bool get running => phase == 'preparing' || phase == 'writing';

  double get fraction =>
      bytesTotal > 0 ? (bytesDone / bytesTotal).clamp(0.0, 1.0) : 0.0;

  factory ZipExportStatus.fromMap(Map<dynamic, dynamic> m) => ZipExportStatus(
    id: (m['id'] as num?)?.toInt() ?? 0,
    phase: m['phase'] as String? ?? 'idle',
    filesTotal: (m['filesTotal'] as num?)?.toInt() ?? 0,
    filesDone: (m['filesDone'] as num?)?.toInt() ?? 0,
    bytesTotal: (m['bytesTotal'] as num?)?.toInt() ?? 0,
    bytesDone: (m['bytesDone'] as num?)?.toInt() ?? 0,
    partsTotal: (m['partsTotal'] as num?)?.toInt() ?? 0,
    part: (m['part'] as num?)?.toInt() ?? 0,
    skipped: (m['skipped'] as num?)?.toInt() ?? 0,
    currentName: m['currentName'] as String? ?? '',
    error: m['error'] as String? ?? '',
    results: [
      for (final r in (m['results'] as List? ?? const []))
        ZipExportResult(
          name: (r as Map)['name'] as String? ?? '',
          uri: r['uri'] as String? ?? '',
          bytes: (r['bytes'] as num?)?.toInt() ?? 0,
        ),
    ],
  );
}
