import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/tour/tour_download.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

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

  /// Opened from Settings > Help rather than on a first run.
  final bool help;
}

/// One page of a tour: whatever it draws, given where the tour is.
class TourPage {
  const TourPage(this.builder);

  final Widget Function(BuildContext context, TourPageScope scope) builder;
}

enum TourMode { firstRun, help }

/// A tour: pages to swipe through, a download card that tucks into a small chip, a skip button, and one button
/// at the bottom whose words follow the page and the download. Built to take any list of pages, so a
/// "What's new" for a later version can be another list.
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

  /// The last button was pressed, or the tour was skipped.
  final VoidCallback onFinished;
  final TourMode mode;

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  // How long the download card stays open once the download is going, before it tucks into the chip.
  static const Duration _cardTime = Duration(milliseconds: 4500);

  final PageController _controller = PageController();
  int _index = 0;

  // Whether the download card is showing (else only the chip, if there is a download to show).
  bool _cardOpen = false;
  Timer? _tuck;
  DateTime? _openedAt;
  TourDownloadPhase _phase = TourDownloadPhase.idle;

  bool get _help => widget.mode == TourMode.help;
  bool get _last => _index == widget.pages.length - 1;

  @override
  void initState() {
    super.initState();
    // The tour is made for a portrait phone: it stays upright, whichever way the phone is held.
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

  @override
  void dispose() {
    // The rest of the app turns with the phone, as it did before the tour.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    widget.download.removeListener(_onDownload);
    _tuck?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // The card opens when the download starts, or when it needs the person (stopped); it tucks
  // away a few seconds after a download starts, and for good once it has finished.
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
        // Both wait for the person, so the card stays down.
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

  // The chip was tapped: the card comes back down, as it did when the download started (and tucks away again after
  // a few seconds, unless it is waiting for the person).
  void _reopenCard() {
    final waiting =
        widget.download.state.phase == TourDownloadPhase.paused ||
        widget.download.state.phase == TourDownloadPhase.error;
    _open(tuckAfter: waiting ? null : _cardTime);
  }

  void _goTo(int page) {
    if (page < 0 || page >= widget.pages.length) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() => _goTo(_index + 1);

  void _onMainButton() {
    // Read when pressed, not when the button was built: a second press before the page has turned must not
    // start the download again.
    final state = widget.download.state;
    HapticFeedback.selectionClick();
    if (_index == 0) {
      // The first button starts the download and the tour together.
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      // Back goes to the page before; from the first page it leaves (the app, or Help).
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_index - 1);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // The background is light: dark icons in the bars, and the bottom bar in its colour.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: kTourBottom,
          systemNavigationBarDividerColor: kTourBottom,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          backgroundColor: kTourBottom,
          body: TourBackground(
            child: SafeArea(
              child: Column(
                children: [
                  // The chip and the buttons follow the download, which changes many times a second: only
                  // these are rebuilt for it, never the pages (they hold demos that animate by themselves).
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
                        // Moving on to another page is a sign it has been seen: the card tucks away (unless
                        // it is asking for something).
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
                          simulated: widget.download.simulated,
                          // Done has nothing more to show.
                          onTap: state.done ? null : _reopenCard,
                        )
                      : const SizedBox(key: ValueKey('nochip')),
                ),
              ),
            ),
            if (_help)
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: kTourText),
                onPressed: widget.onFinished,
              )
            else if (!_last)
              TextButton(
                onPressed: widget.onFinished,
                child: Text(
                  'Skip',
                  style: textTheme.labelLarge?.copyWith(color: kTourText80),
                ),
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
            if (_index == 0 && !state.running && !state.done) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'To make your media searchable, the app needs to download a model that works offline. It’s what makes searching on your phone possible.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: kTourText80,
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

String _size(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}

/// The progress as a ring: filling up, or going round while it is not a number yet.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, this.size = 30});

  /// 0 to 1, or null for "working".
  final double? value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: size > 22 ? 3 : 2.4,
        valueColor: const AlwaysStoppedAnimation<Color>(kTourAccent),
        backgroundColor: Colors.black.withValues(alpha: 0.09),
        strokeCap: StrokeCap.round,
      ),
    );
  }
}

/// Where the download is, small: a ring and the percentage, level with Skip.
class _DownloadChip extends StatelessWidget {
  const _DownloadChip({
    super.key,
    required this.state,
    required this.simulated,
    this.onTap,
  });

  final TourDownloadState state;
  final bool simulated;

  /// Brings the card back down.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final prefix = simulated ? 'Demo  ' : '';
    final String text;
    switch (state.phase) {
      case TourDownloadPhase.done:
        text = '${prefix}Ready';
      case TourDownloadPhase.verifying:
        text = '${prefix}Checking';
      case TourDownloadPhase.connecting:
        text = '${prefix}Starting';
      case TourDownloadPhase.paused:
        text = '${prefix}Paused  ·  ${state.percent}%';
      default:
        text = '$prefix${state.percent}%';
    }
    final double? ring = switch (state.phase) {
      TourDownloadPhase.connecting || TourDownloadPhase.verifying => null,
      _ => state.fraction,
    };
    final chip = Semantics(
      label: onTap == null
          ? 'Download: $text'
          : 'Download: $text. Tap to show details',
      excludeSemantics: true,
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: 8, right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: kTourLine),
          boxShadow: kTourSoftShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (state.done)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: kTourAccent,
              )
            else if (state.paused)
              const Icon(
                Icons.pause_circle_filled_rounded,
                size: 18,
                color: kTourAccent,
              )
            else
              _Ring(value: ring, size: 18),
            const SizedBox(width: 7),
            Text(
              text,
              style: textTheme.labelMedium?.copyWith(
                color: kTourText,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    // The tap reaches past the small chip, to the height of the bar it sits in.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: chip,
        ),
      ),
    );
  }
}

/// The download, with the details: it opens when the download starts and when it needs the person, tucks into the
/// chip after a few seconds (tap the chip to bring it back), and has the button that pauses and resumes it. A tap on
/// the rest of the card tucks it away.
class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.download,
    required this.state,
    required this.onMinimise,
  });

  final TourDownload download;
  final TourDownloadState state;
  final VoidCallback onMinimise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final prefix = download.simulated ? 'Demo  ·  ' : '';
    final String title, detail;
    String? action;
    switch (state.phase) {
      case TourDownloadPhase.error:
        title = 'Download stopped';
        detail = 'Check your connection';
        action = 'Try again';
      case TourDownloadPhase.connecting:
        title = 'Starting the download';
        detail = 'Connecting to the server';
      case TourDownloadPhase.verifying:
        title = 'Checking the download';
        detail = 'Almost ready';
      case TourDownloadPhase.paused:
        title = 'Download paused';
        detail =
            '$prefix${state.percent}%  ·  ${_size(state.downloadedBytes)} of ${_size(state.totalBytes)}';
      default:
        title = 'Downloading search models';
        detail =
            '$prefix${state.percent}%  ·  ${_size(state.downloadedBytes)} of ${_size(state.totalBytes)}';
    }
    final Widget lead;
    switch (state.phase) {
      case TourDownloadPhase.error:
        lead = const Icon(
          Icons.error_outline_rounded,
          size: 26,
          color: Color(0xFFB14032),
        );
      case TourDownloadPhase.connecting || TourDownloadPhase.verifying:
        lead = const _Ring(value: null);
      default:
        lead = _Ring(value: state.fraction);
    }
    // Pausing is offered while bytes are coming (or being asked for); resuming while it is paused.
    final canPause =
        state.phase == TourDownloadPhase.downloading ||
        state.phase == TourDownloadPhase.connecting;
    return Semantics(
      liveRegion: true,
      label: '$prefix$title. $detail',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onMinimise,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg + 2),
            border: Border.all(color: kTourLine),
            boxShadow: kTourSoftShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 30, height: 30, child: Center(child: lead)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: kTourText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: kTourText60,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (canPause || state.paused) ...[
                const SizedBox(width: 6),
                _PauseButton(
                  paused: state.paused,
                  onTap: state.paused ? download.resume : download.pause,
                ),
              ],
              if (action != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: download.start,
                  style: TextButton.styleFrom(
                    foregroundColor: kTourAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    action,
                    style: textTheme.labelLarge?.copyWith(
                      color: kTourAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A round button that pauses the download, or - when it is paused - carries on with it.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.paused, required this.onTap});

  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: paused ? 'Resume download' : 'Pause download',
      excludeSemantics: true,
      child: Tooltip(
        message: paused ? 'Resume' : 'Pause',
        child: Material(
          color: paused ? kTourAccent : kTourAccent.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  key: ValueKey(paused),
                  size: 24,
                  color: paused ? Colors.white : kTourAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                color: i == index ? kTourAccent : const Color(0xFFB8C8C4),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: kTourAccent,
          elevation: 0,
          shadowColor: kTourAccent.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
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
