/// What the Library tab's completion card shows once a scan runs to the end.
class ScanSummary {
  const ScanSummary({required this.total, required this.failed});

  final int total;
  final int failed;

  int get indexed => (total - failed).clamp(0, total);
}

/// Whether a scan covers the whole phone or the folders the person picked.
enum PickingMode { device, folder }
