# Changelog

Notable changes, newest first. There are no tagged releases yet, so changes are grouped by date.
Details of each feature are in [docs/](docs/); the full history is in `git log`.

## Unreleased

### Changed
- README shortened to one line per feature; feature details moved to `docs/` (architecture,
  people, memories, export, development).

## 2026-10-23

### Changed
- Search model switched to Apple MobileCLIP-S0: 104 MB download instead of 606 MB, about as fast,
  and more accurate. Image model fp32 on XNNPACK, text model int8.
- The search index records which model made it; an index from another model is rebuilt, and
  people and faces are kept.
- Photos are decoded in full colour for the search model.
- Search result pictures load three at a time.

### Fixed
- Search tokenizer now matches CLIP's own (spaces, numbers, ending on the end token).
- NaN vectors are never stored, so a broken model cannot make every search rank the same.

### Added
- Debug builds install as a separate app (`.debug`) with model and scan benchmark screens.

## 2026-10-22

### Changed
- License changed from MIT to AGPL-3.0, with a commercial license on request. Added
  `CONTRIBUTING.md` (contributor license agreement) and `TRADEMARKS.md`.

### Added
- Settings > About > License shows the copyright, license and package licenses.

## 2026-10-21

### Added
- First-run tour, replacing the model download screen on a fresh install; replay from
  Settings > About > Help.
- Pause and resume for the model download.
- Settings > About: build details (version, build, commit) and a link to the source code.
- Silent video previews in the grids (Settings > Videos).

### Changed
- On this day moved to the Collections tab; it can be exported as a zip or hidden.
- Sharper pictures in the timeline, month tiles and memory notifications.
- Colours moved into the theme.

### Removed
- The iOS, web, Windows, Linux and macOS folders: the app is Android only.

## 2026-10-15

### Added
- People timeline with moments and "Your story".
- On this day, Then and now, and two daily memory notifications.

## 2026-10-13

### Changed
- Library, People, Collections and Search screens redone; 21 built-in collections.

## 2026-10-12

### Changed
- App renamed to Lost & Found.

## 2026-10-11

### Added
- Zip export of collections and people, with optional parts and a file list.
- A "New" tag for items found by the latest scan.

### Changed
- Stricter "Same person?" suggestions.

## 2026-10-02 to 2026-10-06

### Changed
- Search model moved from PyTorch Mobile to ONNX Runtime (release APK 398 MB to 131 MB).
- Faces are found in step with indexing; only the small MobileFaceNet face model ships, bundled.
- The Library shows the scan with the face scan following indexing.

### Added
- Search by people with "@" mentions, and person-filtered collections.

## 2026-09-25 to 2026-09-28

### Added
- People: face recognition, grouping, find by people, tappable faces in the viewer.
- Face recognition in videos.
- Collections, a "Similar to this" strip in the viewer, and a redesigned viewer.

## 2026-09-06 to 2026-09-10

### Added
- Background scanning with a foreground service, live speed and ETA, and a recently indexed strip.
- Search while a scan is running.

### Changed
- New design system; Home split into Search and Library tabs.

## 2026-08-15

- First version: on-device photo and video search with CLIP.
