import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_links.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/tour/tour_samples.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

/// Page 5: how the app differs from Google Photos, in plain facts, and where the source code is. When the page comes
/// in, the table answers row by row: this app's answer first, with its check, then Google Photos' after it.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.scope});

  final TourPageScope scope;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _still = false;

  @override
  void initState() {
    super.initState();
    if (widget.scope.active) _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With animations turned off the whole table is simply there.
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant ComparePage old) {
    super.didUpdateWidget(old);
    if (widget.scope.active && !old.scope.active) _play();
  }

  void _play() {
    if (_still) {
      _c.value = 1;
      return;
    }
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _later(double from, double to, Widget child, {double dy = 0}) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final a = Interval(from, to, curve: Curves.easeOut).transform(_c.value);
        return Opacity(
          opacity: a,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - a)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TourPageFrame(
      title: 'Your photos stay yours.',
      emphasis: 'yours',
      subtitle:
          'There is no account and nothing is uploaded. Here is how that differs from Google Photos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Table(progress: _c),
          const SizedBox(height: AppSpacing.md),
          _later(
            0.8,
            0.95,
            Text(
              'Free, ad-free and fully open source. Look inside, or help improve it on GitHub.',
              style: textTheme.bodySmall?.copyWith(
                color: kTourText80,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _later(0.86, 1, const _SourceButton(), dy: 8),
        ],
      ),
    );
  }
}

/// The comparison, as two columns side by side: this app's in solid teal, Google Photos' in white, the same rows lined up
/// across them. Each cell names its row in small capitals above the answer. [progress] runs 0 to 1 as the page comes in.
class _Table extends StatelessWidget {
  const _Table({required this.progress});

  final Animation<double> progress;

  static const _rows = [
    ('Needs an account', 'No', 'Yes, a Google account'),
    ('Your photos', 'Stay on your phone', 'Backed up to the cloud'),
    ('Needs the internet', 'No', 'Yes'),
    ('Face data', 'On your phone', 'In your Google account'),
    ('Source code', 'Open on GitHub', 'Closed'),
    ('Price', 'Free', 'Free to 15 GB, then paid'),
  ];

  static const double _gap = 8;

  // Row [i] (0 is the header) starts a little after the one above it.
  static double _start(int i) => 0.04 + 0.105 * i;

  double _at(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      Interval(from, to, curve: curve).transform(progress.value);

  Widget _fade(double a, Widget child, {double dy = 6}) => Opacity(
    opacity: a,
    child: Transform.translate(offset: Offset(0, dy * (1 - a)), child: child),
  );

  Widget _cell({
    required bool ours,
    required Widget child,
    bool first = false,
    bool last = false,
  }) {
    const r = Radius.circular(AppRadius.xl);
    final radius = BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ours ? AppColors.primary : Colors.white,
        borderRadius: radius,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
          // The thin line between this row and the one above.
          if (!first)
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: 0,
              height: 1,
              child: ColoredBox(
                color: ours
                    ? Colors.white.withValues(alpha: 0.16)
                    : AppColors.dividerSoft,
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    TextTheme textTheme,
    int i, {
    required String label,
    required String ours,
    required String theirs,
    bool first = false,
    bool last = false,
  }) {
    final s = _start(i);
    final a = _at(s, s + 0.2);
    final b = _at(s + 0.1, s + 0.3);
    final small = textTheme.labelSmall?.copyWith(
      fontSize: 9.5,
      letterSpacing: 0.9,
      height: 1.2,
      fontWeight: FontWeight.w500,
    );
    final heading = textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    final Widget oursChild;
    final Widget theirsChild;
    if (first) {
      oursChild = Text(
        'Lost & Found',
        style: heading?.copyWith(color: Colors.white),
      );
      theirsChild = Text(
        'Google Photos',
        style: heading?.copyWith(color: AppColors.ink),
      );
    } else {
      oursChild = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: small?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
          ),
          const SizedBox(height: 3),
          _fade(
            a,
            _OursAnswer(
              text: ours,
              // The check pops in a beat after its words.
              pop: _at(s + 0.08, s + 0.28, Curves.easeOutBack),
            ),
            dy: 8,
          ),
        ],
      );
      theirsChild = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            // Darker than the app's usual quiet grey: at this size the usual one is under 4.5:1 on white.
            style: small?.copyWith(color: const Color(0xFF656B69)),
          ),
          const SizedBox(height: 3),
          _fade(
            b,
            Text(
              theirs,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.ink80,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    }
    // The row is announced as one sentence, whatever the animation is showing.
    return Semantics(
      label: first
          ? 'Lost and Found compared with Google Photos'
          : '$label. Lost and Found: $ours. Google Photos: $theirs.',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _cell(
                ours: true,
                first: first,
                last: last,
                child: oursChild,
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: _cell(
                ours: false,
                first: first,
                last: last,
                child: theirsChild,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) => Column(
          children: [
            _row(textTheme, 0, first: true, label: '', ours: '', theirs: ''),
            for (var i = 0; i < _rows.length; i++)
              _row(
                textTheme,
                i + 1,
                last: i == _rows.length - 1,
                label: _rows[i].$1,
                ours: _rows[i].$2,
                theirs: _rows[i].$3,
              ),
          ],
        ),
      ),
    );
  }
}

/// This app's answer: a white check and the words, on the teal.
class _OursAnswer extends StatelessWidget {
  const _OursAnswer({required this.text, required this.pop});

  final String text;

  /// 0 to 1 (a little over 1 while the check settles).
  final double pop;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5),
          child: Transform.scale(
            scale: pop.clamp(0.0, 1.25),
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton();

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(kRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View source code on GitHub',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.code_rounded, size: 20, color: AppColors.ink),
                const SizedBox(width: AppSpacing.sm),
                // Flexible: with large text the words wrap instead of running out of the button.
                Flexible(
                  child: Text(
                    'View source code on GitHub',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: AppColors.ink),
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
