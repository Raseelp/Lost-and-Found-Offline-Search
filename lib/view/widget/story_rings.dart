import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/controllers/stories_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/story_viewer_screen.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

/// Opens the stories at ring [index] of [rings]. [origin] is where the ring was on screen: the
/// story grows out of it, and closes back into it.
void openStories(BuildContext context, List<StoryRing> rings, int index, {Offset? origin, double originRadius = 30}) {
  // A second tap while the first story is opening must not open a second one on top of it.
  if (_opening != null) return;
  final route = StoryRoute(rings: rings, initial: index, origin: origin, originRadius: originRadius);
  _opening = route;
  Navigator.of(context).push(route).whenComplete(() => _opening = null);
}

StoryRoute? _opening;

/// Hands [builder] the rings to show, kept up to date as people, collections and what has been
/// seen change, and how many more are still on their way: [loading] rings that are not there yet
/// (people and collections are found one after the other, and the first time that takes a moment).
class _RingsBuilder extends StatelessWidget {
  const _RingsBuilder({required this.builder});

  final Widget Function(BuildContext context, List<StoryRing> rings, int loading) builder;

  /// How many rings are drawn as placeholders while there are none, and while the collections
  /// are still being scored for the first time.
  static const int _placeholders = 5;
  static const int _placeholdersMore = 2;

  @override
  Widget build(BuildContext context) {
    final native = Get.find<NativeController>();

    return GetBuilder<FacesController>(
      builder: (faces) => GetBuilder<CollectionsController>(
        builder: (collections) => GetBuilder<StoriesController>(
          builder: (stories) {
            final rings = stories.ringsFor(faces.people, collections);
            // Collections are scored once after the library is indexed; until then they have no rings.
            final scoring = native.totalEmbeddings > 0 && !collections.hasScored;
            // With nothing indexed there will be no rings, so nothing is waited for (no grey rings that come and go).
            final waiting = native.totalEmbeddings > 0;
            var loading = 0;
            if (waiting &&
                (!stories.ready || (rings.isEmpty && (faces.isLoadingPeople || scoring || collections.isScoring)))) {
              loading = _placeholders;
            } else if (waiting && rings.isNotEmpty && scoring) {
              loading = _placeholdersMore;
            }
            return builder(context, rings, loading);
          },
        ),
      ),
    );
  }
}

/// The rings of the Search tab: one per person or collection, a lit ring while there is something
/// not seen and a grey one after. A refresh button by the title asks for new stories at once, and a long press on a
/// ring sets it aside for a while.
///
/// It is one bar in two sizes. Before a search it is large, with names and a title. Once there are
/// results ([compact]) the same rings shrink in place into a thin strip above them, the names and
/// title fold away, and a "Stories" button slides in at the left to go back; going back is the
/// same movement the other way.
///
/// While the first rings are still being found, grey rings with a coloured arc running round them
/// stand where they will be, the arcs a little behind one another so a wave goes along the row.
class StoryRingsBar extends StatelessWidget {
  const StoryRingsBar({super.key, required this.controller, required this.compact});

  final NativeController controller;
  final bool compact;

  static const double _large = 68;
  static const double _small = 48;
  static const double _backWidth = 56;

  @override
  Widget build(BuildContext context) {
    return _RingsBuilder(
      builder: (context, rings, loading) {
        if (rings.isEmpty && loading == 0) return const SizedBox.shrink();
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: compact ? 1 : 0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) => _bar(context, rings, loading, t),
        );
      },
    );
  }

  // [t]: 0 large (before a search), 1 compact (above results).
  Widget _bar(BuildContext context, List<StoryRing> rings, int loading, double t) {
    final textTheme = Theme.of(context).textTheme;
    final stories = Get.find<StoriesController>();
    final size = _large + (_small - _large) * t;
    // Room for a name under a ring at the system text size.
    final labelRoom = 20 * MediaQuery.textScalerOf(context).scale(1);
    final labelFold = 1 - t;
    final labelOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    // Every ring has been opened (nothing lit is left), so there is something to ask for.
    final allSeen = loading == 0 && rings.isNotEmpty && rings.every(stories.isSeen);

    Widget label(Widget child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: labelFold,
        child: Opacity(
          opacity: labelOpacity,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: child,
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md * t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: labelFold,
              child: Opacity(
                opacity: labelOpacity,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'STORIES',
                            style: textTheme.labelSmall?.copyWith(color: AppColors.ink48, letterSpacing: 0.5),
                          ),
                        ),
                        // A new set of stories now. Only once every story has been seen: before that there is
                        // nothing to refresh, and it was tapped out of curiosity.
                        IgnorePointer(
                          ignoring: compact || !allSeen,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.8,
                                  end: 1,
                                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
                                child: child,
                              ),
                            ),
                            child: allSeen
                                ? _RefreshButton(
                                    key: const ValueKey('refresh'),
                                    refreshing: stories.refreshing,
                                    onTap: () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final anything = await stories.refreshStories();
                                      if (!anything) {
                                        messenger
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            const SnackBar(content: Text('Nothing new right now. Check back later.')),
                                          );
                                      }
                                    },
                                  )
                                : const SizedBox.shrink(key: ValueKey('no-refresh')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: size + (AppSpacing.xs + labelRoom) * labelFold,
            child: Row(
              children: [
                // The way back to the large rings, sliding in at the left once there are results.
                IgnorePointer(
                  ignoring: !compact,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Opacity(
                        opacity: t,
                        child: Row(
                          children: [
                            Semantics(
                              button: true,
                              label: 'Back to stories',
                              onTap: controller.clearSearch,
                              excludeSemantics: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                onTap: controller.clearSearch,
                                child: SizedBox(
                                  width: _backWidth,
                                  height: _small + AppSpacing.sm,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.web_stories_outlined, size: 22, color: AppColors.primary),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Stories',
                                        maxLines: 1,
                                        // A tiny label in a fixed-size button: it grows with the system text size, but not past 1.2x.
                                        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                                        style: textTheme.labelSmall?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 34,
                              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                              color: AppColors.hairline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: rings.length + loading,
                    separatorBuilder: (_, _) => SizedBox(width: AppSpacing.md - (AppSpacing.md - AppSpacing.sm) * t),
                    itemBuilder: (context, i) {
                      final itemWidth = size + AppSpacing.sm * labelFold;

                      // A ring that is still on its way: grey, with an arc running round it.
                      if (i >= rings.length) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: SizedBox(
                            key: ValueKey('loading$i'),
                            width: itemWidth,
                            child: Column(
                              children: [
                                _RingFrame(
                                  size: size,
                                  lit: true,
                                  spinning: true,
                                  phase: i * 0.12,
                                  child: const ColoredBox(color: AppColors.parchment),
                                ),
                                label(
                                  Container(
                                    width: size * 0.55,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.parchment,
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final ring = rings[i];
                      final seen = stories.isSeen(ring);
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Builder(
                          key: ValueKey(ring.key),
                          builder: (itemContext) {
                            void open() {
                              final box = itemContext.findRenderObject() as RenderBox?;
                              Offset? origin;
                              if (box != null && box.attached) {
                                final topLeft = box.localToGlobal(Offset.zero);
                                origin = Offset(topLeft.dx + box.size.width / 2, topLeft.dy + size / 2);
                              }
                              openStories(context, rings, i, origin: origin, originRadius: size / 2);
                            }

                            return Semantics(
                              button: true,
                              label: '${ring.title}, ${seen ? 'story seen' : 'new story'}',
                              onTap: open,
                              onLongPress: () => _ringMenu(context, stories, ring),
                              excludeSemantics: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                onLongPress: () => _ringMenu(context, stories, ring),
                                onTap: open,
                                child: SizedBox(
                                  width: itemWidth,
                                  child: Column(
                                    children: [
                                      StoryAvatar(ring: ring, size: size, lit: !seen),
                                      label(
                                        Text(
                                          ring.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: seen ? AppColors.ink48 : AppColors.ink80,
                                            fontWeight: seen ? FontWeight.w400 : FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The button that asks for new stories: a pill with a border in the colours of the rings, a small refresh mark and
/// the word "Refresh". While it works the mark becomes a small spinner.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({super.key, required this.refreshing, required this.onTap});

  final bool refreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Refresh stories',
      onTap: refreshing ? null : onTap,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          gradient: const SweepGradient(
            colors: [AppColors.primary, AppColors.mediaAccent, AppColors.honey, AppColors.primary],
            stops: [0.0, 0.4, 0.75, 1.0],
          ),
        ),
        child: Material(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: refreshing ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    refreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      refreshing ? 'Looking' : 'Refresh',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// What a long press on a ring offers: setting it aside for a while.
Future<void> _ringMenu(BuildContext context, StoriesController stories, StoryRing ring) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Not now'),
            subtitle: Text('Leave ${ring.title} out of your stories for ${StoriesController.mutedDays} days'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              stories.setAside(ring);
            },
          ),
        ],
      ),
    ),
  );
}

/// A person's face or a collection's cover inside a ring: coloured while there is something not
/// seen ([lit]), grey after, like the rings of a stories bar. [forceSpin] runs an arc round it
/// (while a story is being found, say); a collection's ring does that by itself until its cover
/// is there.
class StoryAvatar extends StatelessWidget {
  const StoryAvatar({super.key, required this.ring, required this.size, this.lit = true, this.forceSpin = false});

  final StoryRing ring;
  final double size;
  final bool lit;
  final bool forceSpin;

  @override
  Widget build(BuildContext context) {
    if (ring.kind == StoryKind.person) {
      return _RingFrame(
        size: size,
        lit: lit,
        spinning: forceSpin,
        child: FaceAvatar(faceId: ring.person!.coverFaceId, size: size),
      );
    }
    return _CollectionAvatar(ring: ring, size: size, lit: lit, forceSpin: forceSpin);
  }
}

// A collection's cover in its ring. Nothing loads it beforehand, so this asks for its own (small) cover, and the
// ring runs until it is there.
class _CollectionAvatar extends StatefulWidget {
  const _CollectionAvatar({required this.ring, required this.size, required this.lit, required this.forceSpin});

  final StoryRing ring;
  final double size;
  final bool lit, forceSpin;

  @override
  State<_CollectionAvatar> createState() => _CollectionAvatarState();
}

class _CollectionAvatarState extends State<_CollectionAvatar> {
  // The cover could not be had (it has none, or it cannot be read): the icon stays and the ring stops.
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    Get.find<CollectionsController>().loadCover(widget.ring.collection!.id, 240).then((bytes) {
      if (bytes == null && mounted) setState(() => _gaveUp = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CollectionsController>(
      builder: (collections) {
        final bytes = collections.coverFor(widget.ring.collection!.id);
        return _RingFrame(
          size: widget.size,
          lit: widget.lit,
          spinning: widget.forceSpin || (bytes == null && !_gaveUp),
          child: bytes == null
              ? ColoredBox(
                  color: AppColors.parchment,
                  child: Icon(widget.ring.collection!.icon, size: 26, color: AppColors.primary),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Fixed, not the ring's size: the ring changes size while it shrinks and grows, and a new
                  // decode size each frame would decode it again each frame.
                  cacheWidth: 210,
                  excludeFromSemantics: true,
                ),
        );
      },
    );
  }
}

/// The ring and the picture inside it. [spinning]: a coloured arc with a fading tail runs round it
/// (the colours of the lit ring, head in gold) instead of the still ring; [phase] sets where in the
/// turn it starts (0 to 1), so several can follow one another.
class _RingFrame extends StatefulWidget {
  const _RingFrame({
    required this.size,
    required this.lit,
    required this.spinning,
    required this.child,
    this.phase = 0,
  });

  final double size;
  final bool lit, spinning;
  final double phase;
  final Widget child;

  @override
  State<_RingFrame> createState() => _RingFrameState();
}

class _RingFrameState extends State<_RingFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _RingFrame old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final stroke = size >= 60 ? 3.0 : 2.5;
    final gap = size >= 60 ? 3.0 : 2.5;
    final inner = size - 2 * (stroke + gap);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The arc is a layer of its own: while it runs, the picture inside is not drawn again.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RingPainter(
                  lit: widget.lit,
                  stroke: stroke,
                  spin: widget.spinning ? _spin : null,
                  phase: widget.phase,
                ),
              ),
            ),
          ),
          ClipOval(
            child: SizedBox(width: inner, height: inner, child: widget.child),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.lit, required this.stroke, this.spin, this.phase = 0}) : super(repaint: spin);

  final bool lit;
  final double stroke;
  final Animation<double>? spin;
  final double phase;

  static const List<Color> _colors = [AppColors.primary, AppColors.mediaAccent, AppColors.honey, AppColors.primary];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;

    final turning = spin;
    if (turning != null) {
      // A faint track, and over it an arc with a tail that fades behind and a bright head in front.
      canvas.drawCircle(centre, radius, paint..color = AppColors.hairline);
      paint
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0),
            AppColors.primary,
            AppColors.mediaAccent,
            AppColors.honey,
            AppColors.honey.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.3, 0.55, 0.78, 0.8],
          transform: GradientRotation((turning.value + phase) * 2 * math.pi),
        ).createShader(rect);
      canvas.drawCircle(centre, radius, paint);
      return;
    }

    if (lit) {
      paint.shader = const SweepGradient(
        colors: _colors,
        stops: [0.0, 0.4, 0.75, 1.0],
        transform: GradientRotation(math.pi * 0.55),
      ).createShader(rect);
    } else {
      paint.color = AppColors.hairline;
    }
    canvas.drawCircle(centre, radius, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.lit != lit || old.stroke != stroke || old.spin != spin || old.phase != phase;
}
