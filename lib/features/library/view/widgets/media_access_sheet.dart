import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';

/// Says why Lost & Found needs the photos and videos, and what happens to them, before Android asks for them. Returns
/// true for Continue, and false for Not now or when the sheet is dismissed.
Future<bool> showMediaAccessSheet(BuildContext context) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => const _MediaAccessSheet(),
  );
  return agreed == true;
}

class _MediaAccessSheet extends StatelessWidget {
  const _MediaAccessSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium?.copyWith(color: AppColors.ink80, height: 1.45);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Enable media access', style: text.titleLarge),
                const SizedBox(height: AppSpacing.md),
                Text.rich(
                  TextSpan(
                    style: body,
                    children: [
                      const TextSpan(
                        text: 'To make your media searchable offline, we make a fingerprint of each one and ',
                      ),
                      TextSpan(
                        text: 'store it right on your device.',
                        style: body?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _Promise(icon: Icons.smartphone_rounded, text: 'Your media never leaves this device.'),
                const SizedBox(height: AppSpacing.md),
                const _Promise(
                  icon: Icons.airplanemode_active_rounded,
                  text: 'The entire app works offline. You can try it in airplane mode.',
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                  child: const Text('Continue'),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: AppColors.ink48),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.parchment, shape: BoxShape.circle),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
