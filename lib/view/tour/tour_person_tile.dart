import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';

/// One person as the People tab shows them (see PersonTile): a small tilted stack of their faces, the cover on
/// top and two more behind it leaning the other way, then the name and how many photos. The stack fans out one
/// tile after another when the page shows. Where a person has fewer faces than the stack holds, the cards behind
/// are left blank, as in the app. The pictures are bundled (the app's own tile reads faces from its database).
class TourPersonTile extends StatefulWidget {
  const TourPersonTile({
    super.key,
    required this.name,
    required this.photos,
    required this.faces,
    required this.lean,
    this.index = 0,
    this.active = true,
    this.badge,
    this.detail,
  });

  final String name;
  final int photos;

  /// Assets of the faces, the cover first (up to three).
  final List<String> faces;

  /// The lean of the top card in degrees, as the app works it out from the person's id (never flat).
  final double lean;

  /// Where the tile is in its row: the stacks open one after another.
  final int index;

  /// Whether the page is showing: the stack fans out each time it becomes so.
  final bool active;

  /// Words on the top card instead of a face ("+57"): for the tile that stands for the people not shown.
  final String? badge;

  /// The line under the name, in place of "N photos".
  final String? detail;

  @override
  State<TourPersonTile> createState() => _TourPersonTileState();
}

class _TourPersonTileState extends State<TourPersonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TourPersonTile old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      Future<void>.delayed(Duration(milliseconds: 250 + widget.index * 45), () {
        if (!_gone && mounted && widget.active) _fan.forward(from: 0);
      });
    } else {
      _fan.value = 0;
    }
  }

  @override
  void dispose() {
    _gone = true;
    _fan.dispose();
    super.dispose();
  }

  // One face in the stack: a white-bordered rounded square (blank when the person has too few faces).
  Widget _card(String? asset, double size, {required bool top, String? badge}) {
    final radius = size * 0.24;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TourPalette.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          top
              ? BoxShadow(
                  color: TourPalette.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
              : BoxShadow(
                  color: TourPalette.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          width: size - 6,
          height: size - 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 3),
            child: asset == null
                ? ColoredBox(
                    color: AppColors.parchment,
                    child: badge == null
                        ? null
                        : Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  badge,
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ),
                  )
                : Image.asset(asset, fit: BoxFit.cover, cacheWidth: 220),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final lean = widget.lean;
    final dir = lean < 0 ? 1.0 : -1.0;
    // The same lean the app gives the two cards behind (a different amount each, peeking out to the sides).
    final angles = [lean, lean + dir * 11, lean - dir * 7];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final area = (box.maxWidth - 24).clamp(60.0, 112.0);
              final card = area * 0.84;
              final shifts = [
                Offset.zero,
                Offset(dir * area * 0.07, -area * 0.03),
                Offset(-dir * area * 0.06, -area * 0.04),
              ];
              return SizedBox(
                width: area + 8,
                height: area + 8,
                child: Center(
                  child: SizedBox(
                    width: area,
                    height: area,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Furthest back first.
                        for (final layer in const [2, 1, 0])
                          AnimatedBuilder(
                            animation: _fan,
                            builder: (context, child) {
                              final open = Curves.easeOutBack.transform(
                                _fan.value,
                              );
                              return Transform.translate(
                                offset: shifts[layer] * open,
                                child: Transform.rotate(
                                  angle: angles[layer] * math.pi / 180 * open,
                                  child: child,
                                ),
                              );
                            },
                            child: _card(
                              layer < widget.faces.length
                                  ? widget.faces[layer]
                                  : null,
                              card,
                              top: layer == 0,
                              badge: layer == 0 ? widget.badge : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Scaled down rather than cut off, so a narrow phone still reads "248 photos" in full.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.name,
                maxLines: 1,
                style: textTheme.titleSmall?.copyWith(color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.detail ??
                    (widget.photos == 1
                        ? '1 photo'
                        : '${widget.photos} photos'),
                maxLines: 1,
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
