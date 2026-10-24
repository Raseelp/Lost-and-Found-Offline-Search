# People

How faces become people, what you can do with them, and how the timeline, moments and
"Then and now" work. For the models and grouping internals, see [Architecture](architecture.md#faces).

## Finding people

A background scan finds and recognises the faces in your photos and groups them into people. It
runs along with indexing (every batch of photos indexed is scanned for faces before indexing
carries on), or from **Update people** in the bolt button on the People tab. It never starts by itself, can be paused
and resumed, and people appear as they are found.

Each face goes through four steps: detect (SCRFD), straighten (5 landmarks), recognise
(MobileFaceNet, a 512-number fingerprint) and group (compare fingerprints with each person's
"looks"). Blurry, tiny or turned-away faces never start a person; they can only join one that
already exists.

## The People tab

- A grid of the people found, most photographed first. Open a person to see all their photos and
  videos; rename them (for someone without a name, tap **Add name** under their faces); hide people you don't want listed (Settings > People > Hidden people).
- **Select people** in the bolt button (or long-press a person) to see photos of a group: with anyone, on their own,
  any of them, plus others, or only that group. People can be added or removed from the results.
- Names work in search too: "Maya and Dev at the beach" finds photos with both, ranked by "at the
  beach". Type "@" to pick a person from a list.

## Fixing mistakes

- **Review faces** takes out a face that isn't that person.
- **Same person as someone else** merges two people. The app also suggests likely merges, each
  with a certainty level.
- **Undo a merge** (Settings > People) restores the two people.
- **Split into two people** separates a person who was two people mixed up, with a preview of
  both groups.
- Your edits stick: they are remembered for photos scanned later, and pairs you said are
  different are never suggested again.

## In the viewer

- **Tap a face in a photo.** Recognised faces can be tapped: an outline draws round the head and a
  small card shows who it is; tap it to open that person. A photo the background scan hasn't
  reached yet is scanned when you open it, with live progress ("Found 12 faces · identifying"),
  and is then marked done.
- **Videos.** The people found in a video are a row of faces above the playback bar. Tap one to
  jump to where they appear (their moments show on the bar); tap again for the next appearance.
- **Scan a video from its viewer.** A video the background scan hasn't reached has a "find
  people" button. It scans the video while it plays, with live progress ("Scanning frame 7 of 20 ·
  5 faces").
- **Tap a face in a paused video.** Pause (or scrub and let go) and the frame on screen is checked:
  every face that matches someone you know gets the same tappable outline. Nothing is stored, so
  it works before the background scan reaches the video.

## Faces in videos

After the photos, the scan goes through your videos. It samples frames through each video, links
a face across neighbouring frames into a track, and recognises only the best one or two faces of
each track, so a clip costs a handful of recognitions. Faces in video must be clearer than in
photos (motion blur). A small picture of each kept face is saved, and a video counts as one item
however many frames someone is in. It can be switched off in Settings > People > Find people in
videos.

## People timeline

**Timeline**, in the bolt button on the People tab, shows each person as a strip of months, darker where there are
more photos of them, on one shared axis of years, like a video editor's timeline.

- Drag to move through the years; pinch, or use All / 5 years / 1 year / 3 months, to zoom; drag
  the overview at the top to jump.
- A line in the middle is the playhead. Whoever has photos in the month under it lights up, and
  their face turns into their own photo of that month.
- Above the strips, a row of photos follows the playhead: the best few photos of each month, in
  date order. When the timeline comes to rest on a month, that month opens out into a collage;
  tapping a photo opens all of that month's photos and videos, day by day.

**Dates.** A photo's date is the gallery's taken date, else the photo's own (EXIF), else a date in
its file name, else when the file was changed. Dates that cannot be right (before 1990, in the
future, a camera's reset clock) are ignored, and photos without a date are counted per person.

## Moments and "Your story"

The timeline marks good moments: the first photo together with the person someone is photographed
with most, a return after a year or more away, a look back at a run that has gone quiet, the whole
gang in one photo, a reunion after a long gap, and a year's new faces.

- The sparkle button at the top opens **Your story**: the moments year by year, each with the faces
  and one line. Tap one to take the timeline to that month.
- By default only your inner circle (the named people photographed the most, about eight) get
  moments; a switch lets everyone have them.
- Moments about people being together only count clear or confirmed faces in photos, never a
  loosely matched blurry face, and never a video (people may appear at different times).
- Photos that are moments are marked with a small bookmark on their tile, and a caption (faces,
  date, the moment) when opened.

## Then and now

On a person's page: their start next to their latest, with a divider to drag between the two, and
up to three photos at each end to choose from.

- The photos come from about the start and about now: the best of the first and latest couple of
  months, widening (2, 4, 8, 12, 18, 24 months) until there are three different photos at each end.
- Each end mixes on their own, with one other person and in a small group, and each photo says
  who is in it ("On their own", "With Dev").
- It needs at least four clear faces with believable dates, over at least six months.

## Names always match the picture

A person is only said to be in a photo (in a notification, a moment, "together since", "on their
own") when their face is confirmed, or is clear and at least 4% of the photo across, so someone in
the background doesn't count. A notification names only the people in the photo it shows.
