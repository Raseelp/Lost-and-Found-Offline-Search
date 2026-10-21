import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/month_photos_screen.dart';
import 'package:lost_and_found/view/person_screen.dart';
import 'package:lost_and_found/view/widget/app_search_field.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/moments_sheet.dart';
import 'package:lost_and_found/view/widget/people_timeline.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The People timeline on a screen of its own, with the whole height for the years: a slim bar at
/// the top (back, search, order, collapse) and then the timeline. See people_timeline.dart for
/// how the timeline itself works.
class PeopleTimelineScreen extends StatefulWidget {
  const PeopleTimelineScreen({super.key});

  @override
  State<PeopleTimelineScreen> createState() => _PeopleTimelineScreenState();
}

class _PeopleTimelineScreenState extends State<PeopleTimelineScreen> with TickerProviderStateMixin {
  static const _compactKey = 'faces_timeline_compact';

  final FacesController _faces = Get.find<FacesController>();
  late final TimelineWindow _window = TimelineWindow(this);
  final TimelineMemory _memory = TimelineMemory();
  late final TimelinePreview _preview = TimelinePreview(window: _window);
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searching = false;

  // Whether there are moments to go to (the button for them is in the top bar, which is built
  // apart from the list).
  bool _hasMoments = false;

  // Collapsed to names and thin lines (the choice is kept).
  bool _compact = false;

  TimelineSort _sort = TimelineSort.earliest;

  TimelineLayout _layout = TimelineLayout.empty;
  Object? _layoutPeople, _layoutData;
  int _layoutMonth = -1;
  bool _layoutEveryone = false;

  @override
  void initState() {
    super.initState();
    // Dates are looked up while this screen is open (and for new people and photos arriving).
    _faces.timelineWanted = true;
    unawaited(_faces.loadTimeline());
    _loadCompact();
    _window.jumps.addListener(_toTop);
  }

  // A jump to a month (a flag, the moments button) brings the list back to the top, where the
  // preview opens out at the month it went to.
  void _toTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _faces.timelineWanted = false;
    _window.jumps.removeListener(_toTop);
    _scroll.dispose();
    _preview.dispose();
    _window.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCompact() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final compact = prefs.getBool(_compactKey) ?? false;
      if (mounted && compact != _compact) setState(() => _compact = compact);
    } catch (_) {
      // The expanded list, as ever.
    }
  }

  Future<void> _setCompact(bool on) async {
    setState(() => _compact = on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_compactKey, on);
    } catch (_) {
      // Kept for this visit at least.
    }
  }

  // The story: the good moments year by year. Tapping one goes there.
  void _openStory() {
    final faces = _faces;
    HapticFeedback.selectionClick();
    showMomentsSheet(
      context,
      everyone: faces.momentsEveryone,
      layoutFor: (everyone) => everyone == _layoutEveryone
          ? _layout
          : TimelineLayout.build(faces.people, faces.timeline, DateTime.now(), everyone: everyone),
      onEveryoneChanged: (value) {
        // Kept by the controller: the photos' moments follow the same choice.
        faces.setMomentsEveryone(value);
        if (mounted) setState(() {});
      },
      onJump: _window.jumpToMonth,
    );
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _search.clear();
    setState(() => _searching = false);
  }

  // The axis and rows are worked out again only when the people, their months or the month change.
  TimelineLayout _layoutFor(FacesController faces) {
    final now = DateTime.now();
    final month = monthIndex(now);
    if (!identical(_layoutPeople, faces.people) ||
        !identical(_layoutData, faces.timeline) ||
        _layoutMonth != month ||
        _layoutEveryone != faces.momentsEveryone) {
      _layout = TimelineLayout.build(faces.people, faces.timeline, now, everyone: faces.momentsEveryone);
      _layoutEveryone = faces.momentsEveryone;
      _layoutPeople = faces.people;
      _layoutData = faces.timeline;
      _layoutMonth = month;
    }
    return _layout;
  }

  void _pickSort() {
    showFacesSheet<void>(
      context,
      title: 'Order the timeline',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < TimelineSort.values.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.dividerSoft),
            SheetRow(
              icon: switch (TimelineSort.values[i]) {
                TimelineSort.earliest => Icons.hourglass_top_rounded,
                TimelineSort.recent => Icons.update_rounded,
                TimelineSort.mostPhotos => Icons.photo_library_outlined,
                TimelineSort.az => Icons.sort_by_alpha_rounded,
              },
              label: timelineSortLabel(TimelineSort.values[i]),
              trailing: _sort == TimelineSort.values[i]
                  ? const Icon(Icons.check_rounded, size: 20, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sort = TimelineSort.values[i]);
                Navigator.of(sheet).pop();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.ink),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: _searching
                    ? AppSearchField(
                        key: const ValueKey('search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        hint: 'Search people',
                        onChanged: (_) => setState(() {}),
                      )
                    : Text(
                        'Timeline',
                        key: const ValueKey('title'),
                        style: textTheme.titleLarge,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (_searching)
              _BarButton(icon: Icons.close_rounded, tooltip: 'Close search', onTap: _closeSearch)
            else ...[
              if (_hasMoments)
                _BarButton(icon: Icons.auto_awesome_rounded, tooltip: 'Your story', onTap: _openStory),
              _BarButton(icon: Icons.search_rounded, tooltip: 'Search people', onTap: _openSearch),
              _BarButton(
                icon: Icons.swap_vert_rounded,
                tooltip: 'Order the timeline',
                active: _sort != TimelineSort.earliest,
                onTap: _pickSort,
              ),
              _BarButton(
                icon: _compact ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                tooltip: _compact ? 'Show faces and details' : 'Collapse the list',
                active: _compact,
                onTap: () => _setCompact(!_compact),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      // Back first puts the search away, then leaves.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(context),
              Expanded(
                child: GetBuilder<FacesController>(
                  builder: (faces) {
                    final now = DateTime.now();
                    final layout = _layoutFor(faces);
                    final hasMoments = layout.momentMonths.isNotEmpty || layout.groups.isNotEmpty;
                    if (hasMoments != _hasMoments) {
                      _hasMoments = hasMoments;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                    }
                    final query = _search.text.trim().toLowerCase();
                    final rows = timelineRowsFor(
                      layout,
                      query.isEmpty
                          ? faces.people
                          : [
                              for (final p in faces.people)
                                if ((p.name ?? '').toLowerCase().contains(query)) p,
                            ],
                      _sort,
                      datesDone: faces.timelineDone,
                    );

                    // The photos need to know the axis and when the dates change (then they are chosen again).
                    _preview.update(layout, dataVersion: faces.timeline, datesDone: faces.timelineDone);

                    final slivers = <Widget>[
                      // The photos at the playhead: the first part of the list, collapsing as it scrolls
                      // (and out of the way while searching, with the keyboard up).
                      if (!_searching)
                        TimelineLens(
                          preview: _preview,
                          window: _window,
                          onOpenMonth: (month, photo) => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MonthPhotosScreen(month: month, focusKey: photo.key)),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                          child: TimelineIntro(layout: layout, data: faces.timeline, finished: faces.timelineDone, now: now),
                        ),
                      ),
                      // The zoom buttons (All, 5 years, 1 year, 3 months) are switched off: the
                      // timeline zooms with a pinch. To bring them back, add:
                      //   SliverToBoxAdapter(
                      //     child: Padding(
                      //       padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                      //       child: TimelineZoomBar(window: _window),
                      //     ),
                      //   ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: TimelineHeaderDelegate(layout: layout, window: _window, compact: _compact),
                      ),
                      if (rows.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxl),
                            child: Text(
                              query.isEmpty ? 'No one to show yet.' : 'No one is called "${_search.text.trim()}".',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final row = rows[i];
                            return TimelineRow(
                              key: ValueKey(row.person.id),
                              row: row,
                              layout: layout,
                              window: _window,
                              compact: _compact,
                              preview: _preview,
                              now: now,
                              datesDone: faces.timelineDone,
                              memory: _memory,
                              index: i,
                              // No long-press menu here: that is for the grid.
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PersonScreen(person: row.person)),
                              ),
                            );
                          }, childCount: rows.length),
                        ),
                      if (rows.any((r) => r.hasDates)) const SliverToBoxAdapter(child: TimelineFooter()),
                      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.xxl)),
                    ];

                    // While two fingers pinch the timeline, the list stands still under them.
                    // Scrolling the list up or down makes the preview shrink out of its way.
                    return NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
                        // The person scrolling the list (not the list adjusting to the preview growing).
                        if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
                          _preview.userScrolling();
                        }
                        if (n is ScrollUpdateNotification || n is ScrollStartNotification || n is ScrollEndNotification) {
                          _preview.setListOffset(n.metrics.pixels);
                        }
                        return false;
                      },
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _window.pinching,
                        builder: (context, pinching, _) => CustomScrollView(
                          controller: _scroll,
                          physics: pinching ? const NeverScrollableScrollPhysics() : null,
                          slivers: slivers,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round icon button for the slim bar at the top.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Filled, to show a choice that is on (the collapsed list, another order).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.primary : AppColors.transparent,
            ),
            child: Icon(icon, size: 22, color: active ? AppColors.onPrimary : AppColors.ink),
          ),
        ),
      ),
    );
  }
}
