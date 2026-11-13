import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';

/// What auto indexing picks up: photos and videos, or one of them. It sits under the switch of auto indexing and is only
/// there while that is on. It is the same choice control as the density of the videos' faces, and it is not the choice
/// of the manual scan.
class AutoIndexContentChoice extends StatelessWidget {
  const AutoIndexContentChoice({super.key, required this.value, required this.onChanged});

  /// 'both', 'images' or 'videos'.
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'both', label: Text('Both')),
                ButtonSegment(value: 'images', label: Text('Photos')),
                ButtonSegment(value: 'videos', label: Text('Videos')),
              ],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'What auto indexing picks up.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink48, height: 1.4),
          ),
        ],
      ),
    );
  }
}
