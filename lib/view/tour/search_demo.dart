import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart'
    show bentoRects;

/// The search, playing by itself on the sample photos: a query is typed into the bar and the photos move into
/// the order of how well they match, the best one biggest; then the next query. The order is prepared ahead
/// (see [kSampleQueries]); nothing is searched, and nothing here can be touched - it only shows.
///
/// By default it goes through the queries one after another while its page is showing. With [autoplay] off it
/// only runs the query asked for through [runRequests] (the page decides when).
class TourSearchDemo extends StatefulWidget {
  const TourSearchDemo({
    super.key,
    required this.active,
    this.height = 300,
    this.startWith = 0,
    this.autoplay = true,
    this.caption = 'Demo with sample photos',
    this.runRequests,
  });

  /// Whether the page showing it is the current one (it plays while it is).
  final bool active;
  final double height;

  /// The query it begins with.
  final int startWith;
  final bool autoplay;
  final String caption;

  /// When this changes the demo runs the query with that number (modulo how many there are).
  final ValueListenable<int>? runRequests;

  @override
  State<TourSearchDemo> createState() => _TourSearchDemoState();
}

class _TourSearchDemoState extends State<TourSearchDemo> {
  static const int _shown = 7;
  static const Duration _letter = Duration(milliseconds: 70);
  static const Duration _rest = Duration(milliseconds: 3000);

  String _typed = '';
  bool _typing = false;
  bool _matched = false;

  // The "@" demo: the people list is open (narrowed by what follows the "@"), the name is being chosen,
  // and the name has become a pick in the bar.
  bool _menu = false;
  bool _choosing = false;
  int _pickLength = 0;

  // The photos in the order they are shown.
  List<String> _order = [for (final p in kSamplePhotos) p.id];

  // Which play is the current one: a play that is no longer it stops where it is.
  int _generation = 0;
  int _next = 0;

  @override
  void initState() {
    super.initState();
    _next = widget.startWith;
    widget.runRequests?.addListener(_requested);
    _startIfActive();
  }

  @override
  void didUpdateWidget(covariant TourSearchDemo old) {
    super.didUpdateWidget(old);
    if (widget.runRequests != old.runRequests) {
      old.runRequests?.removeListener(_requested);
      widget.runRequests?.addListener(_requested);
    }
    if (widget.active && !old.active) {
      _startIfActive();
    } else if (!widget.active && old.active) {
      _generation++;
    }
  }

  @override
  void dispose() {
    widget.runRequests?.removeListener(_requested);
    _generation++;
    super.dispose();
  }

  void _startIfActive() {
    if (!widget.active || !widget.autoplay) return;
    unawaited(_loop(++_generation));
  }

  void _requested() {
    if (!mounted) return;
    final index = (widget.runRequests?.value ?? 0) % kSampleQueries.length;
    unawaited(_play(index, ++_generation));
  }

  bool _stale(int generation) => !mounted || generation != _generation;

  Future<void> _loop(int generation) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    while (!_stale(generation)) {
      await _play(_next % kSampleQueries.length, generation);
      if (_stale(generation)) return;
      await Future<void>.delayed(_rest);
      _next++;
    }
  }

  Future<void> _playMention(SampleQuery query, int generation) async {
    final name = query.mention!.name;
    setState(() {
      _typed = '';
      _typing = true;
      _matched = false;
      _menu = false;
      _choosing = false;
      _pickLength = 0;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // "@", then the first letters of the name: the list opens and narrows.
    for (var n = 0; n <= 2; n++) {
      if (_stale(generation)) return;
      setState(() {
        _typed = '@${name.substring(0, n)}';
        _menu = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    if (_stale(generation)) return;
    setState(() => _choosing = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (_stale(generation)) return;
    final pick = '@$name';
    setState(() {
      _typed = pick;
      _menu = false;
      _choosing = false;
      _pickLength = pick.length;
    });
    // The rest of the sentence, typed after the pick.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    for (var n = pick.length + 1; n <= query.text.length; n++) {
      await Future<void>.delayed(_letter);
      if (_stale(generation)) return;
      setState(() => _typed = query.text.substring(0, n));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_stale(generation)) return;
    setState(() {
      _order = query.order;
      _typing = false;
      _matched = true;
    });
  }

  Future<void> _play(int index, int generation) async {
    final query = kSampleQueries[index];
    if (query.mention != null) return _playMention(query, generation);
    setState(() {
      _typed = '';
      _typing = true;
      _matched = false;
      _menu = false;
      _choosing = false;
      _pickLength = 0;
    });
    for (var n = 1; n <= query.text.length; n++) {
      await Future<void>.delayed(_letter);
      if (_stale(generation)) return;
      setState(() => _typed = query.text.substring(0, n));
    }
    // A beat after the last letter, like pressing search.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_stale(generation)) return;
    setState(() {
      _order = query.order;
      _typing = false;
      _matched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // One line for a screen reader instead of dozens of photos moving about.
    return Semantics(
      label:
          'Demo: a search is typed and the photos that match move to the front',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: FixedTextScale(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TourSearchBar(
                      text: _typed,
                      typing: _typing,
                      pickLength: _pickLength,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: widget.height,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final area = Size(box.maxWidth, box.maxHeight);
                          final rects = bentoRects(_shown, area, gap: 6);
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final photo in kSamplePhotos)
                                _tile(photo, rects, area),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      widget.caption,
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                        color: kTourText60,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: AppSpacing.sm,
                  top: 52,
                  child: _MentionList(
                    open: _menu,
                    filter: _typed.startsWith('@') ? _typed.substring(1) : '',
                    choosing: _choosing,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(SamplePhoto photo, List<Rect> rects, Size area) {
    final rank = _order.indexOf(photo.id);
    final visible = rank >= 0 && rank < _shown;
    final rect = visible
        ? rects[rank]
        : Rect.fromCenter(
            center: area.center(Offset.zero),
            width: 40,
            height: 40,
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  photo.asset,
                  fit: BoxFit.cover,
                  alignment: photo.focus,
                  cacheWidth: 600,
                  semanticLabel: photo.label,
                  gaplessPlayback: true,
                ),
                // A video plays its four seconds over and over, without sound, while it is on screen.
                if (photo.video)
                  _VideoLoop(
                    asset: photo.videoAsset,
                    play: visible && widget.active,
                  ),
                if (photo.video)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                if (visible && rank == 0 && _matched)
                  const Positioned(left: 8, bottom: 8, child: TourBestMatch()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tour's search bar: a white pill with a hairline edge and a soft shadow, a placeholder, a caret and a ring of light
/// while it is being used, and a round button that is pressed to search. By default it follows [typing] and [text]; the
/// film on page 4, which drives it by its own clock, sets [caret], [focus], [ready] and [press] itself.
class TourSearchBar extends StatelessWidget {
  const TourSearchBar({
    super.key,
    required this.text,
    required this.typing,
    this.pickLength = 0,
    this.caret,
    this.focus,
    this.ready,
    this.press = 0,
  });

  final String text;
  final bool typing;

  /// How many of the first letters are a picked person (shown as the app shows one: bold, in the app's colour).
  final int pickLength;

  /// Whether the caret shows (by default: while typing), how much the ring of light shows (by default: while typing),
  /// how much the button is lit (by default: once there is something typed and it is not being typed), and how far the
  /// button is pressed in.
  final bool? caret;
  final double? focus;
  final double? ready;
  final double press;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final ring = focus ?? (typing ? 1.0 : 0.0);
    final lit = ready ?? (text.isEmpty || typing ? 0.0 : 1.0);
    final showCaret = caret ?? typing;
    final empty = text.isEmpty;
    final base = style?.copyWith(
      fontSize: empty ? 14.5 : 16,
      fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
      color: empty ? AppColors.ink48 : AppColors.ink,
      letterSpacing: -0.1,
    );
    return SizedBox(
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Color.lerp(
              const Color(0x14102220),
              AppColors.primary.withValues(alpha: 0.55),
              ring,
            )!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF102220,
              ).withValues(alpha: 0.10 + 0.04 * ring),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.16 * ring),
              blurRadius: 18,
            ),
            BoxShadow(
              color: const Color(0xFF102220).withValues(alpha: 0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x12165E59),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (empty)
                            const TextSpan(
                              text: 'Describe a photo you remember',
                            )
                          else if (pickLength > 0) ...[
                            TextSpan(
                              text: text.substring(0, pickLength),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: text.substring(pickLength)),
                          ] else
                            TextSpan(text: text),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: base,
                    ),
                  ),
                  if (showCaret)
                    Container(
                      width: 1.6,
                      height: 20,
                      margin: const EdgeInsets.only(left: 2),
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1 - 0.14 * press,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.28 + 0.72 * lit),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list that opens under the bar after an "@": the people whose names hold what was typed after it, with the
/// one being chosen marked.
class _MentionList extends StatelessWidget {
  const _MentionList({
    required this.open,
    required this.filter,
    required this.choosing,
  });

  final bool open;
  final String filter;
  final bool choosing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final people = [
      for (final p in kMentionPeople)
        if (p.name.toLowerCase().contains(filter.toLowerCase())) p,
    ];
    return AnimatedOpacity(
      opacity: open && people.isNotEmpty ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Material(
        elevation: 8,
        shadowColor: AppColors.ink.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: Colors.white,
        child: SizedBox(
          width: 230,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in people)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: choosing && people.length == 1
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            p.face,
                            width: 30,
                            height: 30,
                            fit: BoxFit.cover,
                            cacheWidth: 90,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          p.name,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                      ],
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

class TourBestMatch extends StatelessWidget {
  const TourBestMatch({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Best match',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A short clip looping without sound over its still. Only holds a player while it is [play]ing (a decoder for
/// a tile that is not on screen is a waste); if the clip cannot be played the still stays.
class _VideoLoop extends StatefulWidget {
  const _VideoLoop({required this.asset, required this.play});

  final String asset;
  final bool play;

  @override
  State<_VideoLoop> createState() => _VideoLoopState();
}

class _VideoLoopState extends State<_VideoLoop> {
  VideoPlayerController? _controller;
  bool _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _VideoLoop old) {
    super.didUpdateWidget(old);
    if (widget.play != old.play) _sync();
  }

  void _sync() {
    if (widget.play && _controller == null) {
      unawaited(_start(++_generation));
    } else if (!widget.play && _controller != null) {
      _generation++;
      _release();
    }
  }

  Future<void> _start(int generation) async {
    final controller = VideoPlayerController.asset(
      widget.asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        if (identical(_controller, controller)) _controller = null;
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      // The tile may have gone while the player was being set up.
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
    } catch (_) {
      // No player here (or the clip is not playable): the still stays.
      if (identical(_controller, controller)) _controller = null;
      await controller.dispose();
    }
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    _ready = false;
    if (controller != null) unawaited(controller.dispose());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
