part of '../people_timeline.dart';

/// Their face on a small white print, leaning like their tile on the grid, with a tick when chosen.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.personId,
    required this.preview,
    required this.faceId,
    required this.lean,
    required this.press,
    required this.selecting,
    required this.selected,
  });

  final int personId;
  final TimelinePreview? preview;
  final int faceId;
  final double lean;
  final Animation<double> press;
  final bool selecting, selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatar,
      height: _avatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: press,
              builder: (context, child) => Transform.rotate(
                angle: lean * math.pi / 180 * (1 - 0.7 * press.value),
                child: child,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(color: AppColors.shadow.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: SizedBox(
                      width: _avatar - 5,
                      height: _avatar - 5,
                      child: preview == null
                          ? FaceAvatar(faceId: faceId, size: _avatar - 5, square: true, radius: 8.5)
                          : ListenableBuilder(
                              listenable: preview!,
                              builder: (context, _) {
                                final photo = preview!.photoFor(personId);
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 380),
                                  switchInCurve: Curves.easeOutCubic,
                                  layoutBuilder: switcherStack(fit: StackFit.expand),
                                  child: photo == null
                                      ? FaceAvatar(
                                          key: const ValueKey('face'),
                                          faceId: faceId,
                                          size: _avatar - 5,
                                          square: true,
                                          radius: 0,
                                        )
                                      : PreviewImage(
                                          key: ValueKey(photo.cacheKey),
                                          photo: photo,
                                          loader: preview!.loader,
                                          alignment: const Alignment(0, -0.35),
                                        ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selecting)
            Positioned(
              right: -5,
              bottom: -5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : AppColors.canvas,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.hairline, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 13, color: AppColors.onPrimary) : null,
              ),
            ),
        ],
      ),
    );
  }
}

const double _avatar = 40;
