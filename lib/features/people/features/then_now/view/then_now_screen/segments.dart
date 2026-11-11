part of '../then_now_screen.dart';

/// Two choices side by side in a soft track, the chosen one on a white pill that slides between them.
class _Segments extends StatelessWidget {
  const _Segments({required this.labels, required this.counts, required this.first, required this.onChanged});

  final List<String> labels;
  final List<int> counts;
  final bool first;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 232,
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: first ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: (i == 0) == first,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i == 0),
                      child: Center(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: labels[i]),
                              TextSpan(
                                text: '  ${counts[i]}',
                                style: TextStyle(color: AppColors.ink48.withValues(alpha: (i == 0) == first ? 1 : 0.7)),
                              ),
                            ],
                          ),
                          style: textTheme.labelLarge?.copyWith(
                            color: (i == 0) == first ? AppColors.ink : AppColors.ink48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
