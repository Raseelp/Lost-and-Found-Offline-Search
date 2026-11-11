# Stories

Rings on the Search tab. Tap a ring to watch a short story of that person's or that collection's photos
and videos. A ring that was opened is grey for a day, then has a new story made of pictures it has not
shown before.

## Who gets a ring

- Every person with at least one photo. People without a name come after the named ones.
- Nine built-in collections that are nice to look at: beach, flowers, mountains, golden hour, night sky,
  rainy, road trip, pets and food.
- Not screenshots, documents, tickets, notes or memes, and not collections you made. Screenshots are
  never used in a story.

## The row

The row holds one batch of up to eight rings: normally at most five people and four collections, taking
turns. The batch stays until every ring in it has been opened and a day has passed since the last one, or
until you press Refresh. Rings you opened go grey and move behind the ones you have not. The next batch
tends to choose other rings, so it is not the same ones again.

- A ring is lit when it has a story you have not opened, or when 24 hours have passed since you opened
  its story and it still has pictures it has not shown.
- Rings are ordered by a score: what is new in them, how much they have left, how long since they were
  seen, and a little chance that changes each day.
- Refresh is a button that appears only when every ring in the row has been seen. It makes the opened
  rings due again at once, with pictures they have not shown.
- A long press on a ring and "Not now" leaves it out for 30 days.
- After a search the rings shrink into a strip above the results. "Stories" in the strip goes back.
- Nothing is built while people and collections are still being found at app start, so a batch is never
  made from only some of them.

## One story

A story is made when it is first needed: when its ring is opened, and a moment later for the rings beside
it, so the turn to them is quick. It has four to six pictures, spread through the
time of one lens. Never two within ten minutes of each other, at most two videos, and never two videos in
a row. At least three pictures must be left to make a story.

| Lens | What it uses | Caption |
|---|---|---|
| new | taken in the last 30 days | New this week, New this month |
| throwback | taken within two weeks of today's date in an earlier year | A year ago, 2 years ago |
| best | the best matches of a collection | Some of the best |
| forgotten | older than a year, or with no date | From a while back |
| mixed | anything left | Picked for you |

The same ring does not use the same lens twice running when another one will do. New pictures come
first, and mixed is used only when nothing else fits.

## Not repeating

- The pictures of each story are written down when it is made (`stories.db`, tables `rings` and `shown`,
  with a `meta` table for the row). A ring never shows one of them again in the same round.
- A story nobody has opened never expires, and its pictures count as shown from the moment it is made.
  Opening it for the first time greys the ring for 24 hours. Playing it again changes nothing.
- When fewer than three unshown pictures are left, the ring rests for three days. It stays in the row,
  grey, with its last story. Then a new round starts with everything it holds.
- Pictures that arrive after a scan count as new.

## Watching

- Each picture is on screen for five seconds. A video plays for up to fifteen seconds (at least two) and
  starts muted. The sound button unmutes it at once, and it stays unmuted until the app is closed.
- Tap the right side for the next picture and the left for the one before. Hold to pause. Swipe sideways
  to turn to the next ring like the face of a cube. Pull down to close.
- The button at the bottom opens the person's photos as a search in the Search tab, or the person's or the
  collection's own page.
- With "Remove animations" on, the five seconds are kept, and the pages jump instead of turning. See
  [Development](development.md#reduced-motion).

## The note

A note that says your stories have refreshed comes a day after you last used the app. See
[Memories](memories.md#stories-note). It can be turned off with the Stories reminder switch in Settings.

## In the code

- `lib/features/memories/features/stories/models/story_planner.dart`: the lenses, the choice of pictures, the row and the batch.
- `lib/features/memories/features/stories/controllers/stories_controller.dart`: the rings, the stories, the saved state and the note.
- `lib/features/memories/features/stories/db/stories_store.dart`: `stories.db`.
- `story_viewer_screen.dart` and `widgets/story_rings.dart` in `lib/features/memories/features/stories/view/`: the viewer and the rings.
- `android/.../memories/StoriesReminder.kt` and `StoriesRingRow.kt`: the note.
