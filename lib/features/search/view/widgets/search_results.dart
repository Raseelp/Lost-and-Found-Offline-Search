import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/media/media_view_route.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/viewer/view/image_full_screen.dart';
import 'package:lost_and_found/features/viewer/view/video_full_screen.dart';
import 'package:lost_and_found/core/media/grid_video_layer.dart';
import 'package:lost_and_found/features/people/features/timeline/view/widgets/moment_badge.dart';
import 'package:lost_and_found/core/widgets/new_tag.dart';
import 'package:lost_and_found/core/media/media_service.dart';
part 'search_results/shared.dart';
part 'search_results/generate_bento_pattern.dart';
part 'search_results/search_skeleton_grid.dart';
part 'search_results/results_sliver_grid.dart';
part 'search_results/reveal_gate.dart';
part 'search_results/result_tile.dart';
part 'search_results/layout_picker_button.dart';
part 'search_results/layout_sheet.dart';
part 'search_results/layout_option.dart';
part 'search_results/loading_tile.dart';

/// Returns the results as slivers so SearchTab's CustomScrollView is the one scrollable and the grid can virtualize. A
/// GridView.builder with shrinkWrap inside a SingleChildScrollView loses lazy building and recycling, so with many
/// results it held far more decoded images than are visible, which caused crashes and images flickering while
/// scrolling.
List<Widget> searchResultsSlivers({required NativeController controller}) {
  if (controller.isSearching) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: _SearchSkeletonGrid(layout: controller.resultsLayout),
      ),
    ];
  }

  if (controller.error.isNotEmpty) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: SliverToBoxAdapter(
          child: _CenterNote(
            icon: Icons.error_outline_rounded,
            title: 'Something went wrong',
            subtitle: controller.error,
          ),
        ),
      ),
    ];
  }

  if (controller.searchResults.isEmpty) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        sliver: SliverToBoxAdapter(
          child: _CenterNote(
            icon: Icons.search_rounded,
            title: 'Search your media',
            subtitle: controller.totalEmbeddings == 0
                ? 'Index a folder or your phone first, then come back to search.'
                : 'Describe a photo, place, or moment above.',
          ),
        ),
      ),
    ];
  }

  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      sliver: SliverToBoxAdapter(
        child: Builder(
          builder: (context) => Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  '${controller.searchResults.length} results',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.ink48,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              _LayoutPickerButton(controller: controller),
            ],
          ),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: _ResultsSliverGrid(controller: controller),
    ),
  ];
}

class _CenterNote extends StatelessWidget {
  const _CenterNote({
    this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData? icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Column(
        children: [
          if (icon != null) Icon(icon, size: 32, color: AppColors.ink48),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
