# model_host/

Holds the model files (the two MobileCLIP-S2 files and the face recognition
model) and a throwaway local server for testing the
in-app download flow. Everything here is gitignored — nothing in this
directory should ever be committed.

## Testing locally

```bash
python model_host/serve.py
adb reverse tcp:8000 tcp:8000
```

`serve.py` serves the files with Range support (Python's stock
`http.server` doesn't have it, and the app's resume logic needs it).
`adb reverse` maps the device/emulator's `localhost:8000` to this machine's
`serve.py`, matching the debug `MODEL_BASE_URL` in `android/app/build.gradle.kts`.
Works the same for a physical device over USB or an emulator.

Worth checking before trusting the flow:
- Fresh download completes, progress tracks correctly.
- Kill the app mid-download, relaunch — resumes instead of restarting.
- Stop `serve.py` mid-download — fails with a clear error, doesn't hang.
- Delete models from Settings — app drops back to the download screen.
- Low storage — `ModelManager.hasEnoughFreeSpace()` refuses to start.

## Publishing for real

1. Open the existing GitHub Release `models-v1` and add these as assets (the app downloads the first two on
   first launch; the third is Apple's notice, which has to stay with the weights):
   - `mobileclip_s2_vision.onnx`
   - `mobileclip_s2_text.onnx`
   - `APPLE_MOBILECLIP_WEIGHTS_LICENSE_2024.txt`
   Nothing else is hosted: the face models are bundled in the app. `upload_to_release/` in this folder holds
   them, with `SHA256SUMS.txt` and `RELEASE_NOTES.md`, the new text of the release description.
2. `MODEL_BASE_URL` in the `release` build type (`android/app/build.gradle.kts`) points at that tag - update it if
   you use a different tag name. Add the files **before** a release build goes to anyone: until then it has
   nothing to download.
3. Leave the old assets (`clip_vision.onnx`, `clip_text.onnx`, ...) in the release: versions of the app from before
   the MobileCLIP-S2 switch download their CLIP files from it.
4. If the model files change, update the checksums/sizes in
   `RemoteModel.kt` (`android/app/src/main/kotlin/dev/raseel/lostandfound/embedder/models/`)
   to match, or every download will fail verification. They are made by `export_clip/export_mobileclip_s2.py`
   (what they come from, and under what licence: `export_clip/MOBILECLIP_S2_SOURCE.md`).

`clip_vision.onnx`, `clip_text.onnx` and the `*_ts.pt` files in this folder are the old CLIP ViT-B/32 files
(`models-v1`), kept only for comparing with the new ones; the app no longer downloads them and they can be deleted.

Current checksums:

```
mobileclip_s2_vision.onnx   sha256:faa31ef2a619b049bbd87a3c6a4e8d94894ed2a6fa93b7d18beb1ddcbb8c5d7b  (71792146 bytes)
mobileclip_s2_text.onnx     sha256:bfc216d9913df1c19b4b8929b2eeabf3b4475967b287e121074757a672039919  (67475592 bytes)
```

The face recognition model is InsightFace's MobileFaceNet (`w600k_mbf`, WebFace600K) from
the `buffalo_s` pack, with the output's batch size declared as flexible (the original file
says 1, which makes ONNX Runtime warn on every batched run; the weights and results are
identical). It is **not hosted**: it ships inside the app, in
`android/app/src/main/assets/w600k_mbf.onnx` next to the face detector
(sha256 `81ffd4b788d5c2cb5d9bf25056b7e793bf64322d7796eceff9db6c0272a0e998`, 13613018 bytes),
and `FaceModelStore` finds it there. The grouping thresholds in `FaceClusterConfig` were
set for this model (see the comment there). Earlier versions downloaded the larger
`w600k_r50` model; the app deletes that file when it finds it.
