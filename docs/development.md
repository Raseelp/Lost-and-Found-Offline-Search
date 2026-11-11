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
header, the memories, timeline and date logic, the scan, stories and finish-indexing notifications, the face
pictures, the face quality score and cluster settings, the embedding maths, the rolling log file and the text of the log.

```bash
flutter test
```

Dart tests in `test/`. The folders follow `lib/`, for example `test/features/search/services/`.
They cover the search tokenizer, the story planner, the toast, the Remove animations helpers, the
splash timeline and its lifecycle, the memory and timeline models, and stopping a scan.

To run one file, pass its path, for example `flutter test test/core/widgets/app_toast_test.dart`.
To run one Kotlin class, use `./gradlew :app:testDebugUnitTest --tests "*EmbeddingMathTest"`.

The face clusterer, face aligner, memory planner and image preprocessing need Android classes
and are not covered by these tests.

GitHub Actions (`.github/workflows/tests.yml`) runs the analyzer, the Dart tests and the Kotlin
tests on every push to `main` and on every pull request.

## App icon

The sources are in `design/app-icon/`: `icon.svg` (the whole icon, used for the older square icons and the
Play Store image) and the three layers of Android's adaptive icon, on a 108 unit canvas: `background.svg` (the
landscape, filling the canvas edge to edge, split in two: the app's own colours on the left and the earlier blue
and green on the right), `foreground.svg` (the carved lf, teal on the left and white on the right, with the white
slider line and its round handle; the lf and the handle are kept inside the 66 unit safe area so no launcher shape
cuts them) and `monochrome.svg` (the lf alone, which Android 13 and later draw when themed icons are on). `res/mipmap-anydpi-v26/ic_launcher.xml` puts them together. To change the icon, edit the SVGs
and render the PNGs again with `render.js`: `ic_launcher.png` at 48, 72, 96, 144 and 192 px and the three
layers at 108, 162, 216, 324 and 432 px (mdpi to xxxhdpi).

## Reduced motion

With "Remove animations" on, Flutter runs every one-off animation 20 times faster, so it is over in a
frame or two. Page transitions, dialogs, sheets and animated widgets need nothing more. The rest is in
`lib/core/theme/motion.dart`:

- A controller that keeps time rather than moving anything, such as a story's progress, is made with
  `AnimationBehavior.preserve`, or it would run 20 times faster too.
- A looping controller is started with `loopUnlessCalm` from `didChangeDependencies`, so it stops on a
  still frame when motion is off and follows the setting when it changes.
- Springs and tickers of our own check `calm(context)` and jump to where they would settle.
- A scroll or page move uses `glideTo`, or `jumpToPage` when `calm(context)` is true.
- The start animation shows a still picture and the messages appear without sliding (see below).

## Start animation

The start animation is drawn in Flutter over the app (`lib/features/home/features/splash/`, mounted in `main.dart`), not by Android's own
splash screen. Android 12 and newer show a plain white splash with no icon (`res/values-v31/styles.xml`) and the
launch window is white in dark mode too, so nothing jumps when the first Flutter frame comes.

- `splash_timeline.dart` is the timing as plain maths: the icon fades in, the slider sweeps, a big lens grows out of
  the tile, glides over the screen and widens until the app shows through it. `splash_painter.dart` draws it and
  `splash_overlay.dart` runs the clocks. The whole thing is about 2.9 s (`SplashTimeline.slowdown` stretches or
  shortens it).
- The app is held back (`SplashGate`) until the icon has appeared, so building the first screen does not land in
  the middle of the animation. The animation then waits for the app's thread to be quiet (at least 0.35 s, at most
  1.5 s) before the sweep and the lens play, and the sky keeps drifting while it waits.
- The sky behind the tile is drawn once as a picture when the lens comes out, and each frame draws that picture with
  a round hole where the lens is. The app underneath shows through the hole, whatever it is: the tour on a fresh
  install, the model download screen, or the home screen.
- With "Remove animations" on it shows a still picture for half a second and is taken away. A tap skips it.

## Messages

Every short message ("Copied.", "Merged two people." with Undo) goes through `AppToast` in `lib/core/widgets/app_toast.dart`,
so they all look the same. It sits above the floating bar on the home screen and near the bottom of the screen
anywhere else, above the keyboard when it is up. A message with a button shows the time left as a line that shrinks.
A new message replaces the one on screen. Write them as a short sentence that ends with a full stop. The video viewer
has its own message card, because it shows face pictures.

## Logs

```bash
adb logcat -s FaceScanner FaceTuner   # face scan timing and tuning
adb logcat -s LostFoundBench          # performance logs for indexing, faces and search
```

The performance logs are always on. Every log line goes to Android's log and also to the app's own log file,
two files of up to 512 KB in `files/logs/` (`AppLog` in `core/log/`), because some phones do not let an app read
its log back. The Dart side's printed messages and uncaught errors are added to it, and so is an uncaught crash.
Settings > About > Note from the developer shows the newest 4000 lines (with a Copy button) and attaches them to a
problem report, which opens the person's own email app. The copies of the files of a report are made in
`cache/report/` and deleted when the person is back from the mail app, and when the app next starts.

## The search model files

- `export_clip/export_mobileclip.py` makes the two ONNX files from Apple's 2024 MobileCLIP
  checkpoint (`--variant s0|s1|s2`, default `s0`): image tower in fp32, text tower in int8.
- `export_clip/verify_mobileclip.py` compares them with Apple's PyTorch model on the tour's sample
  photos, and checks the app's tokenizer against open_clip's.
- `export_clip/MOBILECLIP_SOURCE.md` records where the weights came from (address, date, size,
  hashes) and what was measured. The 2024 licence texts are in `export_clip/licenses/`.
- The files are hosted in the `models-v1` GitHub release. The app checks their SHA-256 hashes
  after downloading (`features/model_download/`). Steps and checksums: [model_host/README.md](../model_host/README.md).

## Face models

The face detector (`det_2.5g.onnx`) and recognition model (`w600k_mbf.onnx`) are bundled in
`android/app/src/main/assets/`. Each model is described by a spec (input size, normalisation,
channel order), so either can be swapped without code changes; see [Architecture](architecture.md#faces).
