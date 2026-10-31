# Development

Building, testing, debugging, and how the search model files are made and hosted.

## Build and run

```bash
git clone https://github.com/Raseelp/Lost-and-Found-Offline-Search.git
cd Lost-and-Found-Offline-Search
flutter pub get
flutter run
```

Release builds are signed with the key described in `android/key.properties` (not in the repo).

## Debug builds

A debug build installs as a second app (`.debug`) next to the real one, with its own data, so it
never replaces or wipes the app in use. It includes two developer screens that time the models on
a phone: `ModelBenchActivity` and `ScanBenchActivity` (`android/app/src/debug/`).

Debug builds download the search model from the same GitHub release as release builds.

## Preview builds

A preview build is compiled like a release, so it runs at full speed, but installs as a third app
(`.preview`, named "L&F preview") with its own data, like a debug build. It is signed with the debug
key, so it needs no release key and never replaces the app in use. It has no developer screens.

```bash
cd android && ./gradlew assemblePreview -Ptarget-platform=android-arm64
```

The APK is `build/app/outputs/apk/preview/app-preview.apk`. Flutter also copies it to
`build/app/outputs/flutter-apk/app-release.apk`; that copy is the preview, not a release build.

## Tests

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

Covers the zip writer (including that other zip tools can read its output), the search index
header, and the memories, timeline and date logic.

```bash
flutter test
```

Dart tests in `test/`, for example stopping a scan (`stop_indexing_test.dart`).

## App icon

The sources are in `design/app-icon/`: `icon.svg` (the whole icon, used for the older square icons and the
Play Store image) and the three layers of Android's adaptive icon, on a 108 unit canvas: `background.svg` (the
landscape, filling the canvas edge to edge), `foreground.svg` (the carved lf, kept inside the 66 unit safe area
so no launcher shape cuts it) and `monochrome.svg` (the lf alone, which Android 13 and later draw when themed
icons are on). `res/mipmap-anydpi-v26/ic_launcher.xml` puts them together. To change the icon, edit the SVGs
and render the PNGs again with `render.js`: `ic_launcher.png` at 48, 72, 96, 144 and 192 px and the three
layers at 108, 162, 216, 324 and 432 px (mdpi to xxxhdpi).

## Reduced motion

With "Remove animations" on, Flutter runs every one-off animation 20 times faster, so it is over in a
frame or two. Page transitions, dialogs, sheets and animated widgets need nothing more. The rest is in
`lib/utils/motion.dart`:

- A controller that keeps time rather than moving anything, such as a story's progress, is made with
  `AnimationBehavior.preserve`, or it would run 20 times faster too.
- A looping controller is started with `loopUnlessCalm` from `didChangeDependencies`, so it stops on a
  still frame when motion is off and follows the setting when it changes.
- Springs and tickers of our own check `calm(context)` and jump to where they would settle.
- A scroll or page move uses `glideTo`, or `jumpToPage` when `calm(context)` is true.

## Logs

```bash
adb logcat -s FaceScanner FaceTuner   # face scan timing and tuning
adb logcat -s LostFoundBench          # performance logs for indexing, faces and search
```

The performance logs are on unless turned off in Settings > Diagnostics.

## The search model files

- `export_clip/export_mobileclip.py` makes the two ONNX files from Apple's 2024 MobileCLIP
  checkpoint (`--variant s0|s1|s2`, default `s0`): image tower in fp32, text tower in int8.
- `export_clip/verify_mobileclip.py` compares them with Apple's PyTorch model on the tour's sample
  photos, and checks the app's tokenizer against open_clip's.
- `export_clip/MOBILECLIP_SOURCE.md` records where the weights came from (address, date, size,
  hashes) and what was measured. The 2024 licence texts are in `export_clip/licenses/`.
- The files are hosted in the `models-v1` GitHub release. The app checks their SHA-256 hashes
  after downloading (`embedder/models/`). Steps and checksums: [model_host/README.md](../model_host/README.md).

## Face models

The face detector (`det_2.5g.onnx`) and recognition model (`w600k_mbf.onnx`) are bundled in
`android/app/src/main/assets/`. Each model is described by a spec (input size, normalisation,
channel order), so either can be swapped without code changes; see [Architecture](architecture.md#faces).
