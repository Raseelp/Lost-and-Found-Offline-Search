import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';

// The Library page's hero is a processor (see chip_art.dart and scan_square.dart) that is the
// scan. This file holds what is shared with the controls round it.

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// A pill with an icon, for the controls around the chip (Stop, Choose folder).
/// [busy] swaps the icon for a small spinner and stops taps, for an action that
/// was asked for and is still finishing (Stop while the scan winds down).
class OrbitPill extends StatelessWidget {
  const OrbitPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : AppColors.ink;
    final accent = filled ? AppColors.onPrimary : AppColors.primary;
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : AppColors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: filled ? null : Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
