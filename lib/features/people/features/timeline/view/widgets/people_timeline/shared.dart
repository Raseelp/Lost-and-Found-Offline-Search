part of '../people_timeline.dart';

/// The People tab's timeline, built like the timeline of a video editor: a column of faces on the
/// left that stays put, and the years sliding by beside it. Drag to move through the years (it
/// carries on a little when let go), pinch to zoom from the whole library down to single months,
/// or jump with the zoom buttons. A line in the middle is the playhead: whoever has photos in the
/// month under it lights up, everyone else dims. A thin overview of all the years sits at the top
/// with a window showing where you are; drag it to jump.
const double _pad = AppSpacing.base;

const double _leftColumn = 64;

/// The column of names when the list is collapsed (no faces, so the names get more room).
const double _compactColumn = 92;

const double _columnGap = AppSpacing.md;

/// How an AnimatedSwitcher stacks its pictures, without ever having two children with the same key. The default can:
/// when what it shows goes A, B, A before the first A has faded out (a caption changing quickly as the playhead
/// crosses months), both A are in the stack and Flutter complains. Here the older one is dropped.
AnimatedSwitcherLayoutBuilder switcherStack({
  AlignmentGeometry alignment = Alignment.center,
  StackFit fit = StackFit.loose,
}) {
  return (Widget? current, List<Widget> previous) {
    final seen = <Key?>{if (current != null) current.key};
    final kept = <Widget>[];
    for (final w in previous.reversed) {
      if (w.key != null && !seen.add(w.key)) continue;
      kept.add(w);
    }
    return Stack(alignment: alignment, fit: fit, children: [...kept.reversed, if (current != null) current]);
  };
}

/// Under the list: where the dates come from.
class TimelineFooter extends StatelessWidget {
  const TimelineFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, AppSpacing.xl, _pad, 0),
      child: Text(
        'Dates are when each photo or video was taken.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
      ),
    );
  }
}

/// The people for the timeline, after the search and in the order chosen.
enum TimelineSort { earliest, recent, mostPhotos, az }

String timelineSortLabel(TimelineSort sort) {
  switch (sort) {
    case TimelineSort.earliest:
      return 'Earliest first';
    case TimelineSort.recent:
      return 'Seen most recently';
    case TimelineSort.mostPhotos:
      return 'Most photos';
    case TimelineSort.az:
      return 'A to Z';
  }
}
