# Design notes

Why a few of the less obvious parts are built the way they are. The code carries no long explanations, so they are here.

## The dates catalog

`LibraryDates` (`features/memories/`) is the catalog of when every photo and video in the search index was taken. It
backs On this day, the memories and the timeline, and it is built to stay cheap however big the library is.

- It follows the index instead of reading it again. The embedding file only grows, until a folder is removed, so
  `sync` reads just what was added since last time, from a saved byte position, and never loads an embedding. When
  the file is rewritten (a folder removed, everything cleared) its generation number changes, and the catalog is
  checked against the whole file once, keeping the dates already found.
- Dates are looked up a slice at a time. `resolve` works through the files that have no date for a time budget, so it
  can be called again and again, and it takes the dates the people timeline already found before reading anything.
- A day is found with the date index, one range scan per past year, so the cost of "this day in every year" depends
  on how many years there are and not on how many photos.
- Only dates that can be believed count: the gallery's taken date, the picture's own date, or a date in its name. A
  file's change date is when it was copied, not when it was taken. Screenshots are left out.

## One hub for a scan

`ScanForegroundService` is not an Android service any more. It is the process-wide hub for everything about a scan
that is not the embedding work: the notification, the latest progress, the progress channel to Dart, and the wake
lock that keeps the CPU awake. WorkManager owns the foreground lifecycle (`ScanWorker`). These pieces live in one
static place because a scan can outlive whatever started it, such as an activity recreated from Recents, and a new
Flutter engine has to pick up the progress where it is.

- The wake lock has a ceiling that every progress tick pushes out, so a stalled scan cannot hold it for ever and a long
  one never reaches it.
- The face scan that runs in step with indexing (`FaceFollower`) reports into the same notification, so there is only
  ever one: it shows the batch being worked on, and indexing waits while a batch is. Speeds are measured over the time
  spent indexing, so waiting for faces does not slow the number down.
- A notification the person swiped away is not posted again for the rest of that scan.

## The bento grid

The search results grid is built from short runs of tiles, called movements. Each run, on its own, ends with every
column at the same height, which was checked with a standalone copy of the packing algorithm of
`flutter_staggered_grid_view`. Joining two flush runs is flush again, so any sequence of them can be chained in any
order with no gaps or overlaps. That is what lets the generator add a rare showcase run (one photo taking far more
room than usual) into the steady rhythm without risking a broken layout. A tile big enough to need it asks for a
higher decode size, instead of raising it for every tile.

## The liquid action button

The round action button on the People and Collections tabs is drawn as one blob of liquid (`action_fab.dart`). Its
actions are drops of the same liquid: each one clings to the button on a thick neck, pulls away faster and faster
until the neck pinches off, runs a little past its place and settles. Closing plays the same thing backwards. When
the tab has no actions the button runs down into the search button and the two merge, and it lets go again with a
stretch when the actions come back. With "Remove animations" on the actions fade in where they belong and the button
jumps between its places.
