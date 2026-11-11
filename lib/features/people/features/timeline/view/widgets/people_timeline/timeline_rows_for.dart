part of '../people_timeline.dart';

/// For the People tab: the people in [shown] (a search applied to everyone listed, so the axis does
/// not change with it) as rows, in the order [sort] gives.
List<TimelineRowData> timelineRowsFor(
  TimelineLayout layout,
  List<Person> shown,
  TimelineSort sort, {
  required bool datesDone,
}) {
  final ids = {for (final p in shown) p.id};
  return sortTimelineRows(
    [
      for (final row in layout.rows)
        if (ids.contains(row.person.id)) row,
    ],
    sort,
    datesDone: datesDone,
  );
}

List<TimelineRowData> sortTimelineRows(List<TimelineRowData> rows, TimelineSort sort, {required bool datesDone}) {
  final list = [...rows];
  int byPhotos(TimelineRowData a, TimelineRowData b) => b.photoCount.compareTo(a.photoCount);
  // Until every date is in, the order would keep changing under the finger: most photos first.
  if (!datesDone && (sort == TimelineSort.earliest || sort == TimelineSort.recent)) {
    return list..sort(byPhotos);
  }
  switch (sort) {
    case TimelineSort.earliest:
      list.sort((a, b) {
        if (a.hasDates != b.hasDates) return a.hasDates ? -1 : 1;
        if (!a.hasDates) return byPhotos(a, b);
        final c = a.firstMonth!.compareTo(b.firstMonth!);
        return c != 0 ? c : byPhotos(a, b);
      });
    case TimelineSort.recent:
      list.sort((a, b) {
        if (a.hasDates != b.hasDates) return a.hasDates ? -1 : 1;
        if (!a.hasDates) return byPhotos(a, b);
        final c = b.lastMonth!.compareTo(a.lastMonth!);
        return c != 0 ? c : byPhotos(a, b);
      });
    case TimelineSort.mostPhotos:
      list.sort(byPhotos);
    case TimelineSort.az:
      list.sort((a, b) {
        final an = a.person.name?.toLowerCase(), bn = b.person.name?.toLowerCase();
        if ((an == null) != (bn == null)) return an == null ? 1 : -1;
        if (an == null) return byPhotos(a, b);
        return an.compareTo(bn!);
      });
  }
  return list;
}
