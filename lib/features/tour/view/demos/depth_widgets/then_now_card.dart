part of '../depth_widgets.dart';

/// Then and now: two photos of one person with a divider. Back in the crowd it is a plain split down the middle. As
/// it comes forward the handle appears and the divider sweeps to one side, then the other, and settles again as it
/// goes back. All of it follows the turn, so it never jumps.
///
/// The divider is always sliding, a whole number of sweeps to the loop, so the end of the loop meets its start.
class _ThenNowCard extends StatelessWidget {
  const _ThenNowCard({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final s = 0.5 + 0.3 * math.sin(turn.t * 2 * math.pi * 5);
    Widget tag(String label, Alignment at, double opacity) => Align(
      alignment: at + const Alignment(0, 0.82),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: TourPalette.text.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: _small(
              context,
              color: TourPalette.white,
              weight: FontWeight.w700,
              size: 8,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: TourPalette.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: LayoutBuilder(
          builder: (context, box) {
            final x = s * box.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/tour/photos/messi_now.jpg',
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                ),
                ClipRect(
                  clipper: _LeftOf(s),
                  child: Image.asset(
                    'assets/tour/photos/messi_then.jpg',
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                  ),
                ),
                Positioned(
                  left: x - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const ColoredBox(color: TourPalette.white),
                ),
                Positioned(
                  left: x - 11,
                  top: box.maxHeight / 2 - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: TourPalette.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TourPalette.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 11,
                          color: TourPalette.teal,
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 11,
                          color: TourPalette.teal,
                        ),
                      ],
                    ),
                  ),
                ),
                tag('THEN', Alignment.centerLeft, (s - 0.1) / 0.2),
                tag('NOW', Alignment.centerRight, (0.9 - s) / 0.2),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.share != share;
}
