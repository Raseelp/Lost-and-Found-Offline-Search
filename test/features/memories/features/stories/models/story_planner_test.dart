import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/memories/features/stories/models/story_state.dart';
import 'package:lost_and_found/features/memories/features/stories/models/story_planner.dart';

const int day = 86400000;

StoryItem item(int i, int takenMs, {bool video = false}) =>
    StoryItem(uri: 'content://media/$i', isVideo: video, timestampMs: 0, takenMs: takenMs);

void main() {
  final now = DateTime(2026, 6, 15, 12);
  final nowMs = now.millisecondsSinceEpoch;

  List<StoryItem> spreadOverDays(int count, {required int daysAgoFrom, int stepDays = 2}) =>
      [for (var i = 0; i < count; i++) item(i, nowMs - (daysAgoFrom + i * stepDays) * day)];

  group('StoryPlanner.plan', () {
    test('needs at least 3 pictures', () {
      expect(StoryPlanner.plan(pool: spreadOverDays(2, daysAgoFrom: 1), now: now, seed: 1), isNull);
      expect(StoryPlanner.plan(pool: const [], now: now, seed: 1), isNull);
    });

    test('recent photos make a story called New this week, or New this month when the newest is older', () {
      final week = StoryPlanner.plan(pool: spreadOverDays(6, daysAgoFrom: 1), now: now, seed: 3)!;
      expect(week.lens, StoryPlanner.lensNew);
      expect(week.caption, 'New this week');
      final month = StoryPlanner.plan(pool: spreadOverDays(6, daysAgoFrom: 10), now: now, seed: 3)!;
      expect(month.lens, StoryPlanner.lensNew);
      expect(month.caption, 'New this month');
    });

    test('photos from this time of year in an earlier year make a throwback, with the years in the caption', () {
      final twoYearsAgo = DateTime(2024, 6, 12).millisecondsSinceEpoch;
      final pool = [for (var i = 0; i < 6; i++) item(i, twoYearsAgo + i * day)];
      final plan = StoryPlanner.plan(pool: pool, now: now, seed: 4, lastLens: StoryPlanner.lensForgotten)!;
      expect(plan.lens, StoryPlanner.lensThrowback);
      expect(plan.caption, '2 years ago');
    });

    test('a throwback from one year back says A year ago', () {
      final oneYearAgo = DateTime(2025, 6, 14).millisecondsSinceEpoch;
      final pool = [for (var i = 0; i < 6; i++) item(i, oneYearAgo + i * day)];
      final plan = StoryPlanner.plan(pool: pool, now: now, seed: 4, lastLens: StoryPlanner.lensForgotten)!;
      expect(plan.caption, 'A year ago');
    });

    test('old and undated photos make a story from a while back', () {
      final pool = [for (var i = 0; i < 8; i++) item(i, i.isEven ? 0 : nowMs - (400 + i * 40) * day)];
      final plan = StoryPlanner.plan(pool: pool, now: now, seed: 1)!;
      expect(plan.lens, StoryPlanner.lensForgotten);
      expect(plan.caption, 'From a while back');
    });

    test('a ranked pool can make a story of the best ones', () {
      final pool = [for (var i = 0; i < 12; i++) item(i, nowMs - (500 + i * 30) * day)];
      final best = StoryPlanner.plan(pool: pool, now: now, seed: 0, ranked: true)!;
      expect(best.lens, StoryPlanner.lensBest);
      expect(best.caption, 'Some of the best');
    });

    test('a story is never of the kind the last one was, when there is another', () {
      final pool = spreadOverDays(8, daysAgoFrom: 1);
      final plan = StoryPlanner.plan(pool: pool, now: now, seed: 5, lastLens: StoryPlanner.lensNew)!;
      expect(plan.lens, StoryPlanner.lensMixed);
      expect(plan.caption, 'Picked for you');
    });

    test('has between 3 and 6 pictures, each only once, all from the pool', () {
      final pool = spreadOverDays(30, daysAgoFrom: 1);
      for (var seed = 0; seed < 25; seed++) {
        final plan = StoryPlanner.plan(pool: pool, now: now, seed: seed)!;
        expect(plan.picks.length, inInclusiveRange(StoryPlanner.minFrames, StoryPlanner.maxFrames));
        expect(plan.picks.map((p) => p.uri).toSet().length, plan.picks.length);
        expect(plan.picks.every(pool.contains), isTrue);
      }
    });

    test('the same seed gives the same story', () {
      final pool = spreadOverDays(30, daysAgoFrom: 1);
      final a = StoryPlanner.plan(pool: pool, now: now, seed: 9)!;
      final b = StoryPlanner.plan(pool: pool, now: now, seed: 9)!;
      expect(a.picks.map((p) => p.uri), b.picks.map((p) => p.uri));
      expect(a.lens, b.lens);
    });

    test('different seeds give different stories from a big pool', () {
      final pool = spreadOverDays(60, daysAgoFrom: 1);
      final firsts = {for (var s = 0; s < 12; s++) StoryPlanner.plan(pool: pool, now: now, seed: s)!.picks.map((p) => p.uri).join(',')};
      expect(firsts.length, greaterThan(3));
    });

    test('takes at most one picture from a burst taken within ten minutes', () {
      final burst = [for (var i = 0; i < 6; i++) item(i, nowMs - 20 * day + i * 1000)];
      final others = [for (var i = 0; i < 8; i++) item(10 + i, nowMs - (30 + i * 3) * day)];
      for (var seed = 0; seed < 10; seed++) {
        final plan = StoryPlanner.plan(pool: [...burst, ...others], now: now, seed: seed, lastLens: StoryPlanner.lensNew)!;
        expect(plan.picks.where(burst.contains).length, lessThanOrEqualTo(1));
      }
    });

    test('has at most two videos, and not two in a row', () {
      final pool = [for (var i = 0; i < 20; i++) item(i, nowMs - (1 + i * 2) * day, video: i % 2 == 0)];
      for (var seed = 0; seed < 25; seed++) {
        final picks = StoryPlanner.plan(pool: pool, now: now, seed: seed)!.picks;
        expect(picks.where((p) => p.isVideo).length, lessThanOrEqualTo(2));
        for (var i = 1; i < picks.length; i++) {
          expect(picks[i].isVideo && picks[i - 1].isVideo, isFalse, reason: 'seed $seed');
        }
      }
    });

    test('a story item knows its own frame', () {
      final it = StoryItem(uri: 'u', isVideo: true, timestampMs: 1500, takenMs: 5);
      expect(it.frame.uri, 'u');
      expect(it.frame.isVideo, isTrue);
      expect(it.frame.timestampMs, 1500);
    });
  });

  group('StoryRowPicker', () {
    RingFacts ring(String key, {bool person = true, int count = 30, bool named = true, void Function(RingState)? state}) {
      final s = RingState(key);
      state?.call(s);
      return RingFacts(key: key, isPerson: person, count: count, named: named, state: s);
    }

    StoryFrame frame() => const StoryFrame(uri: 'u', isVideo: false, timestampMs: 0);

    test('what is left is what it has not shown yet, counting photos added since', () {
      expect(StoryRowPicker.remaining(ring('a', count: 30)), 30);
      expect(StoryRowPicker.remaining(ring('a', count: 30, state: (s) => s.shownCount = 12)), 18);
      expect(StoryRowPicker.remaining(ring('a', count: 40, state: (s) {
        s.eligible = 30;
        s.lastCount = 30;
        s.shownCount = 10;
      })), 30);
    });

    test('a story can only be built with at least 3 left, and not while resting or set aside', () {
      final now = 1000 * day;
      expect(StoryRowPicker.canBuild(ring('a', count: 2), now), isFalse);
      expect(StoryRowPicker.canBuild(ring('a', count: 3), now), isTrue);
      expect(StoryRowPicker.canBuild(ring('a', state: (s) => s.mutedUntil = now + 1), now), isFalse);
      expect(StoryRowPicker.canBuild(ring('a', state: (s) => s.restUntil = now + 1), now), isFalse);
      expect(StoryRowPicker.canBuild(ring('a', state: (s) => s.mutedUntil = now - 1), now), isTrue);
    });

    test('a ring with no story yet is due, and lit', () {
      final f = ring('a');
      expect(StoryRowPicker.due(f, 1000 * day), isTrue);
      expect(StoryRowPicker.lit(f, 1000 * day), isTrue);
    });

    test('a story that has not been watched stays lit', () {
      final f = ring('a', state: (s) {
        s.frames = [frame()];
        s.builtAt = 900 * day;
      });
      expect(StoryRowPicker.unviewed(f.state), isTrue);
      expect(StoryRowPicker.lit(f, 1000 * day), isTrue);
    });

    test('a watched story is grey for a day, then a new one is due', () {
      final f = ring('a', state: (s) {
        s.frames = [frame()];
        s.builtAt = 900 * day;
        s.viewedAt = 1000 * day;
      });
      expect(StoryRowPicker.lit(f, 1000 * day + day ~/ 2), isFalse);
      expect(StoryRowPicker.lit(f, 1001 * day + 1), isTrue);
    });

    test('a ring set aside is never lit', () {
      final f = ring('a', state: (s) => s.mutedUntil = 2000 * day);
      expect(StoryRowPicker.lit(f, 1000 * day), isFalse);
    });

    test('a ring that has not been watched scores higher than one that has', () {
      final fresh = ring('a', state: (s) {
        s.frames = [frame()];
        s.builtAt = 900 * day;
      });
      final seen = ring('a', state: (s) {
        s.frames = [frame()];
        s.builtAt = 900 * day;
        s.viewedAt = 950 * day;
      });
      expect(StoryRowPicker.score(fresh, 1000 * day, 1), greaterThan(StoryRowPicker.score(seen, 1000 * day, 1)));
    });

    test('a person without a name scores a little lower', () {
      expect(
        StoryRowPicker.score(ring('a', named: false), 1000 * day, 1),
        lessThan(StoryRowPicker.score(ring('a', named: true), 1000 * day, 1)),
      );
    });

    test('shows at most 8 rings, with at most 5 people and room for collections', () {
      final all = [
        for (var i = 0; i < 7; i++) ring('p$i'),
        for (var i = 0; i < 6; i++) ring('c$i', person: false),
      ];
      final picks = StoryRowPicker.pick(all, 1000 * day, 7);
      expect(picks.length, StoryRowPicker.maxRings);
      expect(picks.every((p) => p.lit), isTrue);
      expect(picks.where((p) => p.facts.isPerson).length, lessThanOrEqualTo(StoryRowPicker.maxPeople));
      expect(picks.where((p) => !p.facts.isPerson).length, greaterThanOrEqualTo(3));
    });

    test('keeps a few grey rings after the lit ones', () {
      final lit = [for (var i = 0; i < 8; i++) ring('lit$i')];
      final grey = [
        for (var i = 0; i < 4; i++)
          ring('grey$i', state: (s) {
            s.frames = [frame()];
            s.builtAt = 900 * day;
            s.viewedAt = 1000 * day;
          }),
      ];
      final picks = StoryRowPicker.pick([...lit, ...grey], 1000 * day + day ~/ 2, 3);
      expect(picks.length, StoryRowPicker.maxRings);
      expect(picks.where((p) => !p.lit).length, 3);
      expect(picks.take(5).every((p) => p.lit), isTrue);
    });

    test('a row with nothing to show is empty', () {
      expect(StoryRowPicker.pick(const [], 1000 * day, 1), isEmpty);
      expect(StoryRowPicker.pick([ring('a', count: 1)], 1000 * day, 1), isEmpty);
    });
  });

  group('StoryBatch top-up', () {
    RingFacts ring(String key, {bool person = true, int count = 30}) =>
        RingFacts(key: key, isPerson: person, count: count, named: true, state: RingState(key));

    StoryBatch first(List<RingFacts> all) => const StoryBatch().next(all, nowMs, 1);

    test('rings that appear after the batch was made join it while it has places left', () {
      final one = [ring('a')];
      final batch = first(one);
      expect(batch.keys, ['a']);
      final grown = batch.next([...one, ring('b'), ring('c', person: false)], nowMs, 1);
      expect(grown.keys.first, 'a');
      expect(grown.keys.toSet(), {'a', 'b', 'c'});
      expect(grown.isLit(ring('b'), nowMs), isTrue);
      expect(grown.isLit(ring('c', person: false), nowMs), isTrue);
    });

    test('a ring with too few pictures is not added', () {
      final batch = first([ring('a')]);
      final same = batch.next([ring('a'), ring('b', count: 2)], nowMs, 1);
      expect(identical(same, batch), isTrue);
    });

    test('a full batch takes nothing more', () {
      final eight = [for (var i = 0; i < 8; i++) ring('r$i', person: i.isEven)];
      final batch = first(eight);
      expect(batch.keys.length, 8);
      final same = batch.next([...eight, ring('extra')], nowMs, 1);
      expect(identical(same, batch), isTrue);
    });

    test('only the places that are left are filled, best rings first', () {
      final seven = [for (var i = 0; i < 7; i++) ring('r$i', person: i.isEven)];
      final batch = first(seven);
      final grown = batch.next([...seven, ring('x', person: false), ring('y', person: false)], nowMs, 1);
      expect(grown.keys.length, 8);
    });

    test('asking again changes nothing once the rings have joined', () {
      final batch = first([ring('a')]);
      final all = [ring('a'), ring('b')];
      final grown = batch.next(all, nowMs, 1);
      expect(identical(grown.next(all, nowMs, 1), grown), isTrue);
    });

    test('a ring that has gone away does not use up a place, and its key is kept', () {
      final seven = [for (var i = 0; i < 7; i++) ring('r$i', person: i.isEven)];
      final batch = first([...seven, ring('gone')]);
      expect(batch.keys.length, 8);
      final grown = batch.next([...seven, ring('x', person: false)], nowMs, 1);
      expect(grown.keys.contains('gone'), isTrue);
      expect(grown.keys.contains('x'), isTrue);
    });

    test('a ring of the kind that has room is taken before one that would pass the cap', () {
      final people = [for (var i = 0; i < 5; i++) ring('p$i')];
      final batch = first(people);
      expect(batch.keys.length, 5);
      final grown = batch.next([...people, ring('p5'), ring('p6'), ring('c', person: false)], nowMs, 1);
      expect(grown.keys.length, 8);
      expect(grown.keys.contains('c'), isTrue);
    });

    test('a ring the batch already holds is never added twice', () {
      final batch = first([ring('a'), ring('b')]);
      final grown = batch.next([ring('a'), ring('b'), ring('c')], nowMs, 1);
      expect(grown.keys.where((k) => k == 'a').length, 1);
      expect(grown.keys.where((k) => k == 'b').length, 1);
    });

    test('the rings already in the batch keep their place and their lit state', () {
      final a = ring('a');
      final batch = first([a]);
      final grown = batch.next([a, ring('b')], nowMs, 1);
      expect(grown.keys.first, 'a');
      expect(grown.at, batch.at);
    });
  });

  group('StoryArrivals', () {
    StoryFrame frame(String u, {bool fresh = false}) => StoryFrame(uri: u, isVideo: false, timestampMs: 0, fresh: fresh);

    test('a picture stands for the same number on every run, and different pictures differ', () {
      expect(StoryArrivals.hash('content://media/1'), StoryArrivals.hash('content://media/1'));
      expect(StoryArrivals.hash('content://media/1'), isNot(StoryArrivals.hash('content://media/2')));
    });

    test('the new ones are the pictures that were not known, newest first', () {
      final items = [item(1, 100), item(2, 300), item(3, 200), item(4, 50)];
      final known = {StoryArrivals.hash(items[0].uri), StoryArrivals.hash(items[3].uri)};
      final fresh = StoryArrivals.fresh(items, known);
      expect(fresh.map((i) => i.uri), [items[1].uri, items[2].uri]);
    });

    test('nothing is new when everything was known, and at most six are taken', () {
      final items = [for (var i = 0; i < 10; i++) item(i, i)];
      expect(StoryArrivals.fresh(items, {for (final i in items) StoryArrivals.hash(i.uri)}), isEmpty);
      expect(StoryArrivals.fresh(items, {}).length, StoryArrivals.maxNew);
    });

    test('new pictures join after the story, marked unread, and the story opens at the first of them', () {
      final story = [frame('a'), frame('b'), frame('c')];
      final joined = StoryArrivals.join(story, [item(7, 5), item(8, 4)]);
      expect(joined.length, 5);
      expect(joined.map((f) => f.fresh), [false, false, false, true, true]);
      expect(StoryArrivals.firstUnread(joined), 3);
    });

    test('a story without unread pictures opens at the start', () {
      expect(StoryArrivals.firstUnread([frame('a'), frame('b')]), 0);
      expect(StoryArrivals.firstUnread(const []), 0);
    });

    test('marks that were already there stay when more arrive', () {
      final story = [frame('a'), frame('b', fresh: true)];
      final joined = StoryArrivals.join(story, [item(9, 1)]);
      expect(joined.map((f) => f.fresh), [false, true, true]);
      expect(StoryArrivals.firstUnread(joined), 1);
    });

    test('a long story loses its oldest read pictures first, never an unread one', () {
      final story = [for (var i = 0; i < 10; i++) frame('old$i')];
      final joined = StoryArrivals.join(story, [for (var i = 0; i < 6; i++) item(100 + i, i)]);
      expect(joined.length, StoryArrivals.maxFrames);
      expect(joined.where((f) => f.fresh).length, 6);
      expect(joined.first.uri, 'old4');
    });

    test('the unread mark survives being saved and read back, and is not written when it is not set', () {
      expect(frame('a', fresh: true).toJson()['n'], isTrue);
      expect(frame('a').toJson().containsKey('n'), isFalse);
      expect(StoryFrame.fromJson(frame('a', fresh: true).toJson()).fresh, isTrue);
      expect(StoryFrame.fromJson({'u': 'x'}).fresh, isFalse);
      expect(frame('a', fresh: true).withFresh(false).fresh, isFalse);
    });
  });

  group('StoryBatch.withLit', () {
    test('a ring of the batch that was not lit becomes lit, and others are left alone', () {
      const batch = StoryBatch(keys: ['a', 'b'], lit: {'a'}, at: 5);
      final lit = batch.withLit('b');
      expect(lit.lit, {'a', 'b'});
      expect(lit.at, 5);
      expect(identical(batch.withLit('a'), batch), isTrue);
      expect(identical(batch.withLit('zzz'), batch), isTrue);
    });
  });

  group('RingState', () {
    test('frames survive being saved and read back', () {
      final s = RingState('k')
        ..frames = const [
          StoryFrame(uri: 'content://a', isVideo: false, timestampMs: 0),
          StoryFrame(uri: 'content://b', isVideo: true, timestampMs: 2500),
        ];
      final back = RingState.framesFrom(s.framesJson);
      expect(back.map((f) => f.uri), ['content://a', 'content://b']);
      expect(back[1].isVideo, isTrue);
      expect(back[1].timestampMs, 2500);
      expect(s.hasEdition, isTrue);
    });

    test('empty or damaged saved frames read as none', () {
      expect(RingState.framesFrom(null), isEmpty);
      expect(RingState.framesFrom(''), isEmpty);
      expect(RingState.framesFrom('not json'), isEmpty);
      expect(RingState.framesFrom('{"a":1}'), isEmpty);
      expect(RingState('k').hasEdition, isFalse);
    });
  });
}
