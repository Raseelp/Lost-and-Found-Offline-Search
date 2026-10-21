# Lost & Found: Offline Search

Find your photos and videos by describing them, and browse them by who is in
them — all on your phone, with no account and no cloud.

On-device semantic search for your photos and videos. Describe what you're
looking for — "a dog on a beach", "the whiteboard from that meeting" — and
it finds it, no matter what the file is named. It also recognises the people
in your photos and groups them, so you can browse and search by who is in a
picture.

Everything runs locally. Your media is never uploaded anywhere; the search
index and the face recognition are built and used entirely on your phone.

## How it works

### Search

- Point it at a folder or your whole phone. It walks through your photos
  and videos and generates a CLIP embedding for each one (and for a handful
  of sampled frames per video), stored in a local index.
- Type a description, or hand it a reference photo, and it ranks your
  library by similarity.
- Indexing is the slow part and only has to happen once per file — after
  that, search is instant.
- Save searches as **Collections** and open them later (see below).

### Collections

A collection is a saved search with a name of your own ("dog" saved as
"Mittu"). Only the definition is stored: its photos and videos are looked up
again from the index each time, so what a new scan finds shows up by itself.
Items found by the latest scan carry a **New** tag and come first, in
collections and on people's pages. Long-press a collection to edit, hide or
export it; **Select** on the Collections tab picks several at once.

### Export as zip

Put collections and people in a zip to keep, send, or move to another phone.
Your photos and videos are only read, never changed or removed.

- **Where from.** **Select collections** on the Collections tab (the bar at the
  bottom then offers *Export as zip*), **Select people** on the People tab (the
  bar offers *Photos together* and *Export as zip*), a collection's or person's
  menu, or the *Export* button round a person's photo.
- **What goes in.** Pick any number of collections and people (there is a
  search box and *Select all*). Each becomes a folder in the zip with an
  `Images` and a `Videos` folder inside. A photo in two chosen albums is stored
  in both. Files are not compressed (photos and videos already are), keep their
  names, and carry the date they were taken (else last changed).
- **Settings.** A name (one album: its name; several: "Lost & Found export" and
  the date), where to save (**Downloads › Lost & Found**, or any folder you
  pick; before Android 10 a folder has to be picked), and a `list.json` with each
  file's name, date and size (no original paths; on by default).
- **Splitting.** From about 100 MB up, the zip can be cut into independent
  parts (4 GB, 2 GB, 1 GB, 512 MB, or a size you choose). Each part is a
  complete zip that opens on its own, and no file is ever cut across two of
  them. A part expected to pass about 3 GB (or 60,000 files) uses the 64-bit zip format; smaller ones are plain zips every tool reads.
- **Making it.** It runs as background work with a notification, so it carries
  on if you leave the app. Cancelling, or a failure, deletes everything made so
  far.

### People (face recognition)

A background scan finds and recognises the faces in your photos and groups
them into people. It runs along with indexing (every so many photos the app
finds their faces before it carries on), or from **Update people** on the People
tab; it never starts by itself. It can be paused and resumed, and people appear
as they are found.

- **Detect → align → recognise → group.** A small detector (SCRFD) finds
  faces, each is straightened, and a small recognition model (MobileFaceNet,
  `w600k_mbf`, ~13 MB) turns it into a 512-number fingerprint. Faces are grouped by comparing
  fingerprints. Blurry, tiny or turned-away faces never start a person; they
  can only join one that already exists.
- **Faces tab.** A grid of the people found, most photographed first. Open a
  person to see all their photos; rename them; hide people you don't want
  listed.
- **Timeline.** *Timeline* on the People tab shows each person as a strip of
  months, darker where there are more photos of them, on one shared axis of
  years, like the timeline of a video editor: drag to move through the years,
  pinch (or use *All / 5 years / 1 year / 3 months*) to zoom, and drag the
  overview at the top to jump. A line in the middle is the playhead: whoever
  has photos in the month under it lights up and the rest dim. The date of each photo
  is the gallery's taken date, else the picture's own (EXIF), else a date in
  its file name, else when the file was changed. Dates that cannot be right
  (before 1990, in the future, a camera's reset clock) are ignored, and photos
  without a date are counted per person. Above the strips a row of photos follows
  the playhead (the best few photos of each month, in date order, the one at the
  playhead large): winding through a busy month steps through its photos, and an
  empty month holds the row still. The face of each person who has photos in the
  month under the playhead turns into their own photo of that month. When the
  years come to rest on a month the preview grows and that month opens out into
  its photos in a collage, folding back into one photo when you move again; the
  row of photos can be dragged too. Tapping a photo in the opened-out month opens a
  screen with all of that month's photos and videos, day by day (the tapped one is
  ringed). The preview is the top of the list: scrolling the list slims it step by
  step (and it stays slim while you are down the list), scrolling back up grows
  it step by step, and it opens out again once the list is back at the top - or as
  soon as you slide a line or the row of photos, wherever the list is. Moving the
  strips also slims it while the years move. Good moments
  (the first photo together with the person they are photographed with most, a
  return after a year or more away, a look back at a run that has gone quiet, the
  whole gang in one photo, a reunion of people coming back together after a long gap,
  a year's new faces) are kept in one place: the sparkle button at the top opens
  *Your story*, a timeline of them year by year, each with the faces and one warm
  line; tap one to take the timeline to that month. By default only your inner
  circle (the named people photographed the most, about eight) get moments; a switch
  lets everyone have them. Moments about people being together (the first photo together, the whole gang, a
  reunion) only count clear faces, or ones you confirmed, in photos - never a blurry
  face that was matched to someone loosely, and never a video, where people may
  appear at different times. The photos that are moments say so wherever they show up:
  a small cream bookmark with a sparkle hanging from the top edge of their tile in
  search, collections, a person's photos and a month's photos, and a film-style
  caption over the photo or video when it is opened (the faces, the date in small
  capitals, the moment in italics, on a shade that fades in from the edge). Everything
  is worked out on the phone.
- **On this day.** A card on the Library tab shows today's date in the years before: how many
  photos and videos there are from it, a little stack of the best, and - when two named people
  first appeared in a photo together on this date - how many years of them it is. It opens a
  screen with a section for each year (the photos that stand for it, and *See all* for the whole
  day). With nothing on the date itself it shows the week round it. Every indexed photo and video
  counts, not only those with people; only dates that can be believed are used (the gallery's taken
  date, the picture's own, a date in its name - never when a file was copied), and screenshots are
  left out. It is kept cheap on a big library: the dates are kept in a small catalog that follows the
  search index by reading only what was added since last time (never the embeddings), looked up a
  slice at a time in the background, and each past year is found with one range lookup on the date
  index.
- **Daily memory.** *Settings > Memories* turns on two notifications a day, at fixed times - early
  morning (6:30), the first thing to see, and evening (7:30) - each only when there is something good.
  The morning looks back (on this day, anniversaries, a few days of a trip, across the years); the
  evening is about people (then and now, together since, a milestone, a lovely picture). Each comes
  with its own look: a small rounded picture and heading when folded, and a full-width picture when
  opened - the photos fill the card (rounded corners, no frames, no empty space) with small pills for
  what the words do not say. *Then and now* is a split: the two photos with a slanted white seam, the
  year on each and the time between on the seam; *together since* is a big photo of the two with the
  first photo of the two tucked into the corner; a few days of a trip, or the same date across the
  years, are a strip of full-height photos each with its day or year; everything else is one photo
  edge to edge with its date. Text colours follow light and dark mode. A locked screen shows only
  the words.
  The kinds take turns: the one that has gone longest without goes next, never one that already went
  out today or yesterday while another is there, the same person is not the subject again for 45 days,
  and a photo is not shown again for 120 days. The kinds:
  - *the anniversary of two named people's first photo together*, *a person's first day in your
    photos* and *a person reaching 50, 100, 250, 500, 1000... photos*;
  - *Then and now*: one person's start next to their latest; *Then and now, together*: two people;
  - *Together since*: the years two people have been in photos together;
  - *On this day* (worded differently from day to day, and for a crowd or a big day), *this date in
    three or more years*, and *this week* when the date itself has nothing;
  - *A few days to remember*: three or more busy days in a row round this date in a past year;
  - *Remember this one?*: a lovely picture of someone, picked by the day.
  A quiet slot sends nothing, and one held up for hours (the phone was off) is skipped. *Send one now*
  tries a different kind each time without using up a slot. Tapping one opens the person's page, or
  that day. All of it is worked out on the phone.
- **Then and now.** On a person's page, their start next to their latest: one comparison with a
  divider to drag between the two, and under it up to three small photos at each end to choose from
  (tap one and it takes that end's place in the comparison). The photos come from *about* the start and
  *about* now - the best of the first couple of months and of the latest couple, widening (2, 4, 8, 12,
  18, 24 months) only until there are three different photos at each end - never simply the very first
  and very last. Each end mixes kinds (on their own, with one other person, in a small group), the best
  first, and each photo says who is in it ("On their own", "With Dev"); which are shown first changes
  from day to day. It needs clear faces in photos with a believable date, at least four of them, over at
  least six months (a lone photo with a wrong date never counts as the first or last time).
- **Names always match the picture.** A person is only said to be in a photo (in a notification, a
  moment, "together since", "on their own") when their face is confirmed, or is clear and big enough
  to be more than someone in the background (at least 4% of the photo across). A notification names
  only the people in the photo it shows, never everyone from that day. The morning and evening
  notifications each keep their own place in the shade.
- **Fixing mistakes.** *Review faces* takes out a face that isn't them.
  *Same person as someone else* merges two groups, and the app suggests likely
  merges (with a certainty level). Merges can be undone (**Undo a merge**), and
  **Split into two people** separates a person who was two people mixed up.
  Your edits stick: they are remembered for photos scanned later, and pairs you
  said are different are never suggested again.
- **Find photos by people.** Pick one or more people (*Select people* on the
  Faces tab, or long-press a person) and see the photos with them — with
  anyone, on their own, any of them, plus others, or only that group. From the
  results you can add or remove people.
- **Teaser on Search.** When the search box is idle, the people found so far
  sit beside your collections.
- **Videos too.** After the photos, the scan goes through your videos: it looks at
  frames spread through each one (fast / balanced / thorough in the face options),
  links a face across neighbouring frames into one track and recognises only the best
  one or two faces of each track, so a clip costs a handful of recognitions, not
  hundreds. Faces in video must be clearer than in photos (motion blur), a small
  picture of each kept face is saved, and a video counts as one item however many frames
  someone is in. People's pages and *Select people* mix photos and videos; a video opens
  at the moment the person shows up. In the video viewer, the people found are a row of
  faces above the playback bar: tap one to jump to where they appear (and see those
  moments on the bar), tap again for their next appearance. It can be switched off in the
  face options.
- **Tap a face in a photo.** In the full-screen viewer, recognised faces can be
  tapped: a morphing, glowing outline draws itself round the head and a small
  card shows who it is — tap it to open that person. A photo the background
  scan hasn't reached yet (or has only partly recognised) is scanned the moment
  you open it, with a quiet glow and live progress ("Found 12 faces ·
  identifying"), and is then marked complete so it isn't looked at again.
- **Scan a video from its viewer.** A video the background scan hasn't reached has a
  "find people" button in the top bar. Tapping it scans that video while it plays and
  everything else keeps working: the same quiet glow, with live progress ("Scanning frame 7
  of 20 · 5 faces"), and the people found appear as a row above the playback bar. Tapping the
  button again scans again and replaces the first result.
- **Tap a face in a paused video.** Pause a video (or scrub and let go): after a moment
  the frame on screen is looked at and every face that matches someone you know gets the
  same tappable outline as in a photo. This is looked up on the spot and stores nothing,
  so it works even before the background scan has reached the video.

The recognition pipeline is model-independent: the detector and the recognition
model are described by their own specs, so either can be swapped without code
changes. A tuning step times the model on your phone (threads, batching,
hardware acceleration) and picks what is fastest.

The Flutter UI talks to a native Android layer that runs CLIP (vision +
text towers) and the face models both via ONNX Runtime, and stores
embeddings and faces in small on-device stores (a binary store for CLIP, SQLite
for faces).

## Privacy

Nothing leaves the phone. The only network use is the one-time download of the
search models (see below); your media, the index, the faces and the people are
never uploaded.

## Status

Android only, for now (minimum Android 7.0 / API 24).

## Project layout

- `lib/` — the Flutter app (`controllers/` with GetX, `view/`, `services/` for
  the channel to the native side, `db/`).
- `android/app/src/main/kotlin/dev/raseel/lostandfound/` — the native side:
  `embedder/` (CLIP, scanning, the stores), `embedder/faces/` (detection,
  recognition, grouping), `export/` (the zip writer and its background work).
- `export_clip/` — scripts that turn the CLIP models into ONNX.
- `model_host/` — a throwaway server for testing the model download.

## Building it yourself

One set of model weights is downloaded once on first launch — it is not
bundled in the app or the repo:

- **Search** — the CLIP weights (~575 MB).

The face models are part of the app (in `android/app/src/main/assets/`): the
face detector (SCRFD, ~3 MB) and the face recognition model (MobileFaceNet,
~13 MB).

The setup screen downloads the search models with one button, with speed, time
left and resume. They can be removed again from Settings, which returns you to
the setup screen. See [model_host/README.md](model_host/README.md) for testing
the download flow locally (including the checksums and how they are
published), or `android/app/build.gradle.kts` for where the release build
points to.

```bash
git clone https://github.com/Raseelp/Lost-and-Found-Offline-Search.git
cd Lost-and-Found-Offline-Search
flutter pub get
flutter run
```

The zip writer has a JVM unit test (it also checks that other zip tools can
read what it writes):

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

To watch the face scan's timing on a device:

```bash
adb logcat -s FaceScanner FaceTuner
```

The performance logs for indexing and face finding (on unless turned off in
Settings) use their own tag:

```bash
adb logcat -s LostFoundBench
```

## Credits

The first-run tour's sample photos and clips are CC0 or public domain, except the photo in the face demo
(`assets/tour/photos/supercup.jpg`, and the face crop `assets/tour/faces/suarez.jpg` made from it), which is by
Oleh Dubyna under CC BY-SA 3.0. Every source is listed in `assets/tour/photos/CREDITS.txt`,
`assets/tour/faces/CREDITS.txt` and `assets/tour/videos/CREDITS.txt`.

## License

MIT — see [LICENSE](LICENSE).
