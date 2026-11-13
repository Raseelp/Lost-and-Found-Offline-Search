part of '../library_tab.dart';

const _scopeOrder = [ContentMode.images, ContentMode.both, ContentMode.videos];

String _scopeLabel(ContentMode mode) {
  switch (mode) {
    case ContentMode.images:
      return 'Photos';
    case ContentMode.videos:
      return 'Videos';
    case ContentMode.both:
      return 'Photos & videos';
  }
}

/// The button that starts a scan, with what to index and where to look folded into it. The second line of the button says
/// what is selected, and the arrow slides the two switches open under it. The button itself does not move.
class _StartPanel extends StatefulWidget {
  const _StartPanel({
    required this.label,
    required this.controller,
    required this.onStart,
  });

  final String label;
  final LibraryController controller;
  final VoidCallback onStart;

  @override
  State<_StartPanel> createState() => _StartPanelState();
}

class _StartPanelState extends State<_StartPanel>
    with SingleTickerProviderStateMixin {
  static const _buttonHeight = 60.0;
  static const _inset = 4.0;
  static const _closedRadius = _buttonHeight / 2 + _inset;
  static const _openRadius = 24.0;

  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final CurvedAnimation _grow = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _open,
    curve: const Interval(0.3, 1, curve: Curves.easeOut),
  );
  bool _expanded = false;

  void _set(bool expanded) {
    setState(() => _expanded = expanded);
    if (calm(context)) {
      _open.value = expanded ? 1 : 0;
    } else if (expanded) {
      _open.forward();
    } else {
      _open.reverse();
    }
  }

  void _start() {
    if (_expanded) _set(false);
    widget.onStart();
  }

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final summary =
        '${_scopeLabel(controller.selectedContentMode)} · ${controller.scanWholePhone ? 'Whole phone' : 'One folder'}';
    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(
            lerpDouble(_closedRadius, _openRadius, _grow.value)!,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _button(context, summary),
              if (!_open.isDismissed)
                SizeTransition(
                  sizeFactor: _grow,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: _fade,
                    child: _settings(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String summary) {
    final text = Theme.of(context).textTheme;
    final splash = Colors.white.withValues(alpha: 0.12);
    return Material(
      color: AppColors.primary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_buttonHeight / 2))),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _buttonHeight),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${widget.label}. $summary',
                  excludeSemantics: true,
                  onTap: _start,
                  child: InkWell(
                    onTap: _start,
                    splashColor: splash,
                    highlightColor: splash,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.sm,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryFocus,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.memory_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.label,
                                  style: text.labelLarge?.copyWith(
                                    color: AppColors.onPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  summary,
                                  style: text.bodySmall?.copyWith(
                                    color: AppColors.onPrimary.withValues(
                                      alpha: 0.74,
                                    ),
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
              ),
              Semantics(
                button: true,
                expanded: _expanded,
                label: 'Indexing options',
                excludeSemantics: true,
                onTap: () => _set(!_expanded),
                child: InkWell(
                  onTap: () => _set(!_expanded),
                  splashColor: splash,
                  highlightColor: splash,
                  child: Container(
                    width: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0, end: 0.5).animate(_grow),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 26,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settings(BuildContext context) {
    final controller = widget.controller;
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.ink48,
      letterSpacing: 0.5,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.base - 2,
        AppSpacing.md,
        AppSpacing.md - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('WHAT TO INDEX', style: label),
          const SizedBox(height: AppSpacing.sm),
          _Segmented<ContentMode>(
            tinted: true,
            options: _scopeOrder,
            value: controller.selectedContentMode,
            labelOf: _scopeLabel,
            onChanged: (mode) =>
                controller.toggleSelectedContentMode(contentMode: mode),
          ),
          const SizedBox(height: AppSpacing.base),
          Text('WHERE TO LOOK', style: label),
          const SizedBox(height: AppSpacing.sm),
          _Segmented<bool>(
            tinted: true,
            options: const [true, false],
            value: controller.scanWholePhone,
            labelOf: (wholePhone) => wholePhone ? 'Whole phone' : 'One folder',
            onChanged: controller.setScanWholePhone,
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              controller.scanWholePhone
                  ? 'Everything on your phone, in one go.'
                  : 'Choose the folder to index.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
          ),
        ],
      ),
    );
  }
}
