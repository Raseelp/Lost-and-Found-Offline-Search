import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/tour/search_demo.dart' show TourBestMatch;
import 'package:lost_and_found/view/tour/tour_person_tile.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/widget/library_tab.dart' show startIndexing;
import 'package:lost_and_found/view/widget/timeline_preview.dart'
    show bentoRects;

/// Takes the person to the Library tab (closing whatever is open on top of the tabs first).
void goToLibrary(BuildContext context) {
  final native = Get.find<NativeController>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  native.setHomeTab(2);
  native.searchFocusNode.unfocus();
}

/// Where [NothingIndexed] is shown: each place has its own picture of what it will hold.
enum NothingIndexedPlace { search, collections, faces, export }

/// What a screen shows when nothing has been indexed yet: a small picture of what the screen will hold, made of the
/// tour's sample photos (bundled, CC0) since there is nothing of the person's own to show yet, then a line about it
/// and a button that starts indexing (as the Library's chip does) and goes to the Library to show it. The picture is
/// kept small: it shows the way, the screen is not about it.
///
/// On Search, example searches take turns and the photos move into the order of how well they match, the best first
/// and biggest (the tour's search, page 2); on Collections, the tiles get their covers and names; on Faces, people
/// show as the People tab shows them, a stack of faces each, some still to be named; on the zip export, the list gets
/// its rows and two are chosen. With animations turned off they show filled in, still.
class NothingIndexed extends StatelessWidget {
  const NothingIndexed({super.key, required this.place});

  final NothingIndexedPlace place;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (title, body) = switch (place) {
      NothingIndexedPlace.search => (
        'Search by what is in a photo',
        'Index your photos once, and you can find them like this.',
      ),
      NothingIndexedPlace.collections => (
        'Your collections fill themselves in',
        'Beach, food, pets, mountains and more, sorted for you once your photos are indexed.',
      ),
      NothingIndexedPlace.faces => (
        'The people in your photos',
        'Once your photos are indexed, the same faces are grouped into people. Then give them names.',
      ),
      NothingIndexedPlace.export => (
        'Nothing to put in a zip yet',
        'Index your photos first. Then pack any collection or person into one zip.',
      ),
    };
    return Column(
      children: [
        ExcludeSemantics(
          child: Center(
            child: ConstrainedBox(
              // A way in, not the screen itself: kept to about two thirds of a phone's width.
              constraints: const BoxConstraints(maxWidth: 260),
              child: switch (place) {
                NothingIndexedPlace.search => const _SearchDemo(),
                NothingIndexedPlace.collections => const _CollectionsDemo(),
                NothingIndexedPlace.faces => const _FacesDemo(),
                NothingIndexedPlace.export => const _ExportDemo(),
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body,
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink80,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        // The scan starts here, as from the Library's chip, and the Library comes up to show it.
        FilledButton(
          onPressed: () {
            final native = Get.find<NativeController>();
            goToLibrary(context);
            startIndexing(context, native);
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.fromLTRB(7, 0, 22, 0),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The scan chip, small: the same thing that starts the scan in the Library.
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFocus,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.memory_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Text('Start indexing'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Runs on this phone. Nothing is uploaded.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
        ),
      ],
    );
  }
}

// The tour's sample pictures the demos are made of.
String _photo(String id) => 'assets/tour/photos/$id.jpg';
String _face(String id) => 'assets/tour/faces/$id.jpg';

/// Runs a demo's loop (and the shimmer of its empty places), or holds it still when animations are turned off. The
/// tickers stop on their own while the tab is not the one showing.
mixin _Loop<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  Duration get loopLength;

  /// Whether the demo has empty places that shimmer (else no ticker runs for it).
  bool get shimmers => true;

  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: loopLength,
  );
  late final AnimationController shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// Animations are turned off: everything shows filled in, and nothing moves.
  bool still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      loop.stop();
      shimmer.stop();
      loop.value = 0.5;
    } else {
      if (!loop.isAnimating) loop.repeat();
      if (shimmers && !shimmer.isAnimating) shimmer.repeat();
    }
  }

  @override
  void dispose() {
    loop.dispose();
    shimmer.dispose();
    super.dispose();
  }

  /// How much of a picture shows at this point of the loop when it comes in at [start] (a part of the loop): fading in
  /// over a tenth, there until [end], gone again by [end] + 0.1.
  double shown(double start, {double end = 0.78}) {
    if (still) return 1;
    final t = loop.value;
    if (t < start) return 0;
    if (t < start + 0.1) return Curves.easeOut.transform((t - start) / 0.1);
    if (t < end) return 1;
    if (t < end + 0.1) return 1 - (t - end) / 0.1;
    return 0;
  }
}

/// An empty place, with a soft light going over it, as while something is loading.
class _Ghost extends StatelessWidget {
  const _Ghost({required this.shimmer, required this.radius, this.child});

  final Animation<double> shimmer;
  final BorderRadius radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmer,
      builder: (context, child) {
        final x = 1.5 - 2 * shimmer.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: const [
                AppColors.parchment,
                AppColors.pearl,
                AppColors.parchment,
              ],
              stops: const [0.3, 0.5, 0.7],
            ),
          ),
          child: child,
        );
      },
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// A picture that fills its place, as a tile crops it.
Widget _cover(String asset, {int width = 320}) => Image.asset(
  asset,
  fit: BoxFit.cover,
  cacheWidth: width,
  width: double.infinity,
  height: double.infinity,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

// ---- Search: example searches take turns, and the photos move into the order of how well they match ----

class _SearchDemo extends StatefulWidget {
  const _SearchDemo();

  @override
  State<_SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<_SearchDemo>
    with TickerProviderStateMixin, _Loop {
  static const int _shown = 7;

  // The tour's searches, worked out ahead of time (nothing is searched here).
  static final List<SampleQuery> _queries = [
    for (final text in const [
      'a dog on a beach',
      'birthday cake',
      'surfing at sunset',
      'friends hiking',
    ])
      kSampleQueries.firstWhere((q) => q.text == text),
  ];

  // The photos that take part (the "@" search's person is not among them).
  static final List<SamplePhoto> _photos = [
    for (final p in kSamplePhotos)
      if (!p.id.startsWith('messi')) p,
  ];

  @override
  Duration get loopLength => Duration(milliseconds: 3200 * _queries.length);

  @override
  bool get shimmers => false;

  // Which example is showing: built again only when it changes (the photos move by themselves).
  int _turn = 0;

  @override
  void initState() {
    super.initState();
    loop.addListener(() {
      final turn = still
          ? 0
          : (loop.value * _queries.length).floor().clamp(
              0,
              _queries.length - 1,
            );
      if (turn != _turn) setState(() => _turn = turn);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Builder(
      builder: (context) {
        final query = _queries[_turn];
        final order = query.order;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'For example',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: _ExampleChip(
                    key: ValueKey(query.text),
                    word: query.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 170,
              child: LayoutBuilder(
                builder: (context, box) {
                  final area = Size(box.maxWidth, box.maxHeight);
                  final rects = bentoRects(_shown, area, gap: 4);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final photo in _photos)
                        _tile(photo, order.indexOf(photo.id), rects, area),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // A photo in its place for the search: the best match first and biggest, as the tour's search lays them out.
  Widget _tile(SamplePhoto photo, int rank, List<Rect> rects, Size area) {
    final visible = rank >= 0 && rank < _shown;
    final rect = visible
        ? rects[rank]
        : Rect.fromCenter(
            center: area.center(Offset.zero),
            width: 30,
            height: 30,
          );
    return AnimatedPositioned(
      key: ValueKey(photo.id),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 450),
        opacity: visible ? 1 : 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                photo.asset,
                fit: BoxFit.cover,
                alignment: photo.focus,
                cacheWidth: 360,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.parchment),
              ),
              if (visible && rank == 0)
                const Positioned(left: 6, bottom: 6, child: TourBestMatch()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The example search above the photos, in the app's green.
class _ExampleChip extends StatelessWidget {
  const _ExampleChip({super.key, required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_rounded, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            word,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Collections: the tiles get their covers and names, one after another ----

class _CollectionsDemo extends StatefulWidget {
  const _CollectionsDemo();

  @override
  State<_CollectionsDemo> createState() => _CollectionsDemoState();
}

class _CollectionsDemoState extends State<_CollectionsDemo>
    with TickerProviderStateMixin, _Loop {
  @override
  Duration get loopLength => const Duration(milliseconds: 6500);

  Widget _tile(String name, String asset, double start) {
    final radius = BorderRadius.circular(AppRadius.xl);
    return _Ghost(
      shimmer: shimmer,
      radius: radius,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, child) {
          final a = shown(start);
          return Opacity(
            opacity: a,
            child: Transform.scale(scale: 0.85 + 0.15 * a, child: child),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cover(asset),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x8C000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.sm,
              child: Text(
                name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - gap) / 2;
        final row = half * 0.62;
        return Column(
          children: [
            SizedBox(
              height: 2 * row + gap,
              child: Row(
                children: [
                  SizedBox(
                    width: half,
                    child: _tile('Beach', _photo('friends_beach'), 0.03),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: half,
                    child: Column(
                      children: [
                        SizedBox(
                          height: row,
                          child: _tile('Food', _photo('cake'), 0.11),
                        ),
                        const SizedBox(height: gap),
                        SizedBox(
                          height: row,
                          child: _tile('Pets', _photo('puppy'), 0.18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: row,
              child: _tile('Mountains', _photo('snow_hike'), 0.26),
            ),
          ],
        );
      },
    );
  }
}

// ---- Faces: people as the People tab shows them, some still to be named ----

class _FacesDemo extends StatelessWidget {
  const _FacesDemo();

  // Who is shown (no name: still to be named), their faces (the cover first), and the lean of their stack.
  static const List<(String, List<String>, double)> _people = [
    ('Maya', ['maya', 'maya_2', 'maya_3'], -4.4),
    ('Sam', ['sam', 'sam_2', 'sam_3'], 3.0),
    ('', ['noor'], 5.4),
    ('Leo', ['messi', 'messi_2'], -3.0),
    ('', ['suarez'], 2.2),
    ('', ['leo'], -5.6),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth / 3;
        return Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final (i, person) in _people.indexed)
              SizedBox(
                width: width,
                child: TourPersonTile(
                  name: person.$1,
                  photos: 0,
                  detail: '',
                  addName: person.$1.isEmpty,
                  faces: [for (final f in person.$2) _face(f)],
                  lean: person.$3,
                  index: i,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---- The zip export: the list gets its rows, and two of them are chosen ----

class _ExportDemo extends StatefulWidget {
  const _ExportDemo();

  @override
  State<_ExportDemo> createState() => _ExportDemoState();
}

class _ExportDemoState extends State<_ExportDemo>
    with TickerProviderStateMixin, _Loop {
  // What each of the first three rows holds, and whether it gets chosen.
  static final List<(String, String, String, bool)> _rows = [
    ('Beach', 'Collection', _photo('friends_beach'), true),
    ('Maya', 'Person', _face('maya'), true),
    ('Food', 'Collection', _photo('cake'), false),
  ];

  @override
  Duration get loopLength => const Duration(milliseconds: 7000);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.xl);
    Widget row(int i) {
      final start = 0.03 + 0.06 * i;
      final item = i < _rows.length ? _rows[i] : null;
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: _Ghost(
          shimmer: shimmer,
          radius: radius,
          child: item == null
              ? null
              : AnimatedBuilder(
                  animation: loop,
                  builder: (context, child) {
                    final a = shown(start);
                    return Opacity(
                      opacity: a,
                      child: Transform.translate(
                        offset: Offset(-6 * (1 - a), 0),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: radius,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            item.$2 == 'Person' ? 24 : AppRadius.md,
                          ),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: _cover(item.$3, width: 108),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$1, style: textTheme.titleSmall),
                              Text(
                                item.$2,
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.ink80,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedBuilder(
                          animation: loop,
                          builder: (context, _) {
                            final on = item.$4 ? shown(start + 0.2) : 0.0;
                            return Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.lerp(
                                  Colors.transparent,
                                  AppColors.primary,
                                  on,
                                ),
                                border: Border.all(
                                  color: Color.lerp(
                                    AppColors.hairline,
                                    AppColors.primary,
                                    on,
                                  )!,
                                  width: 2,
                                ),
                              ),
                              child: Opacity(
                                opacity: on,
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          row(i),
        ],
      ],
    );
  }
}
