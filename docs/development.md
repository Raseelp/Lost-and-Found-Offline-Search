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

Debug builds download the search model from a local server: run `model_host/serve.py` on your
computer and `adb reverse tcp:8000 tcp:8000` first. See [model_host/README.md](../model_host/README.md).

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
