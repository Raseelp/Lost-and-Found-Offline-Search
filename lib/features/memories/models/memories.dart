import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "May 3".
String dayLabel(int month, int day) =>
    '${_monthNames[(month - 1).clamp(0, 11)]} $day';

/// "1 year ago", "3 years ago".
String yearsAgoLabel(int years) =>
    years == 1 ? '1 year ago' : '$years years ago';

/// A photo or video of a memory, and who is in it (only named people, only where their face is clear).
class MemoryPhoto {
  const MemoryPhoto({
    required this.key,
    required this.uri,
    required this.isVideo,
    required this.tsMs,
    required this.takenMs,
    this.names = const [],
  });

  final int key;
  final String uri;
  final bool isVideo;
  final int tsMs, takenMs;
  final List<String> names;

  /// What the timeline's picture loader and viewers know it as.
  PreviewPhoto get preview => PreviewPhoto(
    key: key,
    uri: uri,
    isVideo: isVideo,
    tsMs: tsMs,
    takenMs: takenMs,
  );

  DateTime get taken => DateTime.fromMillisecondsSinceEpoch(takenMs);

  factory MemoryPhoto.fromMap(Map<dynamic, dynamic> m) => MemoryPhoto(
    key: (m['key'] as num).toInt(),
    uri: m['uri'] as String? ?? '',
    isVideo: m['isVideo'] as bool? ?? false,
    tsMs: (m['tsMs'] as num?)?.toInt() ?? 0,
    takenMs: (m['takenMs'] as num?)?.toInt() ?? 0,
    names: [for (final n in (m['names'] as List? ?? const [])) n as String],
  );
}

/// What one past year has for a date: how many photos and videos, and the few that stand for it.
class MemoryYear {
  const MemoryYear({
    required this.year,
    required this.yearsAgo,
    required this.total,
    required this.photos,
    required this.names,
    required this.strength,
  });

  final int year, yearsAgo, total;
  final List<MemoryPhoto> photos;

  /// The named people in it, seen most often first.
  final List<String> names;
  final double strength;

  factory MemoryYear.fromMap(Map<dynamic, dynamic> m) => MemoryYear(
    year: (m['year'] as num).toInt(),
    yearsAgo: (m['yearsAgo'] as num).toInt(),
    total: (m['total'] as num).toInt(),
    photos: [
      for (final p in (m['photos'] as List? ?? const []))
        MemoryPhoto.fromMap(p as Map<dynamic, dynamic>),
    ],
    names: [for (final n in (m['names'] as List? ?? const [])) n as String],
    strength: (m['strength'] as num?)?.toDouble() ?? 0,
  );
}

/// Two named people's first photo together, on its anniversary.
class MemoryAnniversary {
  const MemoryAnniversary({
    required this.yearsAgo,
    required this.ids,
    required this.names,
    required this.firstMs,
    this.photo,
  });

  final int yearsAgo;
  final List<int> ids;
  final List<String> names;
  final int firstMs;
  final MemoryPhoto? photo;

  /// "Anna and Dev".
  String get who => names.length <= 1
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  factory MemoryAnniversary.fromMap(Map<dynamic, dynamic> m) =>
      MemoryAnniversary(
        yearsAgo: (m['yearsAgo'] as num).toInt(),
        ids: [
          for (final i in (m['ids'] as List? ?? const [])) (i as num).toInt(),
        ],
        names: [for (final n in (m['names'] as List? ?? const [])) n as String],
        firstMs: (m['firstMs'] as num?)?.toInt() ?? 0,
        photo: m['photo'] is Map
            ? MemoryPhoto.fromMap(m['photo'] as Map<dynamic, dynamic>)
            : null,
      );
}

/// This date in the past years of the library.
class OnThisDay {
  const OnThisDay({
    required this.month,
    required this.day,
    required this.year,
    required this.exact,
    required this.week,
    required this.anniversaries,
  });

  static const empty = OnThisDay(
    month: 1,
    day: 1,
    year: 0,
    exact: [],
    week: [],
    anniversaries: [],
  );

  final int month, day, year;

  /// The same date in past years, most recent first.
  final List<MemoryYear> exact;

  /// The week round the date, only when the date itself has nothing.
  final List<MemoryYear> week;
  final List<MemoryAnniversary> anniversaries;

  bool get isEmpty => exact.isEmpty && week.isEmpty && anniversaries.isEmpty;

  /// What is shown for the date: its own years, else the week round it.
  List<MemoryYear> get years => exact.isNotEmpty ? exact : week;

  String get dateLabel => dayLabel(month, day);

  /// How many photos and videos, over the years shown.
  int get total => years.fold(0, (sum, y) => sum + y.total);

  /// The photos that best stand for the day, one from each of the strongest years (for the card). When there are
  /// fewer years than [count], the strongest year adds its next photos.
  List<MemoryPhoto> coverPhotos({int count = 3}) {
    final ranked = [...years]..sort((a, b) => b.strength.compareTo(a.strength));
    final out = <MemoryPhoto>[];
    for (final y in ranked) {
      if (y.photos.isEmpty) continue;
      out.add(y.photos.first);
      if (out.length >= count) break;
    }
    if (out.length < count && ranked.isNotEmpty) {
      for (final p in ranked.first.photos.skip(1)) {
        if (out.length >= count) break;
        out.add(p);
      }
    }
    return out;
  }

  factory OnThisDay.fromMap(Map<dynamic, dynamic> m) => OnThisDay(
    month: (m['month'] as num).toInt(),
    day: (m['day'] as num).toInt(),
    year: (m['year'] as num).toInt(),
    exact: [
      for (final y in (m['exact'] as List? ?? const []))
        MemoryYear.fromMap(y as Map<dynamic, dynamic>),
    ],
    week: [
      for (final y in (m['week'] as List? ?? const []))
        MemoryYear.fromMap(y as Map<dynamic, dynamic>),
    ],
    anniversaries: [
      for (final a in (m['anniversaries'] as List? ?? const []))
        MemoryAnniversary.fromMap(a as Map<dynamic, dynamic>),
    ],
  );
}

/// One side of "then and now": the photo, and where to frame (0..1 fractions of it). The frame is the person's face,
/// or both faces when the picture is of the two of them.
class ThenNowSide {
  const ThenNowSide({
    required this.key,
    required this.uri,
    required this.faceId,
    required this.takenMs,
    required this.boxL,
    required this.boxT,
    required this.boxR,
    required this.boxB,
    required this.photoW,
    required this.photoH,
    this.margin = 3.1,
    this.lift = 0.55,
    this.faces = 1,
    this.kind = 'solo',
    this.withName,
  });

  final int key, faceId, takenMs, photoW, photoH;
  final String uri;
  final double boxL, boxT, boxR, boxB;

  /// How much room to leave round the box, and how far down from its middle to centre the picture.
  final double margin, lift;

  /// How many clear faces there are in the photo.
  final int faces;

  /// 'solo' (on their own), 'duo' (with one other person), 'group' or 'crowd'; and who the other person is.
  final String kind;
  final String? withName;

  /// Who is in the picture, in a few words (null when there is nothing worth saying).
  String? get company => switch (kind) {
    'solo' => 'On their own',
    'duo' when withName != null => 'With $withName',
    'group' => 'In a group',
    _ => null,
  };

  DateTime get taken => DateTime.fromMillisecondsSinceEpoch(takenMs);

  /// What identifies the picture made from it.
  String get cropKey => '$uri|$faceId|$boxL|$boxT|$boxR|$boxB|$margin';

  factory ThenNowSide.fromMap(Map<dynamic, dynamic> m) => ThenNowSide(
    key: (m['key'] as num).toInt(),
    uri: m['uri'] as String,
    faceId: (m['faceId'] as num).toInt(),
    takenMs: (m['takenMs'] as num).toInt(),
    boxL: (m['boxL'] as num).toDouble(),
    boxT: (m['boxT'] as num).toDouble(),
    boxR: (m['boxR'] as num).toDouble(),
    boxB: (m['boxB'] as num).toDouble(),
    photoW: (m['photoW'] as num).toInt(),
    photoH: (m['photoH'] as num).toInt(),
    margin: (m['margin'] as num?)?.toDouble() ?? 3.1,
    lift: (m['lift'] as num?)?.toDouble() ?? 0.55,
    faces: (m['faces'] as num?)?.toInt() ?? 1,
    kind: m['kind'] as String? ?? 'solo',
    withName: m['withName'] as String?,
  );
}

/// A person's start next to their latest: every photo from about the first couple of months and from about the
/// latest couple (not the very first and last), oldest first, a burst counting once. The one shown first at
/// each end is one of its best few (on their own, with another person, in a small group), random but the same
/// all day.
class ThenNow {
  const ThenNow({
    required this.thenOptions,
    required this.nowOptions,
    required this.startThen,
    required this.startNow,
    required this.spanMonths,
    required this.lastMonth,
  });

  final List<ThenNowSide> thenOptions, nowOptions;
  final int startThen, startNow;

  /// Months from their first to their latest (as far as the photos tell).
  final int spanMonths;

  /// Their latest month (year * 12 + 0-based month).
  final int lastMonth;

  ThenNowSide get then =>
      thenOptions[startThen.clamp(0, thenOptions.length - 1)];
  ThenNowSide get now => nowOptions[startNow.clamp(0, nowOptions.length - 1)];

  /// "8 years", "1 year 4 months", "11 months".
  String get spanLabel {
    final years = spanMonths ~/ 12, months = spanMonths % 12;
    if (years == 0) return months == 1 ? '1 month' : '$months months';
    final y = years == 1 ? '1 year' : '$years years';
    if (months == 0 || years >= 5) return y;
    return '$y ${months == 1 ? '1 month' : '$months months'}';
  }

  /// Whether the second photos are from about the present day (else they are the latest there are, which is some time
  /// ago).
  bool isNow(DateTime today) =>
      (today.year * 12 + today.month - 1) - lastMonth <= 18;

  factory ThenNow.fromMap(Map<dynamic, dynamic> m) => ThenNow(
    thenOptions: [
      for (final s in (m['then'] as List))
        ThenNowSide.fromMap(s as Map<dynamic, dynamic>),
    ],
    nowOptions: [
      for (final s in (m['now'] as List))
        ThenNowSide.fromMap(s as Map<dynamic, dynamic>),
    ],
    startThen: (m['startThen'] as num?)?.toInt() ?? 0,
    startNow: (m['startNow'] as num?)?.toInt() ?? 0,
    spanMonths: (m['spanMonths'] as num).toInt(),
    lastMonth: (m['lastMonth'] as num).toInt(),
  );
}

/// What the person chose about the daily memory (it comes twice a day, at fixed times: early morning and evening).
class MemorySettings {
  const MemorySettings({this.enabled = true, this.allowed = true});

  final bool enabled;

  /// Whether the system lets the app show notifications at all.
  final bool allowed;

  MemorySettings copyWith({bool? enabled, bool? allowed}) => MemorySettings(
    enabled: enabled ?? this.enabled,
    allowed: allowed ?? this.allowed,
  );

  factory MemorySettings.fromMap(Map<dynamic, dynamic> m) => MemorySettings(
    enabled: m['enabled'] as bool? ?? true,
    allowed: m['allowed'] as bool? ?? true,
  );
}

/// The days a [MemoryYear] stands for, for [DayPhotosScreen]: its date (a week round it when the date itself has
/// nothing in any year), and what to call it.
({DateTime from, int days, String title}) dayOf(
  MemoryYear year,
  OnThisDay today,
) {
  final date = DateTime(year.year, today.month, today.day);
  if (today.exact.isNotEmpty) {
    return (
      from: date,
      days: 1,
      title: '${dayLabel(date.month, date.day)}, ${date.year}',
    );
  }
  return (
    from: DateTime(date.year, date.month, date.day - 3),
    days: 7,
    title: 'Around ${dayLabel(date.month, date.day)}, ${date.year}',
  );
}
