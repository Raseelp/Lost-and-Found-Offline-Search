part of '../people_timeline.dart';

/// Pinned at the top of the list: the overview of all the years, and under it the ruler, with the
/// month under the playhead named at the left.
class TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  TimelineHeaderDelegate({required this.layout, required this.window, this.compact = false});

  final TimelineLayout layout;
  final TimelineWindow window;

  /// The collapsed list has a wider column of names.
  final bool compact;

  static const double _overview = 20;
  static const double _ruler = 30;
  static const double _height = 6 + _overview + 4 + _ruler + 2;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: overlapsContent ? AppColors.hairline : AppColors.transparent)),
      ),
      padding: const EdgeInsets.fromLTRB(_pad, 6, _pad, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: _columnWidth(compact),
            height: _overview + 4 + _ruler,
            child: ValueListenableBuilder<int>(
              valueListenable: window.centre,
              builder: (context, month, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      monthLabel(month),
                      maxLines: 1,
                      style: textTheme.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    () {
                      final n = layout.peopleIn(month);
                      return n == 1 ? '1 person' : '$n people';
                    }(),
                    maxLines: 1,
                    style: textTheme.labelSmall?.copyWith(color: AppColors.ink48, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _columnGap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  window.configure(
                    width: width,
                    minMonth: layout.startMonth.toDouble(),
                    maxMonth: layout.endMonth + 1.0,
                  );
                });
                return Column(
                  children: [
                    SizedBox(
                      height: _overview,
                      width: width,
                      child: _Overview(layout: layout, window: window),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: _ruler,
                      width: width,
                      child: CustomPaint(
                        painter: _RulerPainter(
                          window: window,
                          style: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                            color: AppColors.ink48,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant TimelineHeaderDelegate old) =>
      !identical(old.layout, layout) || !identical(old.window, window) || old.compact != compact;
}

double _columnWidth(bool compact) => compact ? _compactColumn : _leftColumn;

/// All the years in one thin strip, with a window on the stretch that is on screen. Dragging it
/// (or tapping) moves the view there.
class _Overview extends StatelessWidget {
  const _Overview({required this.layout, required this.window});

  final TimelineLayout layout;
  final TimelineWindow window;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double monthAt(double dx) => layout.startMonth + dx / width * layout.monthCount;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => window.centreOn(monthAt(d.localPosition.dx), animate: true),
          onHorizontalDragStart: (d) {
            window.holdStart();
            window.centreOn(monthAt(d.localPosition.dx));
          },
          onHorizontalDragUpdate: (d) => window.centreOn(monthAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => window.holdEnd(),
          onHorizontalDragCancel: window.holdEnd,
          child: CustomPaint(painter: _OverviewPainter(layout: layout, window: window)),
        );
      },
    );
  }
}
