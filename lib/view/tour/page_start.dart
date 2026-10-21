import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';
import 'package:lost_and_found/view/tour/depth_widgets.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

/// Page 1: the whole app at a glance. Its widgets (a video, "On this day", people, Then & now, a memory, search,
/// privacy) float at different depths and take turns coming forward.
class StartPage extends StatelessWidget {
  const StartPage({super.key, required this.scope});

  final TourPageScope scope;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TourPageFrame(
      fill: true,
      title: 'Meet your gallery again.',
      emphasis: 'gallery',
      subtitle: 'Find any photo or video by describing it. Free, with no ads.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: DepthWidgets(active: scope.active),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: TourPalette.teal,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'No account. Nothing is uploaded.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: TourPalette.text,
                    height: 1.4,
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
