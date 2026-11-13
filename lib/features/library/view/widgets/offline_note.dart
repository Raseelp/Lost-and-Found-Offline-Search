import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';

/// The note above the scan card: what the scan is for and that it all stays on the phone. It opens the Your data page.
///
/// Before a scan it says it in full. While a scan runs it shrinks to its title and a button, and a soft band of light
/// sweeps across it, so it feels like part of the scan. The title keeps its place and size through the change, and what
/// is under it grows and fades away.
class OfflineNote extends StatefulWidget {
  const OfflineNote({super.key, required this.compact, required this.onOpen});

  /// Whether to show the short version.
  final bool compact;
  final VoidCallback onOpen;

  static const title = 'Making your media searchable';

  @override
  State<OfflineNote> createState() => _OfflineNoteState();
}

class _OfflineNoteState extends State<OfflineNote> with TickerProviderStateMixin {
  /// The band of light that sweeps across the short note, and the rings that breathe out of the icons of the full one.
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final AnimationController _rings = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  /// Changes each time the full note comes back, so its lines rise in again.
  int _shown = 0;

  @override
  void didUpdateWidget(covariant OfflineNote old) {
    super.didUpdateWidget(old);
    if (old.compact && !widget.compact) _shown++;
    _follow();
  }

  void _follow() {
    if (widget.compact) {
      _rings.stop();
      loopUnlessCalm(context, _sweep);
    } else {
      _sweep.stop();
      loopUnlessCalm(context, _rings);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final text = Theme.of(context).textTheme;
    final roomy = MediaQuery.textScalerOf(context).scale(15) > 20;
    final titleText = compact
        ? _DottedTitle(animation: _sweep, style: text.titleSmall)
        : Text(OfflineNote.title, style: text.titleSmall);
    final title = roomy ? titleText : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: titleText);

    return Semantics(
      button: true,
      label: compact ? '${OfflineNote.title}. See how.' : '${OfflineNote.title}. Your data.',
      excludeSemantics: true,
      onTap: widget.onOpen,
      child: Material(
        color: AppColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedOpacity(
                      opacity: compact ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) => CustomPaint(painter: _SweepPainter(_sweep.value)),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.base),
                      child: roomy
                          ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpacing.xs, children: [title, _SeeHow(show: compact)])
                          : Row(
                              children: [
                                Expanded(child: Align(alignment: Alignment.centerLeft, child: title)),
                                _SeeHow(show: compact),
                              ],
                            ),
                    ),
                    AnimatedCrossFade(
                      duration: calm(context) ? const Duration(milliseconds: 1) : const Duration(milliseconds: 320),
                      sizeCurve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      crossFadeState: compact ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      firstChild: _Body(key: ValueKey(_shown), rings: _rings),
                      secondChild: const SizedBox(width: double.infinity),
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

/// The title with dots after it that count up while a scan runs: none, one, two, three, and again from none. The dots that
/// are not showing still take their room, so the title does not move. [animation] is the sweep of the short note, which
/// goes round twice for each pass of the dots through their four steps. With motion off all three dots stay.
class _DottedTitle extends StatefulWidget {
  const _DottedTitle({required this.animation, required this.style});

  final Animation<double> animation;
  final TextStyle? style;

  @override
  State<_DottedTitle> createState() => _DottedTitleState();
}

class _DottedTitleState extends State<_DottedTitle> {
  static const _dots = 3;
  static const _stepsPerLoop = 8;

  int _shown = 0;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_follow);
  }

  @override
  void didUpdateWidget(covariant _DottedTitle old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeListener(_follow);
      widget.animation.addListener(_follow);
    }
  }

  void _follow() {
    final next = (widget.animation.value * _stepsPerLoop).floor() % (_dots + 1);
    if (next != _shown) setState(() => _shown = next);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_follow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = calm(context) ? _dots : _shown;
    final hidden = (widget.style?.color ?? AppColors.ink).withValues(alpha: 0);
    return Text.rich(
      TextSpan(
        text: OfflineNote.title,
        children: [
          for (var i = 1; i <= _dots; i++) TextSpan(text: '.', style: i > shown ? TextStyle(color: hidden) : null),
        ],
      ),
      style: widget.style,
    );
  }
}

/// The small button of the short note. It fades in as the rest of the note folds away, and takes no room before that.
class _SeeHow extends StatelessWidget {
  const _SeeHow({required this.show});

  final bool show;

  @override
  Widget build(BuildContext context) {
    final button = show
        ? Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                  child: Text(
                    'See how',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
        : const SizedBox.shrink();
    if (calm(context)) return button;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: button,
    );
  }
}

/// What the note says in full: the three lines, each rising in a little after the one before, and the way to Your data.
///
/// The cross fade around it clips to its edges, so the left gap of the note is padding in here. The rings that breathe out
/// of the icons need that room.
class _Body extends StatelessWidget {
  const _Body({super.key, required this.rings});

  final Animation<double> rings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, left: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rise(
            delay: const Duration(milliseconds: 80),
            child: _Line(
              icon: Icons.arrow_downward_rounded,
              words: 'First, index your media with the button below. Then you can start using the app.',
              rings: rings,
              phase: 0,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Rise(
            delay: const Duration(milliseconds: 200),
            child: _Line(
              icon: Icons.map_outlined,
              words: 'We create a searchable map of your media on your phone, using an on-device ML model.',
              rings: rings,
              phase: 2 / 3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Rise(
            delay: const Duration(milliseconds: 320),
            child: _Line(
              icon: Icons.wifi_off_rounded,
              words: "Everything stays on your phone. The app doesn't need the internet to work.",
              rings: rings,
              phase: 1 / 3,
            ),
          ),
          _Rise(
            delay: const Duration(milliseconds: 440),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Your data', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [child] fading in and rising a few dp after [delay]. With motion off it is just there.
class _Rise extends StatefulWidget {
  const _Rise({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (calm(context)) {
      _c.value = 1;
    } else {
      _wait = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, 8 * (1 - _curve.value)), child: child),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.words, required this.rings, required this.phase});

  final IconData icon;
  final String words;
  final Animation<double> rings;
  final double phase;

  static const _badge = 28.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: _badge,
          child: CustomPaint(
            painter: _RingPainter(rings, phase),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: AppColors.parchment, shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              words,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink80, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// A faint ring that breathes out of an icon and fades. Each icon's ring starts a third of a breath after the one above it.
class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.phase) : super(repaint: t);

  final Animation<double> t;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final v = (t.value + phase) % 1.0;
    if (v > 0.7) return;
    final e = Curves.easeOut.transform(v / 0.7);
    final r = size.width / 2;
    canvas.drawCircle(
      size.center(Offset.zero),
      r + 7 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.primary.withValues(alpha: 0.28 * (1 - e)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.phase != phase;
}

/// A soft band of teal light sweeping across the short note and pausing before it comes again.
class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final run = Curves.easeInOut.transform((t / 0.75).clamp(0.0, 1.0));
    final width = size.width * 0.5;
    final x = -width + (size.width + width) * run;
    final band = Rect.fromLTWH(x, 0, width, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.mediaAccent.withValues(alpha: 0),
            AppColors.mediaAccent.withValues(alpha: 0.22),
            AppColors.mediaAccent.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.primaryGlow.withValues(alpha: 0.03 * math.sin(math.pi * run)));
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t;
}
