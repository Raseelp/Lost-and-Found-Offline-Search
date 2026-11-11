/// A screenshot or screen recording picked for a problem report.
class ReportAttachment {
  const ReportAttachment({
    required this.uri,
    required this.name,
    required this.size,
    required this.isVideo,
  });

  factory ReportAttachment.fromMap(Map<Object?, Object?> map) {
    return ReportAttachment(
      uri: map['uri'] as String,
      name: map['name'] as String,
      size: (map['size'] as num).toInt(),
      isVideo: map['video'] as bool,
    );
  }

  final String uri;
  final String name;

  /// In bytes. Zero when the system did not say.
  final int size;
  final bool isVideo;

  /// Mail apps refuse a message with more than this in attachments, so a report is not sent above it.
  static const int maxTotalBytes = 20 * 1024 * 1024;

  static int totalSize(Iterable<ReportAttachment> all) => all.fold(0, (sum, a) => sum + a.size);

  /// A size for people: megabytes with one decimal (none when it is whole), kilobytes below a megabyte.
  static String formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    final mb = bytes / (1024 * 1024);
    return mb == mb.roundToDouble() ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}
