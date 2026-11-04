import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

/// The Why this matched section of the image and video viewers: one row per word, each with its own bar. The raw
/// dot-product scores from loadMatchExplanation do not mean an absolute percentage, so the bars are scaled to the
/// strongest word, which always reads as a full bar, and show the ranking and not an exact number. The rows fill in
/// one after another, strongest first. It is meant to be mounted fresh each time its sheet opens (see
/// [DraggableMetadataSheet]), so the filling plays every time.
class MatchStrengthBars extends StatelessWidget {
  const MatchStrengthBars({super.key, required this.entries});

  final List<MapEntry<String, double>> entries;

  @override
  Widget build(BuildContext context) {
    final maxScore = entries.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _StrengthBarRow(
              word: entries[i].key,
              fraction: maxScore > 0 ? (entries[i].value / maxScore).clamp(0.0, 1.0) : 0.0,
              index: i,
            ),
          ),
        ],
      ],
    );
  }
}

class _StrengthBarRow extends StatefulWidget {
  const _StrengthBarRow({required this.word, required this.fraction, required this.index});

  final String word;
  final double fraction;
  final int index;

  @override
  State<_StrengthBarRow> createState() => _StrengthBarRowState();
}

class _StrengthBarRowState extends State<_StrengthBarRow> {
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 120 * widget.index), () {
      if (mounted) setState(() => _revealed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _revealed ? widget.fraction : 0),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Text(
                  '${(value * 100).round()}%',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.ink48),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.hairline),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _revealed ? widget.fraction : 0),
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: const ColoredBox(color: AppColors.primary),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
