part of '../home_screen.dart';

/// One tab's words, and its icon while selected. The teal chip behind it is drawn by the pill, which also takes the
/// touches, so [onTap] is for screen readers.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.light,
    required this.showDot,
    required this.compact,
    required this.onTap,
  });

  final _NavTab tab;
  final bool compact;
  final bool selected;
  final bool showDot;
  final VoidCallback onTap;

  /// True for the copy drawn on the chip, which has light words.
  final bool light;

  /// Sized by its own content and not a [Flexible], because three of those split the pill into equal thirds, which is
  /// smaller than the selected tab needs, with its icon and "Collections", and would clip the label. The pill has
  /// room for all three at natural width.
  /// The icon opens out beside the words, which never move off or get cut, and the tab widens as it does. There is no
  /// FittedBox: label and icon are always the same size, because the pill has the room.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: _chipHeight,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 12 : (compact ? 10 : 14),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (context, open, label) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (open > 0)
                SizedBox(
                  width: 25 * open,
                  height: 18,
                  child: OverflowBox(
                    maxWidth: 25,
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: open.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: open,
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: Icon(
                            tab.selectedIcon,
                            size: 18,
                            color: light ? AppColors.onPrimary : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              label!,
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: light ? AppColors.onPrimary : AppColors.ink80,
                ),
              ),
              if (showDot) ...[
                const SizedBox(width: 5),
                _ActivityDot(
                  color: light ? AppColors.onPrimary : AppColors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
