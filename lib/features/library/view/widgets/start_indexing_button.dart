import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';

/// The button that starts a scan, the same on every screen that offers one: a pill with a round chip icon at its left.
class StartIndexingButton extends StatelessWidget {
  const StartIndexingButton({super.key, required this.onPressed, this.label = 'Start indexing'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.fromLTRB(7, 0, 22, 0),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: AppColors.primaryFocus, shape: BoxShape.circle),
            child: const Icon(Icons.memory_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}
