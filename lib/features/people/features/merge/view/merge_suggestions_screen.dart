import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/native/native_services.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';

/// People who may be the same person, two at a time. Grouping cannot always tell, as with the same person in
/// different light, with and without glasses, or years apart, so the ones it is not sure about are put here for a yes
/// or a no. A "no" is remembered, so the pair never comes back.
class MergeSuggestionsScreen extends StatelessWidget {
  const MergeSuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Same person?', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: GetBuilder<FacesController>(
          builder: (faces) {
            final pairs = faces.suggestions;
            if (pairs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'Nothing to review. People who might be the same person will show up here.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.ink48, height: 1.45),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xxl),
              itemCount: pairs.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, i) {
                final pair = pairs[i];
                return _SuggestionCard(
                  key: ValueKey('${pair.a.id}-${pair.b.id}'),
                  a: pair.a,
                  b: pair.b,
                  score: pair.score,
                  faces: faces,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// A pair of people with a line saying how likely they are the same person. The line is in words, in three levels,
/// not a number, because it is a guess and not a measurement to compare.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.a,
    required this.b,
    required this.score,
    required this.faces,
  });

  final Person a, b;
  final double score;
  final FacesController faces;

  Widget _person(BuildContext context, Person p) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          FaceAvatar(faceId: p.coverFaceId, size: 84),
          const SizedBox(height: AppSpacing.sm),
          Text(
            p.name ?? 'Unnamed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(color: p.name == null ? AppColors.ink48 : AppColors.ink),
          ),
          Text(
            p.photoCount == 1 ? '1 photo' : '${p.photoCount} photos',
            style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final likely = score >= 0.46
        ? 'Very likely the same person'
        : (score >= 0.40 ? 'Probably the same person' : 'Might be the same person');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _person(context, a),
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: Icon(Icons.link_rounded, color: AppColors.ink48),
              ),
              _person(context, b),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(likely, style: textTheme.bodySmall?.copyWith(color: AppColors.ink80)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => faces.rejectSuggestion(a, b),
                  child: const Text('Different'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => confirmMerge(context, faces, keep: a, other: b),
                  child: const Text('Same person'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
