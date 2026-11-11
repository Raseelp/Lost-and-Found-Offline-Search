part of '../library_tab.dart';

Future<void> _startDeviceScan(
  BuildContext context,
  LibraryController controller,
) async {
  final granted = await controller.requestMediaPermission(
    contentMode: controller.selectedContentMode,
  );
  if (!granted) return;
  controller.pickAndScanFolders(isScanEntirePhone: true);
}
