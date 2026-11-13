import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_palette.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_download.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_samples.dart';
import 'package:lost_and_found/features/tour/view/widgets/tour_widgets.dart';
part 'tour_screen/download_card.dart';
part 'tour_screen/ring.dart';
part 'tour_screen/download_chip.dart';
part 'tour_screen/pause_button.dart';
part 'tour_screen/main_button.dart';

/// A tour: pages to swipe through, a download card that tucks into a small chip, a close button (when replayed from
/// Help), and one button at the bottom whose words follow the page and the download. Built to take any list of
/// pages, so a "What's new" for a later version can be another list.
class TourScreen extends StatefulWidget {
  const TourScreen({
    super.key,
    required this.pages,
    required this.download,
    required this.onFinished,
    this.mode = TourMode.firstRun,
  });

  final List<TourPage> pages;
  final TourDownload download;

  /// The last button was pressed, or the tour replayed from Help was closed.
  final VoidCallback onFinished;
  final TourMode mode;

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  /// How long the download card stays open once the download is going, before it tucks into the chip.
  static const Duration _cardTime = Duration(milliseconds: 4500);

  final PageController _controller = PageController();
  int _index = 0;

  /// Whether the download card is showing (else only the chip, if there is a download to show).
  bool _cardOpen = false;
  Timer? _tuck;
  DateTime? _openedAt;
  TourDownloadPhase _phase = TourDownloadPhase.idle;

  bool get _help => widget.mode == TourMode.help;
  bool get _last => _index == widget.pages.length - 1;

  /// The tour is made for a portrait phone, so it stays upright whichever way the phone is held.
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    widget.download.addListener(_onDownload);
    _onDownload();
  }

  @override
  void didUpdateWidget(covariant TourScreen old) {
    super.didUpdateWidget(old);
    if (old.download != widget.download) {
      old.download.removeListener(_onDownload);
      widget.download.addListener(_onDownload);
    }
  }

  /// The rest of the app turns with the phone again.
  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    widget.download.removeListener(_onDownload);
    _tuck?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The card opens when the download starts, or when it needs the person (stopped or paused, so it stays down). It
  /// tucks away a few seconds after a download starts, and for good once it has finished.
  void _onDownload() {
    final state = widget.download.state;
    final was = _phase;
    if (state.phase == was) return;
    _phase = state.phase;
    switch (state.phase) {
      case TourDownloadPhase.connecting:
      case TourDownloadPhase.downloading:
      case TourDownloadPhase.verifying:
        if (!(was == TourDownloadPhase.connecting ||
            was == TourDownloadPhase.downloading ||
            was == TourDownloadPhase.verifying)) {
          _open(tuckAfter: _cardTime);
        }
      case TourDownloadPhase.error:
      case TourDownloadPhase.paused:
        _open();
      case TourDownloadPhase.done:
      case TourDownloadPhase.idle:
        _close();
    }
  }

  void _open({Duration? tuckAfter}) {
    _tuck?.cancel();
    _openedAt = DateTime.now();
    if (tuckAfter != null) _tuck = Timer(tuckAfter, _close);
    if (mounted) setState(() => _cardOpen = true);
  }

  void _close() {
    _tuck?.cancel();
    if (mounted && _cardOpen) setState(() => _cardOpen = false);
  }

  /// The chip was tapped: the card comes back down, as it did when the download started, and tucks away again after
  /// a few seconds, unless it is waiting for the person.
  void _reopenCard() {
    final waiting =
        widget.download.state.phase == TourDownloadPhase.paused ||
        widget.download.state.phase == TourDownloadPhase.error;
    _open(tuckAfter: waiting ? null : _cardTime);
  }

  void _goTo(int page) {
    if (page < 0 || page >= widget.pages.length) return;
    if (calm(context)) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() => _goTo(_index + 1);

  /// Handles the main button. The state is read when pressed, not when the button was built, because a second press
  /// before the page has turned must not start the download again. The first button starts the download and the tour
  /// together.
  void _onMainButton() {
    final state = widget.download.state;
    HapticFeedback.selectionClick();
    if (_index == 0) {
      if (!state.running && !state.done) widget.download.start();
      _next();
      return;
    }
    if (!_last) {
      _next();
      return;
    }
    if (_help) {
      widget.onFinished();
      return;
    }
    if (state.done) {
      widget.onFinished();
    } else if (!state.running) {
      widget.download.start();
    }
  }

  /// Back goes to the page before, and from the first page it leaves (the app, or Help). The chip and the buttons
  /// follow the download, which changes many times a second, so only these are rebuilt for it, never the pages, which
  /// hold demos that animate by themselves. Moving on to another page is a sign it has been seen, so the card tucks
  /// away unless it is asking for something. The first-run tour is gone through to its end because it sets the app
  /// up, while the one replayed from Help can be closed at any time.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_index - 1);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: AppColors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: TourPalette.bottom,
          systemNavigationBarDividerColor: TourPalette.bottom,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          backgroundColor: TourPalette.bottom,
          body: TourBackground(
            child: SafeArea(
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: widget.download,
                    builder: (context, _) => BarTextScale(
                      child: _topBar(textTheme, widget.download.state),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.pages.length,
                      onPageChanged: (i) {
                        setState(() => _index = i);
                        final shown = _openedAt;
                        if (widget.download.state.running &&
                            shown != null &&
                            DateTime.now().difference(shown) >
                                const Duration(seconds: 2)) {
                          _close();
                        }
                      },
                      itemBuilder: (context, i) => _KeepPage(
                        child: widget.pages[i].builder(
                          context,
                          TourPageScope(
                            index: i,
                            active: i == _index,
                            download: widget.download,
                            next: _next,
                            help: _help,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.download,
                    builder: (context, _) => BarTextScale(
                      child: _bottom(textTheme, widget.download.state),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(TextTheme textTheme, TourDownloadState state) {
    final showChip =
        !_cardOpen &&
        (state.running || state.paused || state.done) &&
        !(state.phase == TourDownloadPhase.idle);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.7,
                        end: 1,
                      ).animate(animation),
                      alignment: Alignment.centerLeft,
                      child: child,
                    ),
                  ),
                  child: showChip
                      ? _DownloadChip(
                          key: const ValueKey('chip'),
                          state: state,
                          onTap: state.done ? null : _reopenCard,
                        )
                      : const SizedBox(key: ValueKey('nochip')),
                ),
              ),
            ),
            if (_help)
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: TourPalette.text),
                onPressed: widget.onFinished,
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _bottom(TextTheme textTheme, TourDownloadState state) {
    final showCard =
        _cardOpen && state.phase != TourDownloadPhase.idle && !state.done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.5),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: showCard
                    ? Padding(
                        key: const ValueKey('card'),
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _DownloadCard(
                          download: widget.download,
                          state: state,
                          onMinimise: _close,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('nocard'),
                        width: double.infinity,
                      ),
              ),
            ),
            _Dots(count: widget.pages.length, index: _index),
            if (_index == 0 && !_help && !state.running && !state.done) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'To make your media searchable, the app needs to download an offline model. This is a one-time download. After that, everything works without an internet connection.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: TourPalette.text80,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _MainButton(
              label: _label(state),
              enabled: _enabled(state),
              onTap: _onMainButton,
            ),
          ],
        ),
      ),
    );
  }

  String _label(TourDownloadState state) {
    if (_index == 0) {
      final size = state.totalLabel;
      return size.isEmpty || state.running || state.done
          ? 'Get started'
          : 'Get started  ·  $size';
    }
    if (!_last) return 'Next';
    if (_help) return 'Done';
    if (state.done) return 'Open the app';
    if (state.running) return 'Almost ready, ${state.percent}%';
    if (state.paused) return 'Resume download  ·  ${state.percent}%';
    final size = state.totalLabel;
    return size.isEmpty ? 'Download' : 'Download  ·  $size';
  }

  bool _enabled(TourDownloadState state) {
    if (!_last || _help) return true;
    return !state.running;
  }
}

/// One page of a tour: whatever it draws, given where the tour is.
class TourPage {
  const TourPage(this.builder);

  final Widget Function(BuildContext context, TourPageScope scope) builder;
}

/// What a page of the tour is told about the tour around it.
class TourPageScope {
  const TourPageScope({
    required this.index,
    required this.active,
    required this.download,
    required this.next,
    required this.help,
  });

  final int index;

  /// Whether this is the page on screen (a page starts its animation when it becomes so).
  final bool active;
  final TourDownload download;

  /// Goes on to the next page.
  final VoidCallback next;

  /// Opened from Settings > App tour rather than on a first run.
  final bool help;
}

enum TourMode { firstRun, help }

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? TourPalette.teal : TourPalette.slate250,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps a page alive when it is swiped away, so coming back does not start its demo again from nothing.
class _KeepPage extends StatefulWidget {
  const _KeepPage({required this.child});

  final Widget child;

  @override
  State<_KeepPage> createState() => _KeepPageState();
}

class _KeepPageState extends State<_KeepPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
