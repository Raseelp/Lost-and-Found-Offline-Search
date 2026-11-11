part of '../search_results.dart';

/// Builds a one-off pattern sized to exactly `resultCount` items, or as close as a whole number of movements allows,
/// with the rest finished by the tail in _ResultsSliverGrid.build. It sprinkles rare showcase movements into the
/// steady rotation instead of using one fixed pattern. `seed` must be stable across rebuilds of the same result set,
/// or the mosaic would visibly reshuffle mid-load, so derive it from something that only changes when the results do.
/// A movement that does not fit is left out, because a partial movement cannot be flush.
List<QuiltedGridTile> _generateBentoPattern({
  required int resultCount,
  required int seed,
}) {
  final rng = Random(seed);
  final pattern = <QuiltedGridTile>[];
  var steadyIndex = 0;
  var movementsSinceShowcase = _showcaseMinMovementGap;
  var movementsSinceGiant = _giantMinMovementGap;

  while (true) {
    final remaining = resultCount - pattern.length;
    final giantEligible = remaining >= _giantMinRemainingItems &&
        movementsSinceGiant >= _giantMinMovementGap;
    final showcaseEligible = remaining >= _showcaseMinRemainingItems &&
        movementsSinceShowcase >= _showcaseMinMovementGap;

    List<QuiltedGridTile> next;
    var isShowcase = false;
    var isGiant = false;

    if (giantEligible && rng.nextDouble() < _giantChance) {
      next = _showcaseGiant;
      isShowcase = true;
      isGiant = true;
    } else if (showcaseEligible && rng.nextDouble() < _showcaseChance) {
      next = _showcaseOptions[rng.nextInt(_showcaseOptions.length)];
      isShowcase = true;
    } else {
      next = _steadyRotation[steadyIndex % _steadyRotation.length];
      steadyIndex++;
    }

    if (pattern.length + next.length > resultCount) break;

    pattern.addAll(next);
    movementsSinceShowcase = isShowcase ? 0 : movementsSinceShowcase + 1;
    movementsSinceGiant = isGiant ? 0 : movementsSinceGiant + 1;
  }

  return pattern;
}

const List<List<QuiltedGridTile>> _steadyRotation = [
  _movementHeroLeft,
  _movementNoHero,
  _movementHeroRight,
];

const List<List<QuiltedGridTile>> _showcaseOptions = [
  _showcaseHorizontal,
  _showcaseVerticalLeft,
  _showcaseVerticalRight,
];

/// Rare showcase movements: one full-bleed photo taking up far more room than usual, spliced sparingly into the steady
/// rhythm by _generateBentoPattern rather than appearing on a fixed schedule. In the tall right hero, a filler placed
/// first is strictly ahead and forces the hero onto the right half, and a catch-up filler re-flushes the left side.
const List<QuiltedGridTile> _showcaseHorizontal = [
  QuiltedGridTile(2, 4),
];

const List<QuiltedGridTile> _showcaseVerticalLeft = [
  QuiltedGridTile(4, 2),
  QuiltedGridTile(2, 2),
  QuiltedGridTile(2, 2),
];

const List<QuiltedGridTile> _showcaseVerticalRight = [
  QuiltedGridTile(2, 2),
  QuiltedGridTile(4, 2),
  QuiltedGridTile(2, 2),
];

const List<QuiltedGridTile> _showcaseGiant = [
  QuiltedGridTile(4, 4),
];

/// A showcase is not considered until the list has enough room left to stay a small minority of the content, which
/// keeps a short result set from being dominated by one giant tile. The giant tile needs an even larger runway and a
/// wider gap from the last showcase, so it reads as rarer than the 8-slot ones. The base chances (0.15 and 0.04) were
/// scaled by 2.5 after testing on a real device.
const int _showcaseMinRemainingItems = 20;

const int _showcaseMinMovementGap = 3;

const double _showcaseChance = 0.375;

const int _giantMinRemainingItems = 40;

const int _giantMinMovementGap = 6;

const double _giantChance = 0.1;
