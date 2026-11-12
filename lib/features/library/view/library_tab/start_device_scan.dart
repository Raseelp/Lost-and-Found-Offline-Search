part of '../library_tab.dart';

Future<void> _startDeviceScan(
  BuildContext context,
  LibraryController controller,
) async {
  final granted = await controller.requestMediaPermission(
    contentMode: controller.selectedContentMode,
    explain: _explainMediaAccess,
  );
  if (!granted) return;
  controller.pickAndScanFolders(isScanEntirePhone: true);
}

bool _explaining = false;

/// Shows the sheet that comes before Android's photo prompt. It uses the app's own navigator, because the screen that
/// started the scan may already be closed (the export screen is closed on the way to the Library). A second tap while
/// the sheet is open is turned down, and without a screen to show it on the prompt goes ahead.
Future<bool> _explainMediaAccess() async {
  if (_explaining) return false;
  final host = Get.context;
  if (host == null || !host.mounted) return true;
  _explaining = true;
  try {
    return await showMediaAccessSheet(host);
  } finally {
    _explaining = false;
  }
}
