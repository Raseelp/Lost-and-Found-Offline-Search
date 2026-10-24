# Architecture

How search and face recognition work, how they fit together, and where the data lives.

## Overview

```
Flutter UI (lib/)  ── method channel ──>  Native Android layer (Kotlin, embedder/)
                                           │
              ┌────────────────────────────┼─────────────────────────────┐
              │                            │                             │
     Search (MobileCLIP-S0)       Faces (SCRFD + MobileFaceNet)    Memories and dates
     ONNX Runtime, XNNPACK         ONNX Runtime, tuned per phone   (LibraryDates, workers)
              │                            │                             │
     EmbeddingStore (binary file)   FaceStore (SQLite)             library_dates.db (SQLite)
```

The Flutter app (`lib/`) holds the screens and state (GetX controllers). Everything heavy runs in
native Kotlin (`android/app/src/main/kotlin/dev/raseel/lostandfound/`): model inference, scanning,
storage, notifications and the zip writer. The two talk over a Flutter method channel
(`lib/services/native_services.dart` and `MainActivity.kt`).

## Models

| Model | File(s) | Format | Input | Output | Shipped |
|---|---|---|---|---|---|
| Apple MobileCLIP-S0, image tower | 45.6 MB | fp32 ONNX | 256 x 256 RGB, 0..1 | 512 numbers | Downloaded |
| Apple MobileCLIP-S0, text tower | 58.7 MB | int8 ONNX (one layer fp32) | 77 CLIP BPE tokens | 512 numbers | Downloaded |
| SCRFD-2.5G face detector | `det_2.5g.onnx`, 3.3 MB | ONNX | 640 x 640 letterboxed | boxes, 5 landmarks, score | Bundled |
| MobileFaceNet `w600k_mbf` | `w600k_mbf.onnx`, 13.6 MB | ONNX | 112 x 112 aligned face | 512 numbers | Bundled |

The search model was exported from Apple's 2024 checkpoint with `export_clip/export_mobileclip.py`
and checked against Apple's PyTorch model with `verify_mobileclip.py` (see
`export_clip/MOBILECLIP_SOURCE.md` for the source, hashes and measurements). The image tower stays
in fp32 because an fp16 build returned NaN on a real phone.

## Search

1. **Preparing a photo** (`ImagePreprocessor.kt`). Decoded in full colour (ARGB_8888), the shorter
   side scaled to 256, the centre 256 x 256 cut out, each pixel scaled to 0..1. No mean/std
   normalisation: MobileCLIP was trained without it.
2. **Videos** (`VideoFrameExtractor.kt`). Frames evenly spread through each video are prepared the
   same way: 3 for clips under 10 s, 5 under 30 s, 8 under 2 minutes, 10 for longer videos. Each frame gets its own vector, so a search can land on the right moment.
3. **The image model** (`EmbeddingEngine.kt`). Runs on XNNPACK with up to 6 threads, in batches of 4,
   with 2 threads preparing the next photos. If XNNPACK fails on a phone, it falls back to the
   plain CPU path and remembers not to try again.
4. **Storing** (`storage/EmbeddingStore.kt`). Vectors go into one binary file. Its header records
   the file format and which model made the vectors (model id 3 = MobileCLIP-S0). An index from
   another model is dropped when the app starts, and the Library tab offers to scan again; faces
   and people are kept. NaN or infinite vectors are never stored.
5. **Searching.** The text is tokenised in Dart (`lib/tokanizer/`, CLIP's own word pattern, 77
   tokens), turned into a vector by the text model, and compared with every stored vector (dot
   product of length-1 vectors = cosine similarity). Frames of the same video collapse into the
   best one. Search by photo runs the image model on the chosen photo and uses that vector
   instead of the text's.
6. **Collections** store only their definition (words, people, or a seed photo). Their results
   are looked up again from the index each time, so new photos show up by themselves. Saved
   vectors record which model made them and are redone when the model changes. A collection's
   words can have other phrasings; their vectors are averaged. While a new collection is being
   made, its sheet runs the same lookup for a preview (the count and the best few), and
   `FaceStore.peopleIn` names the people in those matches.

## Faces

1. **Detect** (`faces/FaceDetector.kt`). SCRFD runs on the whole photo letterboxed into 640 x 640.
   Photos larger than 1000 px get a second pass over overlapping tiles, so small faces in group
   photos are found too. Score threshold 0.5, overlap removal at IoU 0.4.
2. **Quality** (`faces/FaceQuality.kt`). Each face is rated on size (under 44 px is dropped, under
   48 px counts as weak), detector score, how far the head is turned (yaw from the landmarks) and
   sharpness. Weak faces are kept and shown, but they can only join a person, never start or
   reshape one. Video faces are held to a stricter standard (motion blur).
3. **Align** (`faces/FaceAligner.kt`). The 5 landmarks are mapped onto the standard 112 x 112
   face layout with a similarity transform.
4. **Recognise** (`faces/FaceEmbedder.kt`). MobileFaceNet turns the aligned face into a 512-number
   fingerprint, scaled to length 1. The model is described by a spec (input size, normalisation,
   channel order), so either face model can be swapped without code changes.
5. **Group** (`faces/FaceClusterer.kt`).
   - A person is one or more "looks" (up to 6): groups of their faces that resemble each other,
     for example with and without glasses, or years apart. A new face joins the person with the
     closest look if it is similar enough; otherwise it starts a new person.
   - Each person also keeps their 10 best faces, used to compare people face to face.
   - Two faces in the same photo are never the same person. A face the user removed from someone
     never goes back to them.
   - Merging: two people are merged when their looks are close, or when several of their best
     faces match. Close pairs that fall just short are offered as suggestions with a certainty.
   - Strictness (similarity needed): balanced join 0.365 / merge 0.45; strict 0.445 / 0.53;
     loose 0.305 / 0.39. Tuned for this model on about 4,400 faces (LFW).
   - Anything the user named, merged or moved is pinned: automatic regrouping leaves it alone.
6. **Tuning** (`faces/FaceTuner.kt`). On first use the face models are timed on the phone
   (threads, batching, backend) and the fastest setup is remembered.
7. **Model changes.** The face store records which face models made its fingerprints. A different
   model means regrouping from scratch (`FaceScanner.kt`, `adoptModels`).

### Faces in videos

`faces/VideoFaceScanner.kt` treats a video as a set of sampled frames. Every frame is searched for
faces (cheap); faces in neighbouring frames are linked into tracks (one person moving through the
clip); only the best one or two faces of each track are recognised (expensive), and the rest of the
track gets the same person. A short clip costs a handful of recognitions, not hundreds. A video
counts as one item however many frames someone is in, and opens at the moment they appear.

## How search and faces work together

- **One scan, two passes in step** (`ScanWorker.kt`, `faces/FaceFollower.kt`). Indexing runs for
  60 photos or 30 seconds, then waits while those photos' faces are found at full speed, then
  carries on. The two never compete for the processor, and people appear long before a big scan
  ends. Videos and a refining pass of the faces run after indexing.
- **Searching with people.** Names typed in the search box (or picked with "@") are recognised and
  removed from the text. The people narrow the results to photos and videos with all of them in
  it; the remaining words are ranked by the search model. "Maya and Dev at the beach" = photos with
  both, ranked by "at the beach".
- **Names always match the picture.** Memories, moments and notifications only say someone is in a
  photo when their face is confirmed, or clear and at least 4% of the photo across.

## Storage

| Data | Where | Format |
|---|---|---|
| Search vectors | `EmbeddingStore` | Binary file with a header (format version, model id, vector size 512) |
| Faces, people, merges, rejections | `FaceStore` | SQLite |
| Photo dates for memories | `LibraryDates` (`library_dates.db`) | SQLite, follows the search index |
| Collections and indexed folders | Flutter side (`lib/db/`) | SQLite; collection search vectors cached in shared preferences |

Everything stays in the app's private storage. Clearing the search index, the face data or the
search model is in Settings > Danger zone.

## Background work

- **Scans** run as WorkManager work with a foreground notification (`ScanWorker`,
  `ScanForegroundService`), and can be paused and resumed.
- **Face scans** after indexing: `FaceScanWorker`.
- **Daily memories**: `memories/DailyMemoryWorker`, two slots a day.
- **Zip export**: `export/ZipExportWorker`.

## Project layout

- `lib/`: the Flutter app (`controllers/` with GetX, `view/`, `services/` for the channel to the
  native side, `models/`, `tokanizer/`, `db/`).
- `android/app/src/main/kotlin/dev/raseel/lostandfound/`: the native side. `embedder/` (search model,
  scanning, the stores), `embedder/faces/` (detection, recognition, grouping, video faces),
  `embedder/memories/` (dates, notifications), `export/` (the zip writer).
- `export_clip/`: scripts that make and check the search model files, and the model's licence texts.
- `model_host/`: how the search model files are published, with their checksums.
