# Changelog

Notable changes, newest first. There are no tagged releases yet, so changes are grouped by date.
Details of each feature are in [docs/](docs/); the full history is in `git log`.

## Unreleased

### Added
- Stories on the Search tab. There is a ring for each person and for the built-in collections that are
  nice to look at (beach, flowers, mountains and so on). Tap a ring to watch a short story of its photos
  and videos. A ring turns grey for a day after you open it, then has a new story with pictures it has
  not shown before. Once you have seen them all a Refresh button asks for new ones, and a long press on
  a ring leaves it out for a while. A note tells you when your stories have refreshed, with a row of the
  rings that are ready (it can be turned off in Settings). It names the people first and the collections
  after, in a sentence of their own. It comes a day after you last used the app,
  even if you have never opened a ring. If it goes unanswered the next one waits 2, then 4, then 7 days,
  and after four there are no more until you open the app. At most one a day, never on a day a daily
  memory went out (two days running at most), and a tap opens the Search tab.
- A new "New collection" sheet. It previews what the words find (how many, the best few photos
  and who is in them) as you type, takes other ways of saying it, can include photos, videos or
  both, and names the collection from the words. Before anything is typed it offers a few ideas,
  and a collection can start from a photo instead of words.

- A preview build (`.preview`): runs at release speed but installs next to the app in use, with its
  own data. See `docs/development.md`.

### Changed
- With nothing indexed yet, Search, Collections, Faces and the zip export each show a small moving
  picture of what they will hold, made of the tour's sample photos: example searches putting the best
  photos first (as in the tour), collection tiles getting covers, people as stacks of faces with some
  still to be named, and zip rows being chosen. Their Start indexing button starts the scan, as the
  Library's chip does, and shows it in the Library.
- The row of collections and the row of people on the Search tab are replaced by the story rings.
  After a search the rings shrink into a strip above the results, and "Stories" in the strip goes back.
- The scan notification is shorter and clearer. Indexing shows one bar in two parts, photos then
  videos, each as long as its share, and names the part it is on ("Indexing photos · 7%").
  Faces show only while they are being found, in the scan chip's violet, with a line saying what
  they are found in. Both show how fast they go ("6.2 photos a second"). The time left is written
  out ("about 1 h 20 min left"). On Android 16 it is a live update with the percentage in a chip
  in the status bar. Tapping it opens the Library tab, where the scan is, instead of Search.
- On the People tab, tapping "Add name" under someone without a name asks for their name. Before,
  that took a long press or opening the person.
- Search shows 20 results by default, up from 10. A number you have picked stays as it is.
- The search button no longer opens the keyboard. It comes up when you tap the search box.
- Collections you made that have something in them now come first on the Collections tab,
  before the built-in ones.
- Collections tab: each collection is one cover photo filling a rounded tile, with its name, item
  count and a "New" tag. Covers load as tiles come on screen, at the size each tile needs.
- The actions at the top of the Collections and People tabs (New collection, Select collections,
  Timeline, Select people, Update people) moved to a round bolt button above the search button.
  On a tab without actions, or while scrolling down, it merges into the search button.
- README shortened to one line per feature; feature details moved to `docs/` (architecture,
  people, memories, export, development).
- Videos look different from photos in the scan chip. The video rolls in as a strip of film, its
  timeline ticks once for each frame taken, the frames fan out and are read together, and the
  video drops into the strip as one tile with a play mark and its number of frames.
- The scan chip loads small thumbnails (400 pixels instead of 1600), so it does less work while
  a scan runs.

### Removed
- The Skip button on the first-run tour. The tour replayed from Help can still be closed.
- The local model server for debug builds (`model_host/serve.py`). Debug builds now download the
  search model from the GitHub release, like release builds.

### Fixed
- Stop indexing now shows "Stopping…" with a spinner right away, and ignores further taps while
  the scan finishes the photos in progress. Before, nothing changed for a few seconds, so it
  looked like the tap had not worked.

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
