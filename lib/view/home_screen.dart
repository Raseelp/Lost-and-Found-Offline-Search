import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/export_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/view/export_zip_screen.dart';
import 'package:lost_and_found/view/people_filter_screen.dart';
import 'package:lost_and_found/view/people_timeline_screen.dart';
import 'package:lost_and_found/view/settings_screen.dart';
import 'package:lost_and_found/view/widget/action_fab.dart';
import 'package:lost_and_found/view/widget/collections_tab.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/faces_tab.dart';
import 'package:lost_and_found/view/widget/new_collection_sheet.dart';
import 'package:lost_and_found/view/widget/library_tab.dart';
import 'package:lost_and_found/view/widget/search_tab.dart';

// NativeController.homeTab values.
const int _tabSearch = 0;
const int _tabCollections = 1;
const int _tabLibrary = 2;
const int _tabFaces = 3;

// Proportions measured off Google Photos' floating bar on a ~411dp-wide
// phone: a 58dp fully-rounded pill, a 42dp selected chip inset 8dp inside
// it, a round search button the same 58dp tall, and the bar sitting ~20dp
// above the system navigation with wide side margins.
const double _barHeight = kFloatingBarHeight;
const double _barInset = 8;
const double _chipHeight = _barHeight - 2 * _barInset;

// The bar while several people are ticked: two rows (who is chosen, then the two buttons).
const double _tallBarHeight = 106;

/// The app's four front-page destinations behind one floating bar: Library,
/// Collections and Faces as tabs in a pill, and Search as its own round
/// button beside it - which still switches the body like a tab does, it just
/// isn't part of the pill. Indexing lives entirely in the Library tab (that's
/// where it's triggered from); a small pulsing dot on that tab signals it's
/// active even while you're looking at something else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // True while the user is scrolling down a list: the bar shrinks and settles
  // lower (see _FloatingNavBar). Scrolling back up, or reaching the top,
  // restores it.
  bool _shrunk = false;

  final MemoriesController _memories = Get.find<MemoriesController>();

  // The round bolt button's state, to close its actions with the back button.
  final GlobalKey<ActionFabState> _fabKey = GlobalKey<ActionFabState>();

  @override
  void initState() {
    super.initState();
    // A tapped "daily memory" notification opens its memory once the home screen is up.
    _memories.homeReady = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _memories.checkLaunch();
      _checkOpenLibrary();
    });
  }

  @override
  void dispose() {
    _memories.homeReady = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkOpenLibrary();
  }

  // Shows home tab [i]: what a tap on the bar does ([tapped]), and what the scan's notification does to show
  // the Library tab.
  void _showTab(NativeController controller, int i, {bool tapped = true}) {
    if (i != controller.homeTab) {
      if (tapped) HapticFeedback.selectionClick();
      // A newly shown tab is at rest, so the bar is full size.
      _shrunk = false;
    }
    controller.setHomeTab(i);
    // Choosing people belongs to the People tab: leaving it ends that.
    if (i != _tabFaces && Get.isRegistered<FacesController>()) {
      final faces = Get.find<FacesController>();
      if (faces.selecting) faces.stopSelecting();
    }
    // Likewise choosing collections belongs to the Collections tab.
    if (i != _tabCollections && Get.isRegistered<CollectionsController>()) {
      final collections = Get.find<CollectionsController>();
      if (collections.selecting) collections.stopSelecting();
    }
    // Opening Faces: refresh. (Looking never starts a scan.)
    if (i == _tabFaces) {
      Get.find<FacesController>().refreshAll();
    }
    // Search opens without the keyboard: it comes up when the box is tapped, so
    // the suggestions and results under it are not covered straight away.
    if (i != _tabSearch) {
      // Leaving the search tab - the box can still hold focus from an earlier visit (IndexedStack keeps
      // every tab's tree alive, and Flutter's focus history is app-wide, not scoped to whichever tab is
      // actually showing). Left alone, that stale focus can resurface later with no relation to what's now
      // open - popping back from a pushed detail screen (a collection, a person) that has no text field of
      // its own restores focus to whatever last held it, which otherwise pops the keyboard back up over a
      // completely different tab.
      controller.searchFocusNode.unfocus();
    }
  }

  // A tap on the scan's notification shows the Library tab, where the scan is,
  // closing whatever was open on top of it.
  Future<void> _checkOpenLibrary() async {
    try {
      if (!await NativeServices().takeOpenLibrary() || !mounted) return;
      Get.until((route) => route.isFirst);
      _showTab(Get.find<NativeController>(), _tabLibrary, tapped: false);
    } catch (e) {
      debugPrint('takeOpenLibrary failed: $e');
    }
  }

  void _setShrunk(bool value) {
    if (_shrunk != value) setState(() => _shrunk = value);
  }

  // What the bolt button offers on the page showing: the actions that used to sit under the description
  // at the top of the Collections and People tabs. None on the other tabs, and none while choosing.
  List<FabAction> _fabActions(
    NativeController native,
    FacesController faces,
    CollectionsController collections,
  ) {
    if (native.homeTab == _tabCollections) {
      if (collections.selecting) return const [];
      return [
        FabAction(
          icon: Icons.add_rounded,
          label: 'New collection',
          onTap: () => showNewCollectionSheet(context, collections),
        ),
        if (native.totalEmbeddings != 0 && collections.visible.isNotEmpty)
          FabAction(
            icon: Icons.collections_bookmark_outlined,
            label: 'Select collections',
            onTap: collections.startSelecting,
          ),
      ];
    }
    if (native.homeTab == _tabFaces) {
      if (faces.selecting) return const [];
      final status = faces.status;
      final noModel = !status.ready || status.error == 'no_model';
      // While a catch-up scan runs the tab shows its progress instead of this action.
      final catchingUp =
          faces.syncing && !status.userPaused && status.error == null;
      // Choosing people, or seeing them over the years, needs at least two.
      final several = faces.people.length >= 2;
      return [
        if (several)
          FabAction(
            icon: Icons.timeline_rounded,
            label: 'Timeline',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PeopleTimelineScreen()),
            ),
          ),
        if (several)
          FabAction(
            icon: Icons.groups_rounded,
            label: 'Select people',
            onTap: faces.startSelecting,
          ),
        if (!noModel && !catchingUp)
          FabAction(
            icon: Icons.sync_rounded,
            label: 'Update people',
            onTap: () => _updatePeople(faces),
          ),
      ];
    }
    return const [];
  }

  // Runs the face scan over whatever was missed (its progress shows on the tab), or says everything is
  // already covered.
  Future<void> _updatePeople(FacesController faces) async {
    final messenger = ScaffoldMessenger.of(context);
    final started = await faces.syncFaces();
    if (!started) {
      messenger.showSnackBar(
        const SnackBar(content: Text('People are up to date')),
      );
    }
  }

  bool _onScroll(ScrollNotification n) {
    // Only the tabs' own vertical lists - not the horizontal chip rows.
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;

    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse) {
        _setShrunk(true);
      } else if (n.direction == ScrollDirection.forward) {
        _setShrunk(false);
      }
    } else if (n is ScrollUpdateNotification &&
        n.metrics.pixels <= n.metrics.minScrollExtent + 4) {
      _setShrunk(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NativeController>(
      builder: (controller) {
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

        // Back from another tab returns to Search (where the app opens)
        // instead of leaving the app; back on Search leaves as usual.
        return PopScope(
          canPop: controller.homeTab == _tabSearch,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // The bolt button's actions are open: back puts them away first.
            if (_fabKey.currentState?.isOpen == true) {
              _fabKey.currentState!.close();
              return;
            }
            // Choosing people: back first cancels that, and stays on the tab.
            if (Get.isRegistered<FacesController>()) {
              final faces = Get.find<FacesController>();
              if (faces.selecting) {
                faces.stopSelecting();
                return;
              }
            }
            if (Get.isRegistered<CollectionsController>()) {
              final collections = Get.find<CollectionsController>();
              if (collections.selecting) {
                collections.stopSelecting();
                return;
              }
            }
            controller.setHomeTab(_tabSearch);
          },
          child: Scaffold(
            backgroundColor: AppColors.canvas,
            // bottom: false + a Stack: the tabs run the full height and scroll
            // *under* the floating bar (each ends with floatingBarClearance so the
            // last item can still be brought clear of it), instead of being cut
            // off in a strip above it.
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      const _HomeTopBar(),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: IndexedStack(
                            index: controller.homeTab,
                            children: [
                              SearchTab(
                                controller: controller,
                                onSeeAllCollections: () =>
                                    controller.setHomeTab(_tabCollections),
                              ),
                              GetBuilder<CollectionsController>(
                                builder: (collections) => CollectionsTab(
                                  controller: collections,
                                  native: controller,
                                ),
                              ),
                              LibraryTab(controller: controller),
                              const FacesTab(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Out of the way while typing - it would otherwise ride up on
                  // top of the keyboard. Stays mounted so it can animate both
                  // ways; while hidden it can't be tapped or read out.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _KeyboardHide(
                      hidden: keyboardOpen,
                      // Rebuilds with the People tab's "choose people" state: while that is
                      // on, the bar turns into the button that goes on to the photos.
                      child: GetBuilder<FacesController>(
                        builder: (faces) => GetBuilder<CollectionsController>(
                          builder: (collections) => _FloatingNavBar(
                          selection:
                              faces.selecting && controller.homeTab == _tabFaces
                              ? _BarSelection(
                                  chosen: faces.selectedPeople.length,
                                  onCancel: faces.stopSelecting,
                                  emptyLabel: 'Choose people',
                                  faceIds: [
                                    for (final p in faces.selectedPeople)
                                      p.coverFaceId,
                                  ],
                                  summaryFor: (n) => n == 1
                                      ? '1 person chosen'
                                      : '$n people chosen',
                                  actions: [
                                    _BarAction(
                                      icon: Icons.folder_zip_outlined,
                                      labelFor: (n) => 'Export as zip',
                                      onTap: () {
                                        final people = faces.selectedPeople;
                                        if (people.isEmpty) return;
                                        faces.stopSelecting();
                                        openExportZip(
                                          context,
                                          select: {
                                            for (final p in people)
                                              ExportController.personKey(p.id),
                                          },
                                        );
                                      },
                                    ),
                                    _BarAction(
                                      icon: Icons.photo_library_outlined,
                                      labelFor: (n) => n == 1
                                          ? 'Their photos'
                                          : 'Photos together',
                                      onTap: () {
                                        final people = faces.selectedPeople;
                                        if (people.isEmpty) return;
                                        faces.stopSelecting();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => PeopleFilterScreen(
                                              people: people,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                )
                              : collections.selecting &&
                                    controller.homeTab == _tabCollections
                              ? _BarSelection(
                                  chosen: collections.selectedIds.length,
                                  onCancel: collections.stopSelecting,
                                  emptyLabel: 'Choose collections',
                                  actions: [
                                    _BarAction(
                                      icon: Icons.folder_zip_outlined,
                                      labelFor: (n) => n == 1
                                          ? 'Export as zip'
                                          : 'Export $n as zip',
                                      onTap: () {
                                        final ids = {
                                          for (final id
                                              in collections.selectedIds)
                                            id == MemoriesController.selectionId
                                                ? ExportController.memoryKey
                                                : ExportController.collectionKey(
                                                    id,
                                                  ),
                                        };
                                        if (ids.isEmpty) return;
                                        collections.stopSelecting();
                                        openExportZip(context, select: ids);
                                      },
                                    ),
                                  ],
                                )
                              : null,
                          index: controller.homeTab,
                          shrunk: _shrunk,
                          showActivityDot: controller.isScanning,
                          onChanged: (i) => _showTab(controller, i),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The round bolt button above the search button, and the actions it fans out.
                  Positioned.fill(
                    child: GetBuilder<FacesController>(
                      builder: (faces) => GetBuilder<CollectionsController>(
                        builder: (collections) => ActionFab(
                          key: _fabKey,
                          actions: _fabActions(controller, faces, collections),
                          visible: !keyboardOpen,
                          shrunk: _shrunk,
                          searchActive: controller.homeTab == _tabSearch,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Tucks the bar away when the keyboard opens: it sinks and shrinks a little
// while fading, quickly and with an ease-in so it's gone before the keyboard
// is; coming back, it rises and settles with a small spring overshoot so it
// lands softly rather than just appearing.
class _KeyboardHide extends StatelessWidget {
  const _KeyboardHide({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: hidden ? 200 : 460);
    final curve = hidden ? Curves.easeInCubic : Curves.easeOutBack;

    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedSlide(
          duration: duration,
          curve: curve,
          offset: Offset(0, hidden ? 0.7 : 0),
          child: AnimatedScale(
            duration: duration,
            curve: curve,
            scale: hidden ? 0.9 : 1,
            alignment: Alignment.bottomCenter,
            // Opacity can't overshoot 0..1, so it gets its own plain curve.
            child: AnimatedOpacity(
              duration: Duration(milliseconds: hidden ? 160 : 260),
              curve: hidden ? Curves.easeIn : Curves.easeOut,
              opacity: hidden ? 0 : 1,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Lost & Found', style: Theme.of(context).textTheme.titleLarge),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.ink,
              size: 22,
            ),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

class _NavTab {
  const _NavTab(this.value, this.label, this.icon, this.selectedIcon);

  final int value;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _navTabs = [
  _NavTab(
    _tabLibrary,
    'Library',
    Icons.photo_library_outlined,
    Icons.photo_library_rounded,
  ),
  _NavTab(
    _tabCollections,
    'Collections',
    Icons.collections_bookmark_outlined,
    Icons.collections_bookmark_rounded,
  ),
  _NavTab(
    _tabFaces,
    'Faces',
    Icons.face_retouching_natural_outlined,
    Icons.face_retouching_natural,
  ),
];

// A pill holding the three tabs - only the selected one shows its icon and
// sits in a teal chip, the others are just a label - with Search as its own
// round button next to it. Search selects the body the same way a tab does,
// so while it's active the pill has nothing selected and the button takes
// over the highlight. Tonal like the rest of the app (parchment on canvas,
// primary for "on"), not a dark slab.
/// One thing the bar can do with what is ticked: its icon, its words (they can depend on how
/// many are ticked) and what it does.
class _BarAction {
  const _BarAction({
    required this.icon,
    required this.labelFor,
    required this.onTap,
  });

  final IconData icon;
  final String Function(int chosen) labelFor;
  final VoidCallback onTap;
}

/// While choosing people (People tab) or collections (Collections tab): how many are ticked
/// and what the bar can do with them. One action fills the bar; two share it, side by side.
class _BarSelection {
  const _BarSelection({
    required this.chosen,
    required this.onCancel,
    required this.emptyLabel,
    required this.actions,
    this.faceIds = const [],
    this.summaryFor,
  });

  final int chosen;
  final VoidCallback onCancel;

  /// What the bar says until something is ticked.
  final String emptyLabel;
  final List<_BarAction> actions;

  /// The faces of the people ticked (shown stacked in the tall bar).
  final List<int> faceIds;

  /// "3 people chosen" and the like, for the tall bar.
  final String Function(int chosen)? summaryFor;

  /// Two actions, once something is ticked: the bar grows to two rows so neither is cramped.
  bool get tall => chosen > 0 && actions.length > 1;
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onChanged,
    required this.showActivityDot,
    required this.shrunk,
    this.selection,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool showActivityDot;
  final bool shrunk;

  // Non-null while choosing people: the bar becomes the "find photos" button.
  final _BarSelection? selection;

  @override
  Widget build(BuildContext context) {
    // Margins are kept modest so the pill has room for the selected tab's icon
    // and label at full size - the text never has to shrink to fit. Only on a
    // very narrow screen do the tabs tighten their padding.
    final width = MediaQuery.of(context).size.width;
    final margin = width >= 400 ? 20.0 : 16.0;
    final compact = width < 380;
    final selection = this.selection;
    final choosing = selection != null;
    final ready = choosing && selection.chosen > 0;

    // Scrolling down shrinks the whole bar toward its bottom edge and lets it
    // settle lower into the gap beneath it, so it recedes from the content;
    // scrolling back up restores it. Scale and slide are transforms, so
    // nothing relayouts mid-scroll.
    return AnimatedSlide(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      offset: Offset(0, shrunk ? 0.08 : 0),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        scale: shrunk ? 0.93 : 1,
        alignment: Alignment.bottomCenter,
        child: Padding(
          // Bottom includes the system inset now that the body runs behind it.
          padding: EdgeInsets.fromLTRB(
            margin,
            AppSpacing.sm,
            margin,
            kFloatingBarBottomGap + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  // Translucent frosted glass: content scrolls visibly behind
                  // it, a touch more see-through while it's out of the way.
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    // The same pill either way: only its colour and contents change, so it
                    // reads as the bar itself turning into the button (and back).
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      height: choosing && selection.tall
                          ? _tallBarHeight
                          : _barHeight,
                      padding: const EdgeInsets.all(_barInset),
                      decoration: BoxDecoration(
                        color: ready
                            ? AppColors.primary
                            : AppColors.parchment.withValues(
                                alpha: shrunk ? 0.55 : 0.72,
                              ),
                        borderRadius: BorderRadius.circular(_barHeight / 2),
                        border: Border.all(
                          color: ready ? AppColors.primary : AppColors.hairline,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, if (current != null) current],
                        ),
                        child: choosing
                            ? _SelectionContent(
                                key: const ValueKey('choose'),
                                selection: selection,
                              )
                            : Row(
                                key: const ValueKey('tabs'),
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final tab in _navTabs)
                                    _NavItem(
                                      tab: tab,
                                      selected: index == tab.value,
                                      showDot:
                                          tab.value == _tabLibrary &&
                                          showActivityDot,
                                      compact: compact,
                                      onTap: () => onChanged(tab.value),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              // The round Search button slides away while choosing (the pill grows into
              // the space), and comes back after. Kept mounted, just folded to zero width.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: choosing ? 0 : 1),
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                  ),
                ),
                child: IgnorePointer(
                  ignoring: choosing,
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.sm),
                      _SearchButton(
                        active: index == _tabSearch,
                        shrunk: shrunk,
                        onTap: () => onChanged(_tabSearch),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// What the pill shows while choosing people or collections: a close button on the left, and
// the action(s) across the rest - the words "Choose ..." until something is ticked, then the
// buttons. Two actions share the width with a thin line between them.
class _SelectionContent extends StatelessWidget {
  const _SelectionContent({super.key, required this.selection});

  final _BarSelection selection;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: selection.tall
          ? _TallSelection(key: const ValueKey('tall'), selection: selection)
          : _SingleRowSelection(
              key: const ValueKey('row'),
              selection: selection,
            ),
    );
  }
}

// Option E: who is chosen on the first row (their faces, how many, and the close button), and
// the two actions side by side on the second - the right-hand one, the main one, in white.
class _TallSelection extends StatelessWidget {
  const _TallSelection({super.key, required this.selection});

  final _BarSelection selection;

  static const double _face = 30;
  static const double _overlap = 20;

  @override
  Widget build(BuildContext context) {
    final actions = selection.actions;
    final textTheme = Theme.of(context).textTheme;
    final shownFaces = selection.faceIds.take(3).toList();
    final more = selection.faceIds.length - shownFaces.length;
    final summary =
        selection.summaryFor?.call(selection.chosen) ??
        '${selection.chosen} chosen';

    // Laid out at its full height right away and clipped by the bar while the bar grows.
    return OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: _tallBarHeight - 2 * _barInset,
      child: SizedBox(
        height: _tallBarHeight - 2 * _barInset,
        child: Column(
          children: [
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: _face + _overlap * (shownFaces.length - 1) +
                        (more > 0 ? _overlap : 0),
                    height: _face,
                    child: Stack(
                      children: [
                        for (var i = 0; i < shownFaces.length; i++)
                          Positioned(
                            left: i * _overlap,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: FaceAvatar(
                                faceId: shownFaces[i],
                                size: _face - 4,
                              ),
                            ),
                          ),
                        if (more > 0)
                          Positioned(
                            left: shownFaces.length * _overlap,
                            child: Container(
                              width: _face,
                              height: _face,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryFocus,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '+$more',
                                style: textTheme.labelSmall?.copyWith(
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Cancel',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selection.onCancel,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.onPrimary.withValues(alpha: 0.18),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: _chipHeight,
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _TallActionButton(
                        action: actions[i],
                        label: actions[i].labelFor(selection.chosen),
                        main: i == actions.length - 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TallActionButton extends StatelessWidget {
  const _TallActionButton({
    required this.action,
    required this.label,
    required this.main,
  });

  final _BarAction action;
  final String label;

  /// The main action is a solid white button; the other is a soft one.
  final bool main;

  @override
  Widget build(BuildContext context) {
    final foreground = main ? AppColors.primary : AppColors.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: main
                ? AppColors.onPrimary
                : AppColors.onPrimary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(_chipHeight / 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 18, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Nothing ticked yet, or a single action: ✕ on the left and the words or the button across.
class _SingleRowSelection extends StatelessWidget {
  const _SingleRowSelection({super.key, required this.selection});

  final _BarSelection selection;

  @override
  Widget build(BuildContext context) {
    final ready = selection.chosen > 0;
    final foreground = ready ? AppColors.onPrimary : AppColors.ink;
    final actions = selection.actions;
    final labels = [for (final a in actions) a.labelFor(selection.chosen)];

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Cancel',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: selection.onCancel,
            child: Container(
              width: _chipHeight,
              height: _chipHeight,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: foreground.withValues(alpha: ready ? 0.18 : 0.08),
              ),
              child: Icon(Icons.close_rounded, size: 20, color: foreground),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !ready
                ? Center(
                    key: const ValueKey('empty'),
                    child: Text(
                      selection.emptyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: AppColors.ink48),
                    ),
                  )
                : Row(
                    key: ValueKey(labels.join('|')),
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0)
                          Container(
                            width: 1,
                            height: 22,
                            color: foreground.withValues(alpha: 0.35),
                          ),
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: labels[i],
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: actions[i].onTap,
                              child: SizedBox(
                                height: _chipHeight,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            actions[i].icon,
                                            size: 18,
                                            color: foreground,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Text(
                                            labels[i],
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(color: foreground),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        // One action (or none yet): same width as the close button, so the words are centred
        // in the pill. Two actions use the whole width.
        SizedBox(
          width: ready && actions.length > 1 ? AppSpacing.xs : _chipHeight,
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.showDot,
    required this.compact,
    required this.onTap,
  });

  final _NavTab tab;
  final bool compact;
  final bool selected;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sized by its own content, not Flexible: three Flexibles split the pill
    // into equal thirds, which is smaller than the selected tab needs (icon +
    // "Collections") and clipped its label. The pill has room for all three
    // at natural width.
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: _chipHeight,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 12 : (compact ? 10 : 14),
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            // No FittedBox: the label and icon are always the same size, selected
            // or not - the pill has the room, so nothing scales down to fit.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(tab.selectedIcon, size: 18, color: AppColors.onPrimary),
                  const SizedBox(width: 7),
                ],
                Text(
                  tab.label,
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? AppColors.onPrimary : AppColors.ink80,
                  ),
                ),
                if (showDot) ...[
                  const SizedBox(width: 5),
                  _ActivityDot(
                    color: selected ? AppColors.onPrimary : AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Search as its own round button. Inactive it's a plain tonal circle; when
// Search is the screen showing, it comes alive - fills teal, the magnifier
// gives a little tilt-and-bounce, and a ring ripples out once from it - so
// it reads as a switched-on control rather than a shortcut.
class _SearchButton extends StatefulWidget {
  const _SearchButton({
    required this.active,
    required this.shrunk,
    required this.onTap,
  });

  final bool active;
  final bool shrunk;
  final VoidCallback onTap;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    // Already on when the app opens (it launches on Search) - show it
    // settled rather than playing the ripple on every launch.
    if (widget.active) _burst.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SearchButton old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _burst.forward(from: 0);
    } else if (!widget.active && old.active) {
      _burst.value = 0;
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: 'Search',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // While the bolt button's liquid runs into this button it draws this circle itself (see ActionFab).
        child: ValueListenableBuilder<double>(
          valueListenable: ActionFab.ownsSearch,
          builder: (context, level, _) => AnimatedBuilder(
          animation: _burst,
          builder: (context, _) {
            // Fades out (circle, frost, border and icon alike) while the bolt button's liquid draws the
            // circle instead, and back in when it has let go.
            final fade = 1 - level;
            final t = _burst.value;
            // Overshoots and settles: a tilt that swings past and back.
            final tilt = widget.active
                ? math.sin(t * math.pi * 2) * 0.35 * (1 - t)
                : 0.0;
            final pop = widget.active ? 1 + 0.18 * math.sin(t * math.pi) : 1.0;

            return SizedBox(
              width: _barHeight,
              height: _barHeight,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (widget.active && t > 0 && t < 1)
                    Container(
                      width: _barHeight + 26 * t,
                      height: _barHeight + 26 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(
                            alpha: 0.45 * (1 - t),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14 * fade, sigmaY: 14 * fade),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 340),
                        curve: Curves.easeOutCubic,
                        width: _barHeight,
                        height: _barHeight,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.active
                              ? AppColors.primary.withValues(
                                  alpha: (widget.shrunk ? 0.72 : 0.85) * fade,
                                )
                              : AppColors.parchment.withValues(
                                  alpha: (widget.shrunk ? 0.55 : 0.72) * fade,
                                ),
                          border: Border.all(
                            color: (widget.active
                                    ? AppColors.primary
                                    : AppColors.hairline)
                                .withValues(alpha: fade),
                          ),
                        ),
                        child: Transform.rotate(
                          angle: tilt,
                          child: Transform.scale(
                            scale: pop,
                            child: Icon(
                              Icons.search_rounded,
                              color: (widget.active
                                      ? AppColors.onPrimary
                                      : AppColors.ink)
                                  .withValues(alpha: fade),
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

// A quiet pulse rather than a static badge - it needs to read as "something
// ongoing", not "something needs your attention".
class _ActivityDot extends StatefulWidget {
  const _ActivityDot({required this.color});

  final Color color;

  @override
  State<_ActivityDot> createState() => _ActivityDotState();
}

class _ActivityDotState extends State<_ActivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
