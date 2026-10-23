# model_host/

Holds the model files (the two MobileCLIP-S0 files and the face recognition
model) and the steps for publishing them. Everything here except this file is
gitignored: the model files themselves are never committed.

All builds, debug and release, download the search model from the `models-v1`
GitHub Release.

## Publishing for real

1. Open the existing GitHub Release `models-v1` and add these as assets (the app downloads the first two on
   first launch; the third is Apple's notice, which has to stay with the weights):
   - `mobileclip_s0_vision.onnx`
   - `mobileclip_s0_text.onnx`
   - `APPLE_MOBILECLIP_WEIGHTS_LICENSE_2024.txt`
   Nothing else is hosted: the face models are bundled in the app. `upload_to_release/` in this folder holds
   them, with `SHA256SUMS.txt` and `RELEASE_NOTES.md`, the new text of the release description.
2. `MODEL_BASE_URL` in `defaultConfig` (`android/app/build.gradle.kts`) points at that tag, for every build
   type - update it if you use a different tag name. Add the files **before** a build goes to anyone: until
   then it has nothing to download.
3. Leave the old assets (`clip_vision.onnx`, `clip_text.onnx`, ...) in the release: versions of the app from before
   the MobileCLIP switch download their CLIP files from it. The `mobileclip_s2_*` files that were briefly there
   (an fp16 image model that gave NaN on a phone) can be deleted: no build downloads them any more.
4. If the model files change, update the checksums/sizes in
   `RemoteModel.kt` (`android/app/src/main/kotlin/dev/raseel/lostandfound/embedder/models/`)
   to match, or every download will fail verification. They are made by `export_clip/export_mobileclip.py`
   (what they come from, and under what licence: `export_clip/MOBILECLIP_SOURCE.md`).

`clip_vision.onnx`, `clip_text.onnx` and the `*_ts.pt` files in this folder are the old CLIP ViT-B/32 files
(`models-v1`), kept only for comparing with the new ones; the app no longer downloads them and they can be deleted.

Current checksums:

```
mobileclip_s0_vision.onnx   sha256:2404c7f922d3d64552eb9643ff5c6325dab0d3c8b0ab8b51531fc68bf62fdbdf  (45575684 bytes)
mobileclip_s0_text.onnx     sha256:6412755124a4125282cc4fc7b22ea9bdd4671ff07ca59494b1e7545b003327bd  (58652554 bytes)
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
