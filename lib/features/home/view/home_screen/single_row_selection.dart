part of '../home_screen.dart';

/// Nothing ticked yet, or a single action: the close button on the left and the words or the button across. One
/// action, or none yet, leaves a gap the width of the close button on the right, so the words are centred in the
/// pill. Two actions use the whole width.
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
        SizedBox(
          width: ready && actions.length > 1 ? AppSpacing.xs : _chipHeight,
        ),
      ],
    );
  }
}
