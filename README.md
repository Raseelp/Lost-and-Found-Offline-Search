# Lost & Found: Offline Search

Find your photos and videos by describing them, and by who is in them. Everything runs on your
phone, with no account and no cloud.

<!-- Screenshots: replace each placeholder with a phone screenshot (about 1080 px wide). -->
<p align="center">
  <img src="docs/screenshots/search.png" alt="Search" width="19%">
  <img src="docs/screenshots/people.png" alt="People" width="19%">
  <img src="docs/screenshots/timeline.png" alt="People timeline" width="19%">
  <img src="docs/screenshots/on-this-day.png" alt="On this day" width="19%">
  <img src="docs/screenshots/memory.png" alt="Daily memory notification" width="19%">
</p>

Type "a birthday cake with candles" or "the whiteboard from that meeting" and Lost & Found finds it, whatever
the file is called. It recognises the people in your photos and videos, so you can also search
"Maya and Dev at the beach". The search index, the faces and the people are built and kept on
the phone. Nothing is uploaded.

## Features

### Search
- Find photos and videos by describing them in your own words.
- Find similar photos by searching with a photo.
- Search inside videos. A result opens at the matching moment.
- Combine people and words, like "@Maya at the beach".
- Search only photos, only videos, or both.
- Index your whole phone, or only the folders you choose.

### People
- Faces in your photos and videos are grouped into people automatically.
- Name people, or hide the ones you don't want to see.
- Fix mistakes: merge two people, split one into two, or remove a wrong face.
- Get merge suggestions, each with a certainty level.
- Tap a face in a photo or a paused video to see who it is.
- Find photos of a group: with anyone, on their own, or only that group.
- See everyone on one shared timeline, with moments like a first photo together or a reunion.
- Compare a person's early photos with their latest in Then and now.

### Collections and export
- Save a search as a collection. It updates itself as new photos are found.
- Start with 21 built-in collections.
- Export collections and people as zip files.
- Split large exports into smaller parts.

### Memories
- See today's date in past years with On this day.
- Get a photo memory each morning and evening (optional).
- Watch stories of your people and places on the Search tab. Each has a new one a day after you watch it.

### Viewer
- Share, save a copy, set as wallpaper, or copy to the clipboard.
- Watch silent video previews right in the grids.

Details: [People](docs/people.md) · [Export](docs/export.md) · [Memories](docs/memories.md) ·
[Changelog](CHANGELOG.md)

## How it works

Three on-device models do the work, all run with ONNX Runtime from native Kotlin code:

| Job | Model | Size | Where it comes from |
|---|---|---|---|
| Search (text and images) | Apple MobileCLIP-S0: image tower fp32, text tower int8 | 104 MB | Downloaded once on first launch |
| Face detection | SCRFD-2.5G (InsightFace) | 3 MB | Bundled in the app |
| Face recognition | MobileFaceNet `w600k_mbf`, 512-number fingerprints | 13 MB | Bundled in the app |

- Search: each photo (and 3 to 10 frames spread through each video, by length) is turned
  into a 512-number vector by the image model. A search phrase is turned into a vector by the text
  model, and results are the photos whose vectors are closest. Indexing is the slow part and
  happens once per file; searching is instant.
- People: faces are detected (a second pass over tiles finds small faces in big photos),
  straightened, and turned into fingerprints. A face joins the person whose faces it matches;
  each person keeps several "looks" (glasses, years apart) so they stay one person. Blurry,
  tiny or turned-away faces can join a person but never start one.
- Together: people narrow a search and the words rank what is left, so "Maya at the
  beach" combines face recognition with the search model. Face finding runs in step with
  indexing: every batch of photos indexed is scanned for faces, so people appear while the
  first scan is still running.

More: [Architecture](docs/architecture.md)

## Requirements

- Android 7.0 (API 24) or newer. Android only, for now.
- A one-time download of the search model (104 MB). After that, the app works offline.

There are no prebuilt releases yet; build it from source (below).

## Privacy

Nothing leaves the phone. The only network use is the one-time download of the search model.
Your photos, the index, the faces and the people are never uploaded.

## Building

```bash
git clone https://github.com/Raseelp/Lost-and-Found-Offline-Search.git
cd Lost-and-Found-Offline-Search
flutter pub get
flutter run
```

Tests, debug builds, performance logs and how the model files are made and hosted:
[Development](docs/development.md).

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright (C) 2026 Raseel. Lost & Found is free and open source software under the
[GNU Affero General Public License v3.0](LICENSE). Versions up to commit `4e88cab` were released
under the MIT License and stay under it.

- Commercial license: for use in a closed-source product, a separate commercial license is
  available from the author. Open an issue on GitHub to ask.
- Name and icon: not covered by the code license; see [TRADEMARKS.md](TRADEMARKS.md).
- Parts with their own licenses, not covered by the AGPL:
  - the search model, Apple's MobileCLIP-S0, under the license Apple published with the weights
    in 2024 (`export_clip/licenses/`; source record in `export_clip/MOBILECLIP_SOURCE.md`);
  - the tour's sample photos and clips, CC0 or public domain except one photo by Oleh Dubyna
    under CC BY-SA 3.0 (sources in `assets/tour/*/CREDITS.txt`);
  - the fonts in `assets/fonts/`, SIL Open Font License 1.1;
  - the Flutter and Android packages the app uses, each under its own license.
