import 'dart:math' as math;

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import 'package:lost_and_found/services/native_services.dart';

/// The months one person appears in, as the phone counted them (see FaceStore.peopleTimeline).
/// A month is year * 12 + the 0-based month, so January 2019 is 24228.
class PersonTimeline {
  const PersonTimeline({
    required this.id,
    required this.months,
    required this.counts,
    required this.dated,
    required this.undated,
  });

  final int id;

  /// Months with at least one photo or video, oldest first, and how many each has.
  final List<int> months;
  final List<int> counts;

  /// Photos and videos with a date, and without one (or not looked at yet).
  final int dated, undated;

  factory PersonTimeline.fromMap(Map<dynamic, dynamic> m) {
    final flat = [for (final v in (m['months'] as List? ?? const [])) (v as num).toInt()];
    return PersonTimeline(
      id: (m['id'] as num).toInt(),
      months: [for (var i = 0; i + 1 < flat.length; i += 2) flat[i]],
      counts: [for (var i = 0; i + 1 < flat.length; i += 2) flat[i + 1]],
      dated: (m['dated'] as num?)?.toInt() ?? 0,
      undated: (m['undated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The person someone is photographed with the most: [count] photos and videos together, the
/// first in [firstMonth] (the photo or video [firstUri], when it is known).
class Companion {
  const Companion({required this.withId, required this.count, required this.firstMonth, this.firstUri});

  final int withId, count, firstMonth;
  final String? firstUri;
}

/// A photo or video that stands for a moment of several people (the most people in one shot in a
/// year, or people coming back together), with what is needed to show it.
class GroupMedia {
  const GroupMedia({
    required this.key,
    required this.takenMs,
    required this.people,
    required this.gapDays,
    required this.uri,
    required this.isVideo,
    required this.tsMs,
  });

  final int key, takenMs, gapDays, tsMs;
  final List<int> people;
  final String uri;
  final bool isVideo;

  int get month => monthIndex(DateTime.fromMillisecondsSinceEpoch(takenMs));

  PreviewPhoto get photo => PreviewPhoto(key: key, uri: uri, isVideo: isVideo, tsMs: tsMs, takenMs: takenMs);

  factory GroupMedia.fromMap(Map<dynamic, dynamic> m) => GroupMedia(
    key: (m['key'] as num).toInt(),
    takenMs: (m['takenMs'] as num).toInt(),
    people: [for (final id in (m['people'] as List? ?? const [])) (id as num).toInt()],
    gapDays: (m['gapDays'] as num?)?.toInt() ?? 0,
    uri: m['uri'] as String? ?? '',
    isVideo: m['isVideo'] as bool? ?? false,
    tsMs: (m['tsMs'] as num?)?.toInt() ?? 0,
  );
}

/// What the phone knows so far: everyone's months, and how far the looking-up of dates has got
/// ([pending] photos and videos still to look at, of [total]).
class TimelineData {
  const TimelineData({
    this.total = 0,
    this.pending = 0,
    this.byPerson = const {},
    this.together = const {},
    this.crowds = const [],
    this.reunions = const [],
  });

  static const empty = TimelineData();

  final int total, pending;
  final Map<int, PersonTimeline> byPerson;

  /// For each person, who they are photographed with most.
  final Map<int, Companion> together;

  /// The best group shots of each year, and the photos where people came back together.
  final List<GroupMedia> crowds, reunions;

  bool get done => pending == 0;

  factory TimelineData.fromMap(Map<dynamic, dynamic> m) => TimelineData(
    total: (m['total'] as num?)?.toInt() ?? 0,
    pending: (m['pending'] as num?)?.toInt() ?? 0,
    byPerson: {
      for (final e in (m['people'] as List? ?? const []))
        (e['id'] as num).toInt(): PersonTimeline.fromMap(e as Map<dynamic, dynamic>),
    },
    together: {
      for (final e in (m['together'] as List? ?? const []))
        (e['id'] as num).toInt(): Companion(
          withId: (e['withId'] as num).toInt(),
          count: (e['count'] as num).toInt(),
          firstMonth: monthIndex(DateTime.fromMillisecondsSinceEpoch((e['firstMs'] as num).toInt())),
          firstUri: e['first'] is Map ? GroupMedia.fromMap(e['first'] as Map<dynamic, dynamic>).uri : null,
        ),
    },
    crowds: [for (final e in (m['crowds'] as List? ?? const [])) GroupMedia.fromMap(e as Map<dynamic, dynamic>)],
    reunions: [for (final e in (m['reunions'] as List? ?? const [])) GroupMedia.fromMap(e as Map<dynamic, dynamic>)],
  );
}

int monthIndex(DateTime t) => t.year * 12 + t.month - 1;

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String monthLabel(int month) => '${_monthNames[month % 12]} ${month ~/ 12}';

/// The kinds of moment the timeline points out on a person's line - all of them good news.
enum MilestoneKind { firstTogether, comeback, lovelyRun }

/// A moment worth a flag on someone's line. [short] fits a small chip, [long] a line of text.
class Milestone {
  const Milestone({
    required this.kind,
    required this.month,
    required this.short,
    required this.long,
    this.withId,
    this.importance = 0,
    this.uri,
  });

  final MilestoneKind kind;

  /// The photo or video it is about, when it is about one (the first photo together).
  final String? uri;

  /// For the first photo together: the other person.
  final int? withId;

  /// How much it matters (0 to 100): more shared photos, a longer run or a longer time away count for more.
  final int importance;

  /// The month it happened in (absolute).
  final int month;
  final String short, long;
}

/// The moments in one person's months: their first photo with the person they are photographed with
/// most, a return after a year or more away (when it carried on after), and - once they have
/// been quiet for a year - a look back at the run they had. Single photos far from the rest, which
/// are most likely a wrong date, never start or end anything.
List<Milestone> milestonesFor({
  required List<int> offsets,
  required List<int> counts,
  required int base,
  required int? firstMonth,
  required int? lastMonth,
  required int nowMonth,
  Companion? companion,
  String? companionName,
}) {
  final out = <Milestone>[];
  if (offsets.isEmpty || firstMonth == null || lastMonth == null) return out;
  final total = counts.fold<int>(0, (a, b) => a + b);

  // A return: a year or more with nothing, then photos that carry on (not one stray).
  final comebacks = <(int, int)>[]; // (months away, month it came back)
  var before = 0;
  for (var i = 0; i + 1 < offsets.length; i++) {
    before += counts[i];
    final back = base + offsets[i + 1];
    if (base + offsets[i] < firstMonth || back > lastMonth) continue;
    final away = offsets[i + 1] - offsets[i];
    if (away < 12 || before < 3) continue;
    final carriedOn = counts[i + 1] >= 2 || (i + 2 < offsets.length && offsets[i + 2] - offsets[i + 1] <= 3);
    if (carriedOn) comebacks.add((away, back));
  }
  comebacks.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (away, month) in comebacks.take(2)) {
    final text = away >= 24 ? '${(away / 12).round()} years' : '$away months';
    out.add(
      Milestone(
        kind: MilestoneKind.comeback,
        month: month,
        short: 'Back after $text',
        long: 'Welcome back! First photo in $text',
        importance: math.min(80, away * 2),
      ),
    );
  }

  // A look back at a run that has gone quiet.
  if (total >= 6 && nowMonth - lastMonth >= 12) {
    final run = lastMonth - firstMonth + 1;
    final text = run >= 24
        ? 'A lovely ${(run / 12).round()}-year run'
        : (run >= 12 ? 'A year of memories' : 'A short and sweet chapter');
    out.add(
      Milestone(
        kind: MilestoneKind.lovelyRun,
        month: lastMonth,
        short: text,
        long: text,
        importance: math.min(70, (run * 1.5).round()),
      ),
    );
  }

  // The first photo with the person they are photographed with most.
  if (companion != null && companion.count >= 3 && companion.firstMonth >= base && companion.firstMonth <= nowMonth) {
    out.add(
      Milestone(
        kind: MilestoneKind.firstTogether,
        month: companion.firstMonth,
        short: companionName == null ? 'First photo together' : 'First photo with $companionName',
        long: companionName == null ? 'First photo together' : 'First photo together with $companionName',
        withId: companion.withId,
        uri: companion.firstUri,
        importance: math.min(60, 20 + (math.log(companion.count) / math.ln2 * 8).round()),
      ),
    );
  }
  out.sort((a, b) => a.month.compareTo(b.month));
  return out;
}

/// The people whose moments are pointed out: the named ones, the best known first, up to [size] - the
/// inner circle. When hardly anybody is named yet the most photographed stand in, so there is still
/// something to find. With [everyone], all of them.
Set<int> momentCircle(List<Person> people, {required bool everyone, int size = 8}) {
  if (everyone) return {for (final p in people) p.id};
  int byPhotos(Person a, Person b) => b.photoCount.compareTo(a.photoCount);
  final named = people.where((p) => p.name != null).toList()..sort(byPhotos);
  final unnamed = people.where((p) => p.name == null).toList()..sort(byPhotos);
  final picked = <Person>[...named.take(size)];
  if (picked.length < 4) picked.addAll(unnamed.take(size - picked.length));
  return {for (final p in picked) p.id};
}

enum GroupKind { wholeGang, newFaces, reunion }

/// A moment of several people: the most of them in one shot in a year, a run of people who first
/// appeared in a year, or people back together after a long time. [people] are the faces to show.
class GroupMoment {
  const GroupMoment({
    required this.kind,
    required this.month,
    required this.people,
    required this.short,
    required this.long,
    required this.importance,
    this.photo,
  });

  final GroupKind kind;
  final int month;
  final List<Person> people;
  final String short, long;
  final int importance;

  /// A photo that shows it (the group shot, the reunion), when there is one.
  final PreviewPhoto? photo;
}

/// One line of the story: a moment of one person, a pair or a group, as the list of moments shows it.
class StoryEntry {
  const StoryEntry({
    required this.month,
    required this.importance,
    required this.people,
    required this.line,
    required this.icon,
    this.photo,
    this.uri,
  });

  final int month, importance;
  final List<Person> people;
  final String line;
  final IconData icon;
  final PreviewPhoto? photo;

  /// The photo or video it is about, when it is about one.
  final String? uri;
}

/// What to say about a photo or video that is one of the moments: the first photo of two people
/// together, the whole gang in one shot, a reunion. Shown on its tile and where it is opened.
class PhotoMoment {
  const PhotoMoment({
    required this.icon,
    required this.title,
    required this.people,
    required this.month,
    required this.importance,
  });

  final IconData icon;
  final String title;
  final List<Person> people;
  final int month, importance;

  /// "Aug 2022".
  String get when => monthLabel(month);

  /// The people who have a name, as "Anna, Dev and Mo" (null when none has).
  String? get names {
    final named = [
      for (final p in people)
        if (p.name != null) p.name!,
    ];
    if (named.isEmpty) return null;
    // A group shot lists a few of them (the people kept for it are the best known).
    if (people.length >= 4) return '${named.take(3).join(', ')} and others';
    if (named.length == 1) return named.first;
    return '${named.take(named.length - 1).join(', ')} and ${named.last}';
  }
}

/// One person's row, ready to draw on the shared axis.
class TimelineRowData {
  const TimelineRowData({
    required this.person,
    required this.offsets,
    required this.counts,
    required this.firstMonth,
    required this.lastMonth,
    required this.photoCount,
    required this.undated,
    this.milestones = const [],
  });

  final Person person;

  /// The moments worth a flag on this line, by month.
  final List<Milestone> milestones;

  /// Months with photos, as places on the axis (0 = its first month), and their counts.
  final List<int> offsets;
  final List<int> counts;

  /// First and last month that count (a lone far-off month is left out), or null with no dates.
  final int? firstMonth, lastMonth;

  /// Everything they are in (dated or not), and how many of it has no date.
  final int photoCount, undated;

  /// How many photos and videos they have in the month [offset] places along the axis.
  int countAt(int offset) {
    var lo = 0, hi = offsets.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] == offset) return counts[mid];
      if (offsets[mid] < offset) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return 0;
  }

  bool get hasDates => firstMonth != null;
  bool get single => firstMonth != null && firstMonth == lastMonth;
  int get maxCount => counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);

  /// "Since 2019" while they are still around, "2018 - 2021" once they have gone quiet, the
  /// month for someone who shows up in just one.
  String rangeLabel(int nowMonth) {
    final first = firstMonth, last = lastMonth;
    if (first == null || last == null) return 'No dates yet';
    if (first == last) return monthLabel(first);
    final fromYear = first ~/ 12, toYear = last ~/ 12;
    if (nowMonth - last <= 18) return 'Since $fromYear';
    return fromYear == toYear ? '$fromYear' : '$fromYear - $toYear';
  }
}

/// The shared axis and every row, worked out once per refresh.
class TimelineLayout {
  TimelineLayout({
    required this.startMonth,
    required this.endMonth,
    required this.rows,
    this.groups = const [],
  }) : density = _density(rows, endMonth - startMonth + 1);

  /// Moments of several people (the whole gang, new faces, a reunion).
  final List<GroupMoment> groups;

  /// The first month of the axis (always a January) and the last (this month).
  final int startMonth, endMonth;
  final List<TimelineRowData> rows;

  /// For each month of the axis, how much is going on across everyone (0 to 1), for the overview.
  final List<double> density;

  int get monthCount => endMonth - startMonth + 1;

  static final empty = TimelineLayout(startMonth: 0, endMonth: 0, rows: const []);

  late final Map<int, List<({TimelineRowData row, Milestone milestone})>> _momentsByMonth = _groupMoments();

  Map<int, List<({TimelineRowData row, Milestone milestone})>> _groupMoments() {
    final out = <int, List<({TimelineRowData row, Milestone milestone})>>{};
    for (final row in rows) {
      for (final m in row.milestones) {
        out.putIfAbsent(m.month, () => []).add((row: row, milestone: m));
      }
    }
    return out;
  }

  /// The months that have a moment in them, in order.
  late final List<int> momentMonths = (_momentsByMonth.keys.toList()..sort());

  /// The group moments in [month].
  List<GroupMoment> groupsIn(int month) => [
    for (final g in groups)
      if (g.month == month) g,
  ];

  /// The story: the moments of the people shown and of groups, year by year - the six that matter most
  /// of each year (they are in the order they happened).
  List<StoryEntry> story() {
    final all = <StoryEntry>[];
    final pairs = <String>{};
    for (final row in rows) {
      for (final m in row.milestones) {
        final other = m.withId;
        var people = [row.person];
        if (m.kind == MilestoneKind.firstTogether && other != null) {
          final a = row.person.id;
          if (!pairs.add(a < other ? '$a-$other' : '$other-$a')) continue;
          final friend = _rowOf(other)?.person;
          if (friend != null) people = [row.person, friend];
        }
        final both = people.length == 2;
        all.add(
          StoryEntry(
            month: m.month,
            importance: m.importance,
            people: people,
            uri: m.uri,
            line: both ? 'First photo together' : m.long,
            icon: switch (m.kind) {
              MilestoneKind.firstTogether => Icons.favorite_rounded,
              MilestoneKind.comeback => Icons.waving_hand_rounded,
              MilestoneKind.lovelyRun => Icons.auto_awesome_rounded,
            },
          ),
        );
      }
    }
    for (final g in groups) {
      all.add(
        StoryEntry(
          month: g.month,
          importance: g.importance,
          people: g.people,
          line: g.long,
          icon: groupIcon(g.kind),
          photo: g.photo,
          uri: g.photo?.uri,
        ),
      );
    }
    final byYear = <int, List<StoryEntry>>{};
    for (final e in all) {
      byYear.putIfAbsent(e.month ~/ 12, () => []).add(e);
    }
    final out = <StoryEntry>[];
    for (final list in byYear.values) {
      list.sort((a, b) => b.importance.compareTo(a.importance));
      out.addAll(list.take(6));
    }
    out.sort((a, b) => a.month.compareTo(b.month));
    return out;
  }

  /// The photos and videos that are moments of the story, by uri (the most important when a photo is
  /// two of them).
  Map<String, PhotoMoment> photoMoments() {
    final out = <String, PhotoMoment>{};
    for (final e in story()) {
      final uri = e.uri;
      if (uri == null || uri.isEmpty) continue;
      final old = out[uri];
      if (old != null && old.importance >= e.importance) continue;
      out[uri] = PhotoMoment(icon: e.icon, title: e.line, people: e.people, month: e.month, importance: e.importance);
    }
    return out;
  }

  TimelineRowData? _rowOf(int personId) {
    for (final row in rows) {
      if (row.person.id == personId) return row;
    }
    return null;
  }

  /// The moments in [month] (an absolute month), across everyone.
  List<({TimelineRowData row, Milestone milestone})> momentsIn(int month) => _momentsByMonth[month] ?? const [];

  /// How many people have something in the month [month] (an absolute month).
  int peopleIn(int month) {
    var n = 0;
    for (final row in rows) {
      if (row.countAt(month - startMonth) > 0) n++;
    }
    return n;
  }

  static List<double> _density(List<TimelineRowData> rows, int months) {
    if (months <= 0) return const [];
    final sums = List<double>.filled(months, 0);
    var most = 0.0;
    for (final row in rows) {
      for (var i = 0; i < row.offsets.length; i++) {
        final o = row.offsets[i];
        if (o < 0 || o >= months) continue;
        sums[o] += row.counts[i];
        if (sums[o] > most) most = sums[o];
      }
    }
    if (most == 0) return sums;
    return [for (final v in sums) math.sqrt(v / most)];
  }

  /// Lays out [people] (in the order given) with the months in [data]. [now] is today.
  factory TimelineLayout.build(List<Person> people, TimelineData data, DateTime now, {bool everyone = false}) {
    final end = monthIndex(now);

    // Every person's months, kept to those that can be real (not after today).
    final all = <int, int>{};
    for (final p in people) {
      final t = data.byPerson[p.id];
      if (t == null) continue;
      for (var i = 0; i < t.months.length; i++) {
        if (t.months[i] > end) continue;
        all[t.months[i]] = (all[t.months[i]] ?? 0) + t.counts[i];
      }
    }
    final start = _axisStart(all, end);

    final names = {for (final p in people) p.id: p.name};
    final circle = momentCircle(people, everyone: everyone);
    final rows = <TimelineRowData>[];
    for (final p in people) {
      final t = data.byPerson[p.id];
      final offsets = <int>[], counts = <int>[];
      if (t != null) {
        for (var i = 0; i < t.months.length; i++) {
          final m = t.months[i];
          if (m < start || m > end) continue;
          offsets.add(m - start);
          counts.add(t.counts[i]);
        }
      }
      // A single photo a long way from the rest is most likely a wrong date: it is drawn, but
      // left out of "since" and of the order.
      var lo = 0, hi = offsets.length - 1;
      while (lo < hi && counts[lo] == 1 && offsets[lo + 1] - offsets[lo] > 18) {
        lo++;
      }
      while (hi > lo && counts[hi] == 1 && offsets[hi] - offsets[hi - 1] > 18) {
        hi--;
      }
      final first = offsets.isEmpty ? null : start + offsets[lo];
      final last = offsets.isEmpty ? null : start + offsets[hi];
      final companion = data.together[p.id];
      rows.add(
        TimelineRowData(
          person: p,
          offsets: offsets,
          counts: counts,
          firstMonth: first,
          lastMonth: last,
          photoCount: p.photoCount,
          undated: t?.undated ?? 0,
          milestones: !circle.contains(p.id)
              ? const []
              : milestonesFor(
            offsets: offsets,
            counts: counts,
            base: start,
            firstMonth: first,
            lastMonth: last,
            nowMonth: end,
            companion: companion,
            companionName: companion == null ? null : names[companion.withId],
          ),
        ),
      );
    }
    return TimelineLayout(
      startMonth: start,
      endMonth: end,
      rows: rows,
      groups: _buildGroupMoments(people, rows, data, start, end),
    );
  }

  // The axis begins where the library really begins: the first month that has company (at least
  // ten photos in the two years from it), so one photo with a wrong date cannot stretch it.
  static int _axisStart(Map<int, int> all, int end) {
    if (all.isEmpty) return (end ~/ 12) * 12;
    final months = all.keys.toList()..sort();
    var chosen = months.first;
    var total = 0;
    for (final c in all.values) {
      total += c;
    }
    if (total >= 10) {
      for (final m in months) {
        var inWindow = 0;
        for (final other in months) {
          if (other >= m && other < m + 24) inWindow += all[other]!;
          if (other >= m + 24) break;
        }
        if (inWindow >= 10) {
          chosen = m;
          break;
        }
      }
    }
    return (chosen ~/ 12) * 12;
  }
}

/// One photo or video shown on the timeline: on the filmstrip, or as a person's picture for the
/// month under the playhead.
class PreviewPhoto {
  const PreviewPhoto({
    required this.key,
    required this.uri,
    required this.isVideo,
    required this.tsMs,
    required this.takenMs,
    this.personId = 0,
  });

  final int key;
  final String uri;
  final bool isVideo;

  /// Where in a video the picture is taken from (0 for a photo).
  final int tsMs;

  /// When it was taken.
  final int takenMs;

  /// The person it was chosen for (0 on the filmstrip).
  final int personId;

  /// Identifies the picture (a video's frame is its own picture).
  String get cacheKey => isVideo ? '$uri@$tsMs' : uri;

  DateTime get taken => DateTime.fromMillisecondsSinceEpoch(takenMs);
  int get month => monthIndex(taken);

  factory PreviewPhoto.fromMap(Map<dynamic, dynamic> m) => PreviewPhoto(
    key: (m['key'] as num).toInt(),
    uri: m['uri'] as String,
    isVideo: m['isVideo'] as bool? ?? false,
    tsMs: (m['tsMs'] as num?)?.toInt() ?? 0,
    takenMs: (m['takenMs'] as num?)?.toInt() ?? 0,
    personId: (m['personId'] as num?)?.toInt() ?? 0,
  );
}

IconData groupIcon(GroupKind kind) {
  switch (kind) {
    case GroupKind.wholeGang:
      return Icons.groups_rounded;
    case GroupKind.newFaces:
      return Icons.person_add_alt_1_rounded;
    case GroupKind.reunion:
      return Icons.celebration_rounded;
  }
}

// The moments of several people. Only people on the timeline count (known ones), so a group shot of
// five faces that are not people yet is not a "whole gang".
List<GroupMoment> _buildGroupMoments(
  List<Person> people,
  List<TimelineRowData> rows,
  TimelineData data,
  int start,
  int end,
) {
  final byId = {for (final p in people) p.id: p};
  final out = <GroupMoment>[];

  List<Person> known(List<int> ids) => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];

  String apart(int days) {
    final months = (days / 30.4).round();
    return months >= 24 ? '${(months / 12).round()} years' : '$months months';
  }

  // The whole gang: each year's shot with the most known people (four or more).
  final bestOfYear = <int, GroupMedia>{};
  final bestCount = <int, int>{};
  for (final c in data.crowds) {
    final month = c.month;
    if (month < start || month > end) continue;
    final n = known(c.people).length;
    final year = month ~/ 12;
    if (n >= 4 && (n > (bestCount[year] ?? 0))) {
      bestOfYear[year] = c;
      bestCount[year] = n;
    }
  }
  for (final e in bestOfYear.entries) {
    final c = e.value;
    final faces = known(c.people)..sort((a, b) => b.photoCount.compareTo(a.photoCount));
    final n = faces.length;
    out.add(
      GroupMoment(
        kind: GroupKind.wholeGang,
        month: c.month,
        people: faces.take(4).toList(),
        short: 'The whole gang',
        long: 'The whole gang: $n people in one photo',
        importance: 40 + 8 * math.min(n, 10),
        photo: c.photo,
      ),
    );
  }

  // Reunions: three or more known people together again after a year or more.
  for (final r in data.reunions) {
    final month = r.month;
    if (month < start || month > end) continue;
    final faces = known(r.people);
    if (faces.length < 3) continue;
    faces.sort((a, b) => b.photoCount.compareTo(a.photoCount));
    out.add(
      GroupMoment(
        kind: GroupKind.reunion,
        month: month,
        people: faces.take(4).toList(),
        short: 'Reunion after ${apart(r.gapDays)}',
        long: 'A reunion: ${faces.length} of you together again after ${apart(r.gapDays)}',
        importance: 50 + 6 * math.min<int>(faces.length, 10) + math.min<int>(36, (r.gapDays / 30.4).round()) ~/ 2,
        photo: r.photo,
      ),
    );
  }

  // New faces: three or more people who first appear in the same year (not the first year of the
  // library, when everyone is new).
  final firstYear = start ~/ 12;
  final arrivals = <int, List<TimelineRowData>>{};
  for (final row in rows) {
    final first = row.firstMonth;
    if (first == null || row.photoCount < 4) continue;
    final year = first ~/ 12;
    if (year > firstYear) arrivals.putIfAbsent(year, () => []).add(row);
  }
  for (final e in arrivals.entries) {
    if (e.value.length < 3) continue;
    final months = [for (final r in e.value) r.firstMonth!]..sort();
    final month = months[months.length ~/ 2];
    final faces = [for (final r in e.value) r.person]..sort((a, b) => b.photoCount.compareTo(a.photoCount));
    out.add(
      GroupMoment(
        kind: GroupKind.newFaces,
        month: month,
        people: faces.take(4).toList(),
        short: '${faces.length} new faces',
        long: '${faces.length} new faces in ${e.key}',
        importance: 30 + 6 * math.min(faces.length, 10),
      ),
    );
  }
  out.sort((a, b) => a.month.compareTo(b.month));
  return out;
}
