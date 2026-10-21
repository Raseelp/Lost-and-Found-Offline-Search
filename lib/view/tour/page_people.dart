import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';
import 'package:lost_and_found/view/tour/face_demo.dart';
import 'package:lost_and_found/view/tour/tour_person_tile.dart';
import 'package:lost_and_found/view/tour/tour_screen.dart';
import 'package:lost_and_found/view/tour/tour_widgets.dart';

/// Page 3: more than search. People (as the People tab shows them), what happens when a photo is opened and a face
/// tapped, and "Then and now", on sample data. It plays by itself and
/// nothing on it can be touched.
class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key, required this.scope});

  final TourPageScope scope;

  @override
  Widget build(BuildContext context) {
    return TourPageFrame(
      title: 'Browse by who is in them.',
      emphasis: 'who',
      subtitle:
          'Faces are grouped on your phone. Name someone and see all their photos.',
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('People'),
            const SizedBox(height: AppSpacing.sm),
            _PeopleStacks(active: scope.active),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Open a photo, tap a face'),
            const SizedBox(height: AppSpacing.sm),
            TourFaceDemo(active: scope.active),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Then and now'),
            const SizedBox(height: AppSpacing.sm),
            _ThenNowCard(active: scope.active),
            const SizedBox(height: AppSpacing.sm),
            const Center(child: TourTag('Sample people and photos')),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: TourPalette.teal,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ----------------------------------------------------------------------------------- people

/// Three people as the People tab shows them (stacks of their faces with the name and number of photos), and a
/// fourth tile for everyone else.
class _PeopleStacks extends StatelessWidget {
  const _PeopleStacks({required this.active});

  final bool active;

  static const _people = [
    ('Maya', 248, ['maya', 'maya_2', 'maya_3'], -3.0),
    ('Sam', 131, ['sam', 'sam_2', 'sam_3'], 3.0),
    // Two clear faces so far: the third card behind is blank, as in the app.
    ('Messi', 7, ['messi', 'messi_2'], -2.2),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _people.length; i++)
          Expanded(
            child: TourPersonTile(
              name: _people[i].$1,
              photos: _people[i].$2,
              faces: [
                for (final f in _people[i].$3) 'assets/tour/faces/$f.jpg',
              ],
              lean: _people[i].$4,
              index: i,
              active: active,
            ),
          ),
        // The rest of the people the app has found: more than fit in the row.
        Expanded(
          child: TourPersonTile(
            name: 'More',
            photos: 57,
            faces: const [],
            lean: 2.6,
            index: _people.length,
            active: active,
            badge: '+57',
            detail: 'people',
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------------------- then and now

/// The same person in two photos, years apart, with the divider sweeping back and forth by itself.
class _ThenNowCard extends StatefulWidget {
  const _ThenNowCard({required this.active});

  final bool active;

  @override
  State<_ThenNowCard> createState() => _ThenNowCardState();
}

class _ThenNowCardState extends State<_ThenNowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  // With animations turned off on the phone the divider rests in the middle.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ThenNowCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !_still && !_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    } else if ((!widget.active || _still) && _sweep.isAnimating) {
      _sweep.stop();
    }
    if (_still) _sweep.value = 0.5;
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: 1.6,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/tour/photos/messi_now.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.2),
                    cacheWidth: 700,
                  ),
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) {
                      // The divider travels between 0.2 and 0.8 of the width.
                      final s =
                          0.2 + 0.6 * Curves.easeInOut.transform(_sweep.value);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            clipper: _LeftOf(s),
                            child: Image.asset(
                              'assets/tour/photos/messi_then.jpg',
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, -0.2),
                              cacheWidth: 700,
                            ),
                          ),
                          Positioned(
                            left: s * w - 1,
                            top: 0,
                            bottom: 0,
                            width: 2,
                            child: const ColoredBox(color: TourPalette.white),
                          ),
                          Positioned(
                            left: s * w - 18,
                            top: box.maxHeight / 2 - 18,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: TourPalette.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: TourPalette.black.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chevron_left_rounded,
                                    size: 17,
                                    color: AppColors.primary,
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 17,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _Tag(
                              label: 'THEN  ·  2012',
                              opacity: ((s - 0.1) / 0.2).clamp(0.0, 1.0),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: _Tag(
                              label: 'NOW  ·  2026',
                              opacity: ((0.9 - s) / 0.2).clamp(0.0, 1.0),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  _LeftOf(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.share != share;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.opacity});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: TourPalette.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: TourPalette.white,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
