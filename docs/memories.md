# Memories

On this day and the daily memory notifications. Everything is worked out on the phone.

## On this day

A card on the Collections tab shows today's date in past years: how many photos and videos there
are from it, a small stack of the best, and, when two named people first appeared in a photo
together on this date, how many years of them it is.

- It opens a screen with a section for each year (the photos that stand for it, and **See all**
  for the whole day). With nothing on the date itself, it shows the week around it.
- The card can be exported as a zip (every photo and video of the date across the years) or
  hidden; hidden cards come back from the tab or from Settings.
- Every indexed photo and video counts, not only those with people. Only believable dates are
  used (the gallery's taken date, the photo's own, a date in its name; never when a file was
  copied), and screenshots are left out.

**How it stays fast on a big library.** Dates are kept in a small catalog (`LibraryDates`,
SQLite) that follows the search index, reading only what was added since last time (never the
vectors). Missing dates are looked up a slice at a time in the background, and each past year is
found with one range lookup on the date index.

## Daily memory notifications

Settings > Memories turns on two notifications a day, each sent only when there is something good:

- **Morning (6:30)** looks back: on this day, anniversaries, a few days of a trip, the same date
  across the years.
- **Evening (7:30)** is about people: then and now, together since, a milestone, a lovely picture.

**Kinds**
- The anniversary of two named people's first photo together, a person's first day in your photos,
  and a person reaching 50, 100, 250, 500, 1000... photos.
- Then and now (one person's start next to their latest), and Then and now together (two people).
- Together since: the years two people have been in photos together.
- On this day (worded differently from day to day), this date in three or more years, and this
  week when the date itself has nothing.
- A few days to remember: three or more busy days in a row around this date in a past year.
- Remember this one?: a lovely picture of someone, picked by the day.

**Taking turns.** The kind that has gone longest without being sent goes next; a kind already sent
today or yesterday waits while another is available; the same person is not the subject again for
45 days; a photo is not shown again for 120 days. A quiet slot sends nothing, and a slot held up
for hours (the phone was off) is skipped. **Send one now** tries a different kind each time
without using up a slot. Tapping a notification opens the person's page, or that day.

**Look.** Folded: a small rounded picture and a heading. Opened: a full-width picture with small
labels for what the words don't say. Then and now is a split with a slanted seam and the years;
together since is a big photo of the two with their first photo tucked into the corner; a trip or
the same date across years is a strip of photos, each with its day or year. Pictures are read from
the original photo, not the small system thumbnail. A locked screen shows only the words.

**Names match the picture.** A notification only names people whose face is confirmed, or clear
and at least 4% of the photo across, in the photo it shows.

## Stories note

The note that says the stories have refreshed (`StoriesReminder`) is set for a day after the app was
last used: when a story is opened, when the app goes to the background, and when an index scan ends.
Each time it replaces the one waiting, and only when there will be rings to see then, opened before
or never. The app sends who those rings are with it, since the note is made later without the app.

- A note that nobody answers sets the next one itself: 2 days later, then 4, then 7. After four
  unanswered notes there are no more until the app is opened, which starts the gaps again.
- At most one a day. A day a daily memory went out is skipped, but not more than two days running.
- Never between 22:00 and 08:00 (moved to 09:00). It opens the app on the Search tab.
- The lock screen shows only the title, and a person with no name is never read out.
