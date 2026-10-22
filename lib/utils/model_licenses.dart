import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Adds the license of the search model's weights to the app's license page (Settings > About > License), where it
/// is listed with the packages' own. Apple's terms ask that its notice and disclaimers stay with the weights when
/// they are redistributed; the app carries them in `assets/licenses/` and shows them here.
void registerModelLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/apple_mobileclip_weights_2024.txt');
    yield LicenseEntryWithLineBreaks(['MobileCLIP-S2 model weights (Apple)'], text);
  });
}
