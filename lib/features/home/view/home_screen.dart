import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/export/controllers/export_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/memories/controllers/memories_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/floating_bar.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/export/view/export_zip_screen.dart';
import 'package:lost_and_found/features/people/features/together/view/people_filter_screen.dart';
import 'package:lost_and_found/features/people/features/timeline/view/people_timeline_screen.dart';
import 'package:lost_and_found/features/settings/view/settings_screen.dart';
import 'package:lost_and_found/features/home/view/widgets/action_fab.dart';
import 'package:lost_and_found/features/collections/view/collections_tab.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/people/view/faces_tab.dart';
import 'package:lost_and_found/features/collections/view/widgets/new_collection_sheet.dart';
import 'package:lost_and_found/features/library/view/library_tab.dart';
import 'package:lost_and_found/features/search/view/search_tab.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/features/memories/services/memories_service.dart';
part 'home_screen/shared.dart';
part 'home_screen/tab_pill.dart';
part 'home_screen/floating_nav_bar.dart';
part 'home_screen/tall_selection.dart';
part 'home_screen/tall_action_button.dart';
part 'home_screen/single_row_selection.dart';
part 'home_screen/nav_item.dart';
part 'home_screen/search_button.dart';
part 'home_screen/activity_dot.dart';

/// The app's four front-page destinations behind one floating bar: Library, Collections and Faces as tabs in a pill,
/// and Search as its own round button beside it. Search switches the body like a tab does, but it is not part of the
/// pill. Indexing lives entirely in the Library tab, where it is triggered from. A small pulsing dot on that tab
/// shows it is active even while you are looking at something else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// True while the user is scrolling down a list: the bar shrinks and settles lower (see _FloatingNavBar).
  /// Scrolling back up, or reaching the top, restores it.
  bool _shrunk = false;

  final MemoriesController _memories = Get.find<MemoriesController>();

  /// The round bolt button's state, to close its actions with the back button.
  final GlobalKey<ActionFabState> _fabKey = GlobalKey<ActionFabState>();

  /// Marking the home screen ready lets a tapped "daily memory" notification open its memory.
  @override
  void initState() {
    super.initState();
    _memories.homeReady = true;
    FloatingBarPresence.shown = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _memories.checkLaunch();
      _checkOpenTab();
    });
  }

  @override
  void dispose() {
    _memories.homeReady = false;
    FloatingBarPresence.shown = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkOpenTab();
  }

  /// Shows home tab [i]. [tapped] is true for a tap on the bar and false when a notification shows the Library tab.
  ///
  /// A newly shown tab is at rest, so the bar is full size. Choosing people belongs to the People tab and choosing
  /// collections to the Collections tab, so leaving either ends it. Opening Faces refreshes it, as looking never
  /// starts a scan. Search opens without the keyboard, which comes up when the box is tapped, so the suggestions and
  /// results under it are not covered straight away.
  void _showTab(NativeController controller, int i, {bool tapped = true}) {
    if (i != controller.homeTab) {
      if (tapped) HapticFeedback.selectionClick();
      _shrunk = false;
    }
    controller.setHomeTab(i);
    if (i != _tabFaces && Get.isRegistered<FacesController>()) {
      final faces = Get.find<FacesController>();
      if (faces.selecting) faces.stopSelecting();
    }
    if (i != _tabCollections && Get.isRegistered<CollectionsController>()) {
      final collections = Get.find<CollectionsController>();
      if (collections.selecting) collections.stopSelecting();
    }
    if (i == _tabFaces) {
      Get.find<FacesController>().refreshAll();
    }
    if (i != _tabSearch) {
      // The IndexedStack keeps the search box alive, and a stale focus on it would come back when a pushed screen
      // pops, putting the keyboard up over a different tab.
      controller.searchFocusNode.unfocus();
    }
  }

  /// A tap on a notification that belongs to a tab shows that tab, closing whatever was open on top of it. The scan's
  /// notification shows the Library tab, where the scan is, and the stories note shows the Search tab, where the rings
  /// are. "Index now" on the note that asks to finish indexing also starts the scan at once, over the whole phone.
  Future<void> _checkOpenTab() async {
    try {
      final tab = await MemoriesService().takeOpenTab();
      if (tab == null || !mounted) return;
      Get.until((route) => route.isFirst);
      final native = Get.find<NativeController>();
      _showTab(native, tab == _tabLibrary ? _tabLibrary : _tabSearch, tapped: false);
      if (await MemoriesService().takeIndexNow() && mounted) {
        native.setScanWholePhone(true);
        await startIndexing(context, native);
      }
    } catch (e) {
      debugPrint('takeOpenTab failed: $e');
    }
  }

  void _setShrunk(bool value) {
    if (_shrunk != value) setState(() => _shrunk = value);
  }

  /// What the bolt button offers on the page showing, which is the actions for the Collections and People tabs. There
  /// are none on the other tabs, and none while choosing. While a catch-up scan runs the People tab shows its
  /// progress instead of the update action. Choosing people, or seeing them over the years, needs at least two.
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
      final catchingUp =
          faces.syncing && !status.userPaused && status.error == null;
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

  /// Runs the face scan over whatever was missed, with its progress on the tab, or says everything is already covered.
  Future<void> _updatePeople(FacesController faces) async {
    final started = await faces.syncFaces();
    if (!started) AppToast.show('People are up to date.');
  }

  /// Shrinks the bar while a tab's list scrolls down. Only the tabs' own vertical lists count, not the horizontal chip
  /// rows.
  bool _onScroll(ScrollNotification n) {
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

  /// Builds the tabs and the floating bar over them. Back from another tab returns to Search, where the app opens, and
  /// back on Search leaves as usual. If the bolt button's actions are open, or people or collections are being chosen,
  /// back first closes or cancels that. The tabs run the full height and scroll under the bar, and each ends with
  /// [floatingBarClearance] so the last item can be brought clear of it. The bar hides while typing, because it would
  /// ride up on the keyboard. It stays mounted so it can animate both ways, and while hidden it cannot be tapped or
  /// read out.
  @override
  Widget build(BuildContext context) {
    return GetBuilder<NativeController>(
      builder: (controller) {
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

        return PopScope(
          canPop: controller.homeTab == _tabSearch,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_fabKey.currentState?.isOpen == true) {
              _fabKey.currentState!.close();
              return;
            }
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
                              SearchTab(controller: controller),
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _KeyboardHide(
                      hidden: keyboardOpen,
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

/// Tucks the bar away when the keyboard opens. It sinks and shrinks a little while fading, quickly and with an ease-in
/// so it is gone before the keyboard is. Coming back, it rises and settles with a small spring overshoot so it lands
/// softly rather than just appearing. The opacity gets its own plain curve, because it cannot overshoot the range 0
/// to 1.
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
