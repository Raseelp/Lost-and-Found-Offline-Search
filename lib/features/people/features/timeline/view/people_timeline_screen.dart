import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/people/features/timeline/models/people_timeline.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/people/features/timeline/view/month_photos_screen.dart';
import 'package:lost_and_found/features/people/view/person_screen.dart';
import 'package:lost_and_found/core/widgets/app_search_field.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/moments_sheet.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/people_timeline.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_preview.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/timeline_tip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The People timeline on a screen of its own, with the whole height for the years. It has a slim bar at the top with
/// back and one button that slides out the rest (story, search, order, collapse and about), and then the timeline. See
/// people_timeline.dart for how the timeline itself works.
class PeopleTimelineScreen extends StatefulWidget {
  const PeopleTimelineScreen({super.key});

  @override
  State<PeopleTimelineScreen> createState() => _PeopleTimelineScreenState();
}

/// Dates are looked up while the screen is open and for people and photos that arrive. Back first puts the search
/// away, then leaves.
/// The photos at the playhead are the first part of the list, collapsing as it scrolls and out of the way while
/// searching with the keyboard up. A row has no long-press menu, that is for the grid. The zoom buttons are hidden
/// because the timeline zooms with a pinch, during which the list stands still. The preview shrinks out of the way
/// only when the person scrolls, not when the list adjusts to the preview growing.
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

  /// Whether there are moments to go to. The button for them is in the top bar, which is built apart from the list.
  bool _hasMoments = false;

  /// Collapsed to names and thin lines. The choice is kept.
  bool _compact = false;

  TimelineSort _sort = TimelineSort.earliest;

  /// The slide-out row of the bar's actions. It is open when the button at the right end was tapped, and anything
  /// else tapped on the screen closes it.
  late final AnimationController _actions = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    animationBehavior: AnimationBehavior.preserve,
  );
  late final CurvedAnimation _slideCurve = CurvedAnimation(
    parent: _actions,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(_slideCurve);
  late final Animation<double> _titleFade = ReverseAnimation(_actions);
  bool _actionsOpen = false;

  TimelineLayout _layout = TimelineLayout.empty;
  Object? _layoutPeople, _layoutData;
  int _layoutMonth = -1;
  bool _layoutEveryone = false;

  @override
  void initState() {
    super.initState();
    _faces.timelineWanted = true;
    unawaited(_faces.loadTimeline());
    _loadCompact();
    _window.jumps.addListener(_toTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showTimelineTipOnce(context));
    });
  }

  /// A jump to a month, from a flag or the moments button, brings the list back to the top, where the preview opens
  /// out at the month it went to.
  void _toTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      glideTo(context, _scroll, 0, duration: const Duration(milliseconds: 380));
    }
  }

  @override
  void dispose() {
    _faces.timelineWanted = false;
    _window.jumps.removeListener(_toTop);
    _slideCurve.dispose();
    _actions.dispose();
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
      // Falls back to the expanded list.
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

  /// The story: the good moments year by year. Tapping one goes there. The controller keeps the choice of showing
  /// everyone, so the photos' moments follow it.
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

  /// The axis and rows are worked out again only when the people, their months or the month change.
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

  /// Slides the actions out of the button at the right end, or back into it. With motion off it just switches.
  void _setActions(bool open) {
    if (_actionsOpen == open) return;
    setState(() => _actionsOpen = open);
    if (calm(context)) {
      _actions.value = open ? 1 : 0;
    } else if (open) {
      unawaited(_actions.forward());
    } else {
      unawaited(_actions.reverse());
    }
  }

  /// Closes the row of actions and then does what the tapped action does.
  VoidCallback _thenClose(VoidCallback action) {
    return () {
      _setActions(false);
      action();
    };
  }

  /// The actions in the order they sit in the row. The row scrolls sideways when the screen is too narrow for all of
  /// them.
  List<Widget> _actionButtons() {
    return [
      if (_hasMoments)
        _BarButton(icon: Icons.auto_awesome_rounded, tooltip: 'Your story', onTap: _thenClose(_openStory)),
      _BarButton(icon: Icons.search_rounded, tooltip: 'Search people', onTap: _thenClose(_openSearch)),
      _BarButton(
        icon: Icons.swap_vert_rounded,
        tooltip: 'Order the timeline',
        active: _sort != TimelineSort.earliest,
        onTap: _thenClose(_pickSort),
      ),
      _BarButton(
        icon: _compact ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
        tooltip: _compact ? 'Show faces and details' : 'Collapse the list',
        active: _compact,
        onTap: _thenClose(() => _setCompact(!_compact)),
      ),
      _BarButton(
        icon: Icons.info_outline_rounded,
        tooltip: 'About the timeline',
        onTap: _thenClose(() => unawaited(showTimelineTip(context))),
      ),
    ];
  }

  /// The title, which gives way to the row of actions sliding in from the right end.
  Widget _titleAndActions(TextTheme textTheme) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          FadeTransition(
            opacity: _titleFade,
            child: Text('Timeline', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge),
          ),
          AnimatedBuilder(
            animation: _actions,
            builder: (context, _) {
              if (_actions.isDismissed) return const SizedBox.shrink();
              return ClipRect(
                child: FadeTransition(
                  opacity: _actions,
                  child: SlideTransition(
                    position: _slide,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(mainAxisSize: MainAxisSize.min, children: _actionButtons()),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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
                    : KeyedSubtree(key: const ValueKey('title'), child: _titleAndActions(textTheme)),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (_searching)
              _BarButton(icon: Icons.close_rounded, tooltip: 'Close search', onTap: _closeSearch)
            else
              _BarButton(
                icon: _actionsOpen ? Icons.close_rounded : Icons.more_horiz_rounded,
                tooltip: _actionsOpen ? 'Hide the options' : 'Options',
                active: _actionsOpen,
                dot: !_actionsOpen && (_compact || _sort != TimelineSort.earliest),
                onTap: () => _setActions(!_actionsOpen),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_searching && !_actionsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searching) {
          _closeSearch();
        } else {
          _setActions(false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(context),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GetBuilder<FacesController>(
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

                        _preview.update(layout, dataVersion: faces.timeline, datesDone: faces.timelineDone);

                        final slivers = <Widget>[
                          if (!_searching)
                            TimelineLens(
                              preview: _preview,
                              window: _window,
                              onOpenMonth: (month, photo) => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MonthPhotosScreen(month: month, focusKey: photo.key),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                              child: TimelineIntro(
                                layout: layout,
                                data: faces.timeline,
                                finished: faces.timelineDone,
                                now: now,
                              ),
                            ),
                          ),
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
                                  onTap: () => Navigator.of(
                                    context,
                                  ).push(MaterialPageRoute(builder: (_) => PersonScreen(person: row.person))),
                                );
                              }, childCount: rows.length),
                            ),
                          if (rows.any((r) => r.hasDates)) const SliverToBoxAdapter(child: TimelineFooter()),
                          SliverToBoxAdapter(
                            child: SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.xxl),
                          ),
                        ];

                        return NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
                            if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
                              _preview.userScrolling();
                            }
                            if (n is ScrollUpdateNotification ||
                                n is ScrollStartNotification ||
                                n is ScrollEndNotification) {
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
                    if (_actionsOpen)
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => _setActions(false),
                        child: const SizedBox.expand(),
                      ),
                  ],
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
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.dot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Filled, to show a choice that is on (the collapsed list, another order).
  final bool active;

  /// A small mark for a button that hides choices which are on.
  final bool dot;

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
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22, color: active ? AppColors.onPrimary : AppColors.ink),
                if (dot)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                      child: SizedBox(width: 7, height: 7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
