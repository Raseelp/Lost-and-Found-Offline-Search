import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/models/memories.dart';

MemoryPhoto photo(int key) => MemoryPhoto(key: key, uri: 'content://$key', isVideo: false, tsMs: 0, takenMs: 1000 * key);

MemoryYear year(int yearsAgo, {required double strength, int total = 5, List<MemoryPhoto>? photos}) => MemoryYear(
      year: 2026 - yearsAgo,
      yearsAgo: yearsAgo,
      total: total,
      photos: photos ?? [photo(yearsAgo * 10), photo(yearsAgo * 10 + 1)],
      names: const [],
      strength: strength,
    );

OnThisDay day({List<MemoryYear> exact = const [], List<MemoryYear> week = const [], List<MemoryAnniversary> anniversaries = const []}) =>
    OnThisDay(month: 3, day: 9, year: 2026, exact: exact, week: week, anniversaries: anniversaries);

ThenNowSide side(int key) => ThenNowSide(
      key: key,
      uri: 'content://$key',
      faceId: key,
      takenMs: 0,
      boxL: 0,
      boxT: 0,
      boxR: 1,
      boxB: 1,
      photoW: 100,
      photoH: 100,
    );

ThenNow thenNow({int spanMonths = 24, int lastMonth = 0, int startThen = 0, int startNow = 0, int options = 3}) => ThenNow(
      thenOptions: [for (var i = 0; i < options; i++) side(i)],
      nowOptions: [for (var i = 0; i < options; i++) side(100 + i)],
      startThen: startThen,
      startNow: startNow,
      spanMonths: spanMonths,
      lastMonth: lastMonth,
    );

void main() {
  group('labels', () {
    test('a day reads as the month and the number', () {
      expect(dayLabel(3, 9), 'March 9');
      expect(dayLabel(12, 31), 'December 31');
    });

    test('a month number outside 1 to 12 is held to the nearest month', () {
      expect(dayLabel(0, 1), 'January 1');
      expect(dayLabel(13, 1), 'December 1');
    });

    test('years ago is singular for one', () {
      expect(yearsAgoLabel(1), '1 year ago');
      expect(yearsAgoLabel(4), '4 years ago');
    });
  });

  group('OnThisDay', () {
    test('is empty only when there is nothing on the day, in the week or among the anniversaries', () {
      expect(day().isEmpty, isTrue);
      expect(day(week: [year(1, strength: 1)]).isEmpty, isFalse);
      expect(OnThisDay.empty.isEmpty, isTrue);
    });

    test('the exact day is shown when there is one, otherwise the week around it', () {
      final exact = [year(1, strength: 1)];
      final week = [year(2, strength: 1)];
      expect(day(exact: exact, week: week).years, exact);
      expect(day(week: week).years, week);
    });

    test('the total counts the years that are shown', () {
      expect(day(exact: [year(1, strength: 1, total: 4), year(2, strength: 1, total: 6)], week: [year(3, strength: 1, total: 100)]).total, 10);
    });

    test('the label is the date', () {
      expect(day().dateLabel, 'March 9');
    });

    test('cover photos are the first of the strongest years', () {
      final d = day(exact: [year(1, strength: 0.2), year(2, strength: 0.9), year(3, strength: 0.5)]);
      expect(d.coverPhotos().map((p) => p.key), [20, 30, 10]);
      expect(d.coverPhotos(count: 2).map((p) => p.key), [20, 30]);
    });

    test('when there are fewer years than covers, the strongest year gives more of its photos', () {
      final d = day(exact: [year(2, strength: 0.9, photos: [photo(1), photo(2), photo(3), photo(4)])]);
      expect(d.coverPhotos().map((p) => p.key), [1, 2, 3]);
    });

    test('a year without photos is passed over', () {
      final d = day(exact: [year(1, strength: 0.9, photos: const []), year(2, strength: 0.1)]);
      expect(d.coverPhotos().map((p) => p.key), [20]);
    });
  });

  group('MemoryAnniversary.who', () {
    MemoryAnniversary of(List<String> names) => MemoryAnniversary(yearsAgo: 2, ids: const [], names: names, firstMs: 0);

    test('one name stands alone, two are joined with and, three with commas and and', () {
      expect(of(['Maya']).who, 'Maya');
      expect(of(['Maya', 'Dev']).who, 'Maya and Dev');
      expect(of(['Maya', 'Dev', 'Sam']).who, 'Maya, Dev and Sam');
      expect(of(const []).who, '');
    });
  });

  group('ThenNow', () {
    test('the span reads in months for under a year', () {
      expect(thenNow(spanMonths: 1).spanLabel, '1 month');
      expect(thenNow(spanMonths: 7).spanLabel, '7 months');
    });

    test('the span reads in years and months up to five years, and in years after that', () {
      expect(thenNow(spanMonths: 12).spanLabel, '1 year');
      expect(thenNow(spanMonths: 13).spanLabel, '1 year 1 month');
      expect(thenNow(spanMonths: 30).spanLabel, '2 years 6 months');
      expect(thenNow(spanMonths: 5 * 12 + 4).spanLabel, '5 years');
      expect(thenNow(spanMonths: 7 * 12 + 11).spanLabel, '7 years');
    });

    test('the chosen photos are the starting ones, held inside the list', () {
      final t = thenNow(startThen: 1, startNow: 99);
      expect(t.then.key, 1);
      expect(t.now.key, 102);
      expect(thenNow(startThen: -4).then.key, 0);
    });

    test('is now only while the last month is within a year and a half of today', () {
      final lastMonth = 2025 * 12 + 5;
      expect(thenNow(lastMonth: lastMonth).isNow(DateTime(2026, 12, 1)), isTrue);
      expect(thenNow(lastMonth: lastMonth).isNow(DateTime(2027, 1, 1)), isFalse);
    });

    test('a side says who is with them', () {
      ThenNowSide kind(String k, {String? with_}) => ThenNowSide(
            key: 1, uri: 'u', faceId: 1, takenMs: 0, boxL: 0, boxT: 0, boxR: 1, boxB: 1, photoW: 1, photoH: 1, kind: k, withName: with_);
      expect(kind('solo').company, 'On their own');
      expect(kind('duo', with_: 'Dev').company, 'With Dev');
      expect(kind('duo').company, isNull);
      expect(kind('group').company, 'In a group');
      expect(kind('other').company, isNull);
    });
  });

  group('reading what the phone sends', () {
    test('a photo with only its key gets the defaults', () {
      final p = MemoryPhoto.fromMap({'key': 7});
      expect(p.key, 7);
      expect(p.uri, '');
      expect(p.isVideo, isFalse);
      expect(p.names, isEmpty);
    });

    test('a whole day is read, years inside years', () {
      final d = OnThisDay.fromMap({
        'month': 3,
        'day': 9,
        'year': 2026,
        'exact': [
          {
            'year': 2024,
            'yearsAgo': 2,
            'total': 3,
            'strength': 0.5,
            'names': ['Maya'],
            'photos': [
              {'key': 1, 'uri': 'u', 'names': ['Maya']},
            ],
          },
        ],
        'anniversaries': [
          {'yearsAgo': 3, 'ids': [1, 2], 'names': ['Maya', 'Dev'], 'firstMs': 5, 'photo': {'key': 9}},
        ],
      });
      expect(d.exact.single.photos.single.names, ['Maya']);
      expect(d.week, isEmpty);
      expect(d.anniversaries.single.ids, [1, 2]);
      expect(d.anniversaries.single.photo?.key, 9);
    });

    test('an anniversary without a photo has none', () {
      final a = MemoryAnniversary.fromMap({'yearsAgo': 1, 'ids': [], 'names': []});
      expect(a.photo, isNull);
      expect(a.firstMs, 0);
    });

    test('numbers that arrive as decimals are read as whole numbers', () {
      expect(MemoryPhoto.fromMap({'key': 7.0, 'takenMs': 5.0}).takenMs, 5);
    });

    test('settings default to on and allowed, and can be changed one at a time', () {
      final s = MemorySettings.fromMap({});
      expect(s.enabled, isTrue);
      expect(s.allowed, isTrue);
      expect(const MemorySettings().enabled, isTrue);
      final off = s.copyWith(enabled: false);
      expect(off.enabled, isFalse);
      expect(off.allowed, isTrue);
      expect(off.copyWith(allowed: false).enabled, isFalse);
    });
  });
}
