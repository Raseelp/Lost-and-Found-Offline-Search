import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/features/people/models/person.dart';

Person person() => Person(id: 1, name: 'Maya', hidden: false, faceCount: 10, photoCount: 10, coverFaceId: 1);

TimelineRowData row({List<int> offsets = const [], List<int> counts = const [], int? first, int? last}) => TimelineRowData(
      person: person(),
      offsets: offsets,
      counts: counts,
      firstMonth: first,
      lastMonth: last,
      photoCount: counts.fold(0, (a, b) => a + b),
      undated: 0,
    );

void main() {
  group('months', () {
    test('a month counts from year 0, so later months are bigger', () {
      expect(monthIndex(DateTime(2026, 1, 15)), 2026 * 12);
      expect(monthIndex(DateTime(2026, 12, 31)), 2026 * 12 + 11);
      expect(monthIndex(DateTime(2027, 1, 1)), monthIndex(DateTime(2026, 12, 31)) + 1);
    });

    test('a month reads as its short name and the year', () {
      expect(monthLabel(monthIndex(DateTime(2026, 3, 9))), 'Mar 2026');
      expect(monthLabel(monthIndex(DateTime(2019, 12, 1))), 'Dec 2019');
    });
  });

  group('a row of the timeline', () {
    test('the count in a month is found, and a month with none is zero', () {
      final r = row(offsets: [0, 2, 5, 9], counts: [4, 1, 7, 2], first: 100, last: 109);
      expect(r.countAt(0), 4);
      expect(r.countAt(5), 7);
      expect(r.countAt(9), 2);
      expect(r.countAt(3), 0);
      expect(r.countAt(-1), 0);
      expect(r.countAt(50), 0);
    });

    test('a row with no months counts zero everywhere', () {
      final r = row();
      expect(r.countAt(0), 0);
      expect(r.maxCount, 0);
      expect(r.hasDates, isFalse);
    });

    test('the busiest month is the biggest count', () {
      expect(row(offsets: [0, 1, 2], counts: [3, 9, 4], first: 0, last: 2).maxCount, 9);
    });

    test('a row is single when all its photos are from one month', () {
      expect(row(first: 5, last: 5).single, isTrue);
      expect(row(first: 5, last: 6).single, isFalse);
      expect(row().single, isFalse);
    });

    test('the range says no dates, one month, since a year, or the years it spans', () {
      final now = monthIndex(DateTime(2026, 11, 1));
      expect(row().rangeLabel(now), 'No dates yet');
      expect(row(first: monthIndex(DateTime(2024, 5, 1)), last: monthIndex(DateTime(2024, 5, 20))).rangeLabel(now), 'May 2024');
      expect(row(first: monthIndex(DateTime(2018, 2, 1)), last: monthIndex(DateTime(2026, 9, 1))).rangeLabel(now), 'Since 2018');
      expect(row(first: monthIndex(DateTime(2015, 2, 1)), last: monthIndex(DateTime(2019, 9, 1))).rangeLabel(now), '2015 - 2019');
      expect(row(first: monthIndex(DateTime(2015, 2, 1)), last: monthIndex(DateTime(2015, 9, 1))).rangeLabel(now), '2015');
    });
  });
}
