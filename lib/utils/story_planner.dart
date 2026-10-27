import 'dart:math';

import 'package:lost_and_found/models/story_state.dart';

/// A photo or video a story could use, with when it was taken (0 when that is not known).
class StoryItem {
  const StoryItem({required this.uri, required this.isVideo, required this.timestampMs, this.takenMs = 0});

  final String uri;
  final bool isVideo;
  final int timestampMs;
  final int takenMs;

  StoryFrame get frame => StoryFrame(uri: uri, isVideo: isVideo, timestampMs: timestampMs);
}

/// The pictures chosen for one story, how they were chosen ([lens]) and the line that says so.
class StoryPlan {
  const StoryPlan({required this.picks, required this.lens, required this.caption});

  final List<StoryItem> picks;
  final String lens;
  final String caption;
}

/// Chooses the pictures of one story from what a ring has not shown yet.
///
/// A story looks at the pool through one lens, and takes turns: the same ring never uses the same lens twice
/// running (when another will do), so a person's story is about something different each time.
///  - new: taken in the last month ("New this week" / "New this month")
///  - throwback: taken around today's date in an earlier year ("2 years ago")
///  - best: the best matches of a collection ("Some of the best")
///  - forgotten: older than a year, or with no date ("From a while back")
///  - mixed: whatever there is ("Picked for you")
/// The pictures are spread over the lens's time and never two from the same minute or so.
class StoryPlanner {
  static const int minFrames = 3;
  static const int maxFrames = 6;
  static const int _day = 86400000;
  static const int _burst = 10 * 60 * 1000;

  static const String lensNew = 'new';
  static const String lensThrowback = 'throwback';
  static const String lensBest = 'best';
  static const String lensForgotten = 'forgotten';
  static const String lensMixed = 'mixed';

  /// [pool]: what has not been shown (in the order the source gave it: best first when [ranked]). [seed] makes the
  /// choice the same however often it is asked and different for each ring and day. Null: not enough to make a story.
  static StoryPlan? plan({
    required List<StoryItem> pool,
    required DateTime now,
    required int seed,
    String? lastLens,
    bool ranked = false,
  }) {
    if (pool.length < minFrames) return null;
    final nowMs = now.millisecondsSinceEpoch;

    final lenses = <String, List<StoryItem>>{};
    final captions = <String, String>{};

    final recent = [
      for (final i in pool)
        if (i.takenMs > 0 && nowMs - i.takenMs <= 30 * _day && i.takenMs <= nowMs + _day) i,
    ];
    if (recent.length >= minFrames) {
      lenses[lensNew] = recent;
      final newest = recent.map((i) => i.takenMs).reduce(max);
      captions[lensNew] = nowMs - newest <= 7 * _day ? 'New this week' : 'New this month';
    }

    // Around today's date, in the year that has the most. (How far round the year a day is from today's counts, so
    // the end of December is near the start of January.)
    final byYear = <int, List<StoryItem>>{};
    final today = DateTime(now.year, now.month, now.day);
    for (final i in pool) {
      if (i.takenMs <= 0 || i.takenMs > nowMs) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(i.takenMs);
      final years = ((nowMs - i.takenMs) / (365.25 * _day)).round();
      if (years < 1) continue;
      final around =
          (DateTime(d.year, d.month, d.day).difference(DateTime(d.year, 1, 1)).inDays -
                  today.difference(DateTime(now.year, 1, 1)).inDays)
              .abs();
      if (min(around, 365 - around) <= 14) (byYear[years] ??= []).add(i);
    }
    if (byYear.isNotEmpty) {
      final years = byYear.keys.toList()
        ..sort((a, b) {
          final c = byYear[b]!.length.compareTo(byYear[a]!.length);
          return c != 0 ? c : a.compareTo(b);
        });
      if (byYear[years.first]!.length >= minFrames) {
        lenses[lensThrowback] = byYear[years.first]!;
        captions[lensThrowback] = years.first == 1 ? 'A year ago' : '${years.first} years ago';
      }
    }

    if (ranked && pool.length >= minFrames) {
      lenses[lensBest] = pool.take(12).toList();
      captions[lensBest] = 'Some of the best';
    }

    final old = [
      for (final i in pool)
        if (i.takenMs <= 0 || nowMs - i.takenMs > 365 * _day) i,
    ];
    if (old.length >= minFrames) {
      lenses[lensForgotten] = old;
      captions[lensForgotten] = 'From a while back';
    }

    lenses[lensMixed] = pool;
    captions[lensMixed] = 'Picked for you';

    // The lens: not the one before when there is another; new things first; "mixed" only when nothing else fits.
    var options = lenses.keys.where((k) => k != lastLens).toList();
    if (options.isEmpty) options = lenses.keys.toList();
    final specific = options.where((k) => k != lensMixed).toList();
    final String lens;
    if (specific.isEmpty) {
      lens = lensMixed;
    } else if (specific.contains(lensNew)) {
      lens = lensNew;
    } else {
      lens = specific[seed.abs() % specific.length];
    }

    var used = lens;
    var picks = _spread(lenses[lens]!, seed);
    // Too close together to make a story (a burst of photos): the whole pool, then with the gap forgotten.
    if (picks.length < minFrames && lens != lensMixed) {
      used = lensMixed;
      picks = _spread(pool, seed);
    }
    if (picks.length < minFrames) picks = _spread(pool, seed, burst: false);
    if (picks.length < minFrames) return null;
    return StoryPlan(picks: picks, lens: used, caption: captions[used]!);
  }

  // Between 4 and 6 pictures, one from each equal stretch of the lens's items in time order, never one within
  // ten minutes of another, at most two videos and none of them side by side.
  static List<StoryItem> _spread(List<StoryItem> items, int seed, {bool burst = true}) {
    final sorted = [...items]
      ..sort((a, b) {
        if (a.takenMs == 0 && b.takenMs == 0) return 0;
        if (a.takenMs == 0) return 1;
        if (b.takenMs == 0) return -1;
        return a.takenMs.compareTo(b.takenMs);
      });
    final rng = Random(seed);
    final n = min(sorted.length, min(maxFrames, 4 + seed.abs() % 3));

    bool burstWith(StoryItem item, List<StoryItem> chosen) =>
        burst && item.takenMs > 0 && chosen.any((c) => c.takenMs > 0 && (c.takenMs - item.takenMs).abs() < _burst);

    final chosen = <StoryItem>[];
    for (var i = 0; i < n; i++) {
      final from = (i * sorted.length / n).floor();
      final to = max(from + 1, ((i + 1) * sorted.length / n).floor());
      final bucket = [for (var k = from; k < to; k++) sorted[k]]..shuffle(rng);
      StoryItem? pick;
      for (final candidate in bucket) {
        if (burstWith(candidate, chosen)) continue;
        if (candidate.isVideo && chosen.where((c) => c.isVideo).length >= 2) continue;
        pick = candidate;
        break;
      }
      if (pick != null) chosen.add(pick);
    }

    _apartVideos(chosen);
    return chosen;
  }

  static bool _videosTogether(List<StoryItem> list) {
    for (var i = 1; i < list.length; i++) {
      if (list[i].isVideo && list[i - 1].isVideo) return true;
    }
    return false;
  }

  // Not two videos in a row: one of the two is swapped with a picture that is not a video, the first swap that
  // leaves no two side by side (with at most two videos among three or more pictures there always is one).
  static void _apartVideos(List<StoryItem> list) {
    if (!_videosTogether(list)) return;
    for (var mover = 0; mover < list.length; mover++) {
      if (!list[mover].isVideo) continue;
      for (var target = 0; target < list.length; target++) {
        if (list[target].isVideo) continue;
        final t = list[mover];
        list[mover] = list[target];
        list[target] = t;
        if (!_videosTogether(list)) return;
        list[target] = list[mover];
        list[mover] = t;
      }
    }
  }
}

/// What the row of rings needs to know about one candidate.
class RingFacts {
  RingFacts({required this.key, required this.isPerson, required this.count, required this.named, required this.state});

  final String key;
  final bool isPerson;
  final int count;
  final bool named;
  final RingState state;
}

/// One place in the row: the ring, and whether it is lit (something new to see) or grey (seen, a replay).
class RingPick {
  const RingPick(this.facts, this.lit);

  final RingFacts facts;
  final bool lit;
}

/// Chooses which rings are in the row, and in what order.
///
///  - A ring is lit when it has a story that has not been opened, or when 24 hours have passed since its story was
///    opened and it still has something it has not shown. Opening a story greys the ring for those 24 hours (the
///    story can be played again).
///  - A ring with nothing left to show rests for a few days; it stays in the row, grey, with its last story.
///  - At most [maxRings] places. Lit rings take most of them, in the order of a score (what is new in it, how much
///    it has left, how long since it was last seen, a little chance that changes each day) and with a mix of
///    people and collections; up to three places keep the grey ones so the row is not only what is new.
class StoryRowPicker {
  static const int maxRings = 8;
  static const int maxPeople = 5;
  static const int maxCollections = 4;
  static const int day = 86400000;

  static bool canBuild(RingFacts f, int now) {
    final s = f.state;
    if (s.mutedUntil > now || s.restUntil > now) return false;
    return remaining(f) >= StoryPlanner.minFrames;
  }

  /// About how many pictures the ring has not shown in its round: what could be used when it was last looked
  /// at (or all it holds, before that) and what has arrived since, less what was shown.
  static int remaining(RingFacts f) {
    final s = f.state;
    final int known = s.eligible > 0 ? s.eligible + (f.count > s.lastCount ? f.count - s.lastCount : 0) : f.count;
    return known - s.shownCount;
  }

  static bool unviewed(RingState s) => s.hasEdition && s.viewedAt < s.builtAt;

  /// A new story is due: there is none yet, or the last one was opened at least 24 hours ago.
  static bool due(RingFacts f, int now) {
    if (!canBuild(f, now)) return false;
    final s = f.state;
    return !s.hasEdition || (s.viewedAt >= s.builtAt && now - s.viewedAt >= day);
  }

  static bool lit(RingFacts f, int now) => f.state.mutedUntil <= now && (unviewed(f.state) || due(f, now));

  static int _hash(String s) {
    var h = 17;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static double score(RingFacts f, int now, int seed) {
    final s = f.state;
    final fresh = s.lastCount > 0 ? max(0, f.count - s.lastCount) : 0;
    final left = f.count > 0 ? (remaining(f) / f.count).clamp(0.0, 1.0) : 0.0;
    final away = s.viewedAt == 0 ? 14.0 : min(14.0, (now - s.viewedAt) / day);
    final chance = Random(_hash(f.key) ^ seed).nextDouble() * 1.5;
    return (unviewed(s) ? 5 : 0) +
        min(fresh, 20) / 20 * 3 +
        left * 2 +
        away / 14 * 3 +
        chance +
        (f.named || !f.isPerson ? 0 : -0.5);
  }

  /// [seed]: changes with the day (and with a manual refresh). [keepGreys]: places kept for rings that were seen
  /// (a batch that is being made takes none: it is the rings that are lit, and only fills up with grey ones).
  static List<RingPick> pick(List<RingFacts> all, int now, int seed, {int keepGreys = 3}) {
    final lits = [
      for (final f in all)
        if (lit(f, now)) f,
    ]..sort((a, b) => score(b, now, seed).compareTo(score(a, now, seed)));
    final greys = [
      for (final f in all)
        if (!lit(f, now) && f.state.mutedUntil <= now && f.state.hasEdition) f,
    ]..sort((a, b) => b.state.viewedAt.compareTo(a.state.viewedAt));

    final int slots = maxRings - (greys.length < keepGreys ? greys.length : keepGreys);
    final chosen = _balanced(lits, slots);
    final room = maxRings - chosen.length;
    return [for (final f in chosen) RingPick(f, true), for (final f in greys.take(room)) RingPick(f, false)];
  }

  // People and collections in a mix, never more than the caps unless there is nothing else, best first.
  static List<RingFacts> _balanced(List<RingFacts> sorted, int slots) {
    final people = <RingFacts>[], collections = <RingFacts>[], rest = <RingFacts>[];
    for (final f in sorted) {
      if (f.isPerson && people.length < maxPeople) {
        people.add(f);
      } else if (!f.isPerson && collections.length < maxCollections) {
        collections.add(f);
      } else {
        rest.add(f);
      }
    }
    var chosen = <RingFacts>[...people, ...collections]..sort((a, b) => sorted.indexOf(a).compareTo(sorted.indexOf(b)));
    if (chosen.length > slots) chosen = chosen.take(slots).toList();
    for (final f in rest) {
      if (chosen.length >= slots) break;
      chosen.add(f);
    }
    // Alternate the kinds, each keeping its own order, starting with whichever leads.
    final p = [
          for (final f in chosen)
            if (f.isPerson) f,
        ],
        c = [
          for (final f in chosen)
            if (!f.isPerson) f,
        ];
    final out = <RingFacts>[];
    var takePerson = p.isNotEmpty && (c.isEmpty || chosen.indexOf(p.first) < chosen.indexOf(c.first));
    while (p.isNotEmpty || c.isNotEmpty) {
      if (takePerson && p.isNotEmpty) {
        out.add(p.removeAt(0));
      } else if (!takePerson && c.isNotEmpty) {
        out.add(c.removeAt(0));
      } else if (p.isNotEmpty) {
        out.add(p.removeAt(0));
      } else {
        out.add(c.removeAt(0));
      }
      takePerson = !takePerson;
    }
    return out;
  }
}

/// The rings of the row, kept together as one batch.
///
/// The row is not a window that slides over everything there is: a batch of up to eight rings is chosen, and those
/// stay in the row (the ones that were opened go grey and move behind the ones that have not) until the batch has been
/// used up. A ring opened in the batch stays grey for the rest of it. When every ring of the batch has been opened,
/// and a day has gone by since the last was, the next batch is chosen (other rings are preferred, so it is not the same
/// rings again). A refresh by hand starts the next batch at once. A batch nobody finishes stays as it is.
class StoryBatch {
  const StoryBatch({this.keys = const [], this.lit = const {}, this.at = 0});

  /// The rings in the batch, and which of them were lit (had something to show) when it was made; [at]: when.
  final List<String> keys;
  final Set<String> lit;
  final int at;

  bool get isEmpty => keys.isEmpty;

  /// The ring was opened since this batch was made (its story was made, and opened, after it).
  bool openedIn(RingState s) => s.hasEdition && s.viewedAt >= at && s.viewedAt >= s.builtAt;

  /// Whether the ring has something new to see. Within a batch only the rings that were lit when it was made can be,
  /// and not once they have been opened.
  bool isLit(RingFacts f, int now) {
    if (!StoryRowPicker.lit(f, now)) return false;
    if (lit.contains(f.key)) return !openedIn(f.state);
    return keys.isEmpty;
  }

  /// This batch, or a new one: when this is empty, when none of its rings is left, when every ring in it was opened and a
  /// day has gone by since the last, or when [force] says so (a refresh by hand). Not while [ready] is false (people and
  /// collections are still being found at the start of the app: a batch made from some of them would keep the others out,
  /// and an empty list of them would end the batch there is).
  StoryBatch next(List<RingFacts> all, int now, int seed, {bool force = false, bool ready = true}) {
    if (!ready) return this;
    final byKey = {for (final f in all) f.key: f};
    final present = [
      for (final k in keys)
        if (byKey[k] != null && byKey[k]!.state.mutedUntil <= now) byKey[k]!,
    ];
    var rebuild = force || present.isEmpty;
    final anyLit = present.any((f) => isLit(f, now));
    if (!rebuild && !anyLit) {
      final last = present.fold<int>(0, (a, f) => max(a, f.state.viewedAt));
      rebuild = now - last >= StoryRowPicker.day;
    }
    if (!rebuild) return this;

    final picks = StoryRowPicker.pick(all, now, seed, keepGreys: 0);
    if (picks.isEmpty) return present.isEmpty ? StoryBatch(at: now) : this;
    final newLit = {
      for (final p in picks)
        if (p.lit) p.facts.key,
    };
    // Nothing new to light up: what is there stays, rather than being chosen again every time it is asked.
    if (!force && present.isNotEmpty && newLit.isEmpty && !anyLit) return this;
    return StoryBatch(keys: [for (final p in picks) p.facts.key], lit: newLit, at: now);
  }
}
