import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser, and says so with a short message when it cannot be opened.
Future<void> openLink(String url) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) AppToast.show("Couldn't open the link.");
}
