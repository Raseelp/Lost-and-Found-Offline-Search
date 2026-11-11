import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/core/bundled_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled notice loads and is listed under its name', () async {
    registerBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final byPackage = {
      for (final e in entries)
        for (final p in e.packages) p: e.paragraphs.map((x) => x.text).join(' '),
    };

    expect(byPackage.keys, containsAll([
      'MobileCLIP-S0 model weights (Apple)',
      'Face detection and recognition models (InsightFace)',
      'ONNX Runtime (Microsoft)',
      'Space Grotesk font',
      'Instrument Serif font',
      'Photos and videos in the tour',
    ]));
    expect(byPackage['Photos and videos in the tour'], contains('CC BY-SA 3.0'));
    expect(byPackage['Photos and videos in the tour'], contains('Dubyna'));
    expect(byPackage['ONNX Runtime (Microsoft)'], contains('Microsoft Corporation'));
    expect(byPackage['Face detection and recognition models (InsightFace)'], contains('non-commercial'));
    expect(byPackage['Space Grotesk font'], contains('SIL OPEN FONT LICENSE'));
    expect(byPackage['Instrument Serif font'], contains('SIL OPEN FONT LICENSE'));
  });
}
