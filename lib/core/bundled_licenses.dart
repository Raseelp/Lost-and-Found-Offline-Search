import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One notice that the app carries for something it ships: the packages it is listed under, and the asset files whose
/// text is shown, joined with a blank line.
class _Notice {
  const _Notice(this.packages, this.assets);

  final List<String> packages;
  final List<String> assets;
}

const _notices = [
  _Notice(
    ['MobileCLIP-S0 model weights (Apple)'],
    ['assets/licenses/apple_mobileclip_weights_2024.txt'],
  ),
  _Notice(
    ['Face detection and recognition models (InsightFace)'],
    ['assets/licenses/insightface_models.txt'],
  ),
  _Notice(
    ['ONNX Runtime (Microsoft)'],
    ['assets/licenses/onnxruntime_mit.txt'],
  ),
  _Notice(['Space Grotesk font'], ['assets/fonts/OFL-SpaceGrotesk.txt']),
  _Notice(['Instrument Serif font'], ['assets/fonts/OFL-InstrumentSerif.txt']),
  _Notice(
    ['Photos and videos in the tour'],
    [
      'assets/tour/photos/CREDITS.txt',
      'assets/tour/faces/CREDITS.txt',
      'assets/tour/videos/CREDITS.txt',
    ],
  ),
];

/// Adds what the app ships besides its packages to the license page (Settings > About > License): the search model's
/// weights, the face models, ONNX Runtime, the fonts and the credits of the tour's photos and videos. Apple's terms
/// ask that its notice and disclaimers stay with the weights when they are redistributed, and CC BY-SA asks for the
/// credit of its photo to be shown. The texts are bundled as assets.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final notice in _notices) {
      final texts = [
        for (final asset in notice.assets) await rootBundle.loadString(asset),
      ];
      yield LicenseEntryWithLineBreaks(notice.packages, texts.join('\n\n'));
    }
  });
}
