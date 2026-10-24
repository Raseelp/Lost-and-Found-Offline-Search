# Export as zip

Put collections and people in a zip to keep, send or move to another phone. Your photos and videos
are only read, never changed or removed.

## Where to start it

- **Select collections** from the bolt button on the Collections tab, then **Export as zip** in the bar at the bottom.
- **Select people** from the bolt button on the People tab, then **Export as zip** (the bar also offers **Photos
  together**).
- A collection's or person's menu, or the **Export** button on a person's page.
- The On this day card's menu (every photo and video of the date across the years).

## What goes in

- Any number of collections and people (with a search box and **Select all**).
- Each becomes a folder in the zip, with an `Images` and a `Videos` folder inside. A photo in two
  chosen albums is stored in both.
- Files are stored uncompressed (photos and videos already are), keep their names, and carry the
  date they were taken (else the date last changed).

## Settings

- **Name.** One album: its name. Several: "Lost & Found export" and the date.
- **Where to save.** Downloads › Lost & Found, or any folder you pick (before Android 10 a folder
  has to be picked).
- **File list.** An optional `list.json` with each file's name, date and size; no original paths.
  On by default.

## Splitting

From about 100 MB up, the zip can be cut into parts of 4 GB, 2 GB, 1 GB, 512 MB, or a size you
choose. Each part is a complete zip that opens on its own, and no file is ever cut across two
parts. A part expected to pass about 3 GB (or 60,000 files) uses the 64-bit zip format; smaller
ones are plain zips every tool reads.

## Making it

The zip is written by background work (`export/ZipExportWorker.kt`) with a notification, so it
carries on if you leave the app. Cancelling, or a failure, deletes everything made so far. The zip
writer has a JVM unit test that also checks other zip tools can read what it writes (see
[Development](development.md)).
