import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';

/// The mark on something new: an item the latest scan indexed, or a picture that came to a story after it was last
/// watched. A small pill on a normal tile, a dot on a very small one. The ring keeps it readable on a light or a dark
/// photo. [label] is what a screen reader says.
class NewTag extends StatelessWidget {
  const NewTag({super.key, this.compact = false, this.label = 'New, indexed in the latest scan'});

  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: compact
            ? Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.onMedia, width: 1.4),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.onMedia.withValues(alpha: .85), width: 1),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ),
      ),
    );
  }
}
