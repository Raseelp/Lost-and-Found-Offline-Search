part of '../person_menu.dart';

/// Everyone else, the likeliest matches first; tapping one asks to confirm the merge.
void showMergePicker(
  BuildContext context,
  FacesController faces,
  Person person,
) {
  final others = faces.people.where((p) => p.id != person.id).toList()
    ..sort((x, y) {
      final sx = faces.suggestionScoreFor(person, x) ?? -1;
      final sy = faces.suggestionScoreFor(person, y) ?? -1;
      if (sx != sy) return sy.compareTo(sx);
      return y.photoCount.compareTo(x.photoCount);
    });

  showFacesSheet<void>(
    context,
    title: 'Merge ${person.name ?? 'this person'} with...',
    builder: (sheet) => others.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text('There is nobody else to merge with yet.'),
          )
        : ListView.separated(
            shrinkWrap: true,
            itemCount: others.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.dividerSoft),
            itemBuilder: (_, i) {
              final other = others[i];
              final suggested = faces.suggestionScoreFor(person, other) != null;
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  Navigator.of(sheet).pop();
                  confirmMerge(context, faces, keep: person, other: other);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      FaceAvatar(faceId: other.coverFaceId, size: 44),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          other.name ??
                              'Unnamed  ·  ${other.photoCount} photos',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
      if (suggested)
                        Text(
                          'Looks similar',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.primary),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
