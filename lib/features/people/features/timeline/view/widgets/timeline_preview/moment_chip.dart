part of '../timeline_preview.dart';

/// A little card on the opened-out month: the person's face, an icon, and what happened.
class _MomentChip extends StatelessWidget {
  const _MomentChip({required this.people, required this.icon, required this.text});

  final List<Person> people;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [BoxShadow(color: AppColors.shadow.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24.0 + (people.length - 1) * 16,
            height: 24,
            child: Stack(
              children: [
                for (var i = 0; i < people.length; i++)
                  Positioned(
                    left: i * 16.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.canvas, width: 1.5),
                      ),
                      child: FaceAvatar(faceId: people[i].coverFaceId, size: 24),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
