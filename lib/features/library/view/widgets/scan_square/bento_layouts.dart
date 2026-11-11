part of '../scan_square.dart';

/// How [n] photos read together are laid out, as parts of the photo area. Several for each
/// count, and a different one is used each round, so the mosaic is never the same twice; every
/// photo fills its cell (cropped to it, never stretched).
const _bentoLayouts = <List<List<Rect>>>[
  [],
  [
    [Rect.fromLTWH(0, 0, 1, 1)],
  ],
  [
    [Rect.fromLTWH(0, 0, .5, 1), Rect.fromLTWH(.5, 0, .5, 1)],
    [Rect.fromLTWH(0, 0, 1, .5), Rect.fromLTWH(0, .5, 1, .5)],
    [Rect.fromLTWH(0, 0, .62, 1), Rect.fromLTWH(.62, 0, .38, 1)],
    [Rect.fromLTWH(0, 0, .38, 1), Rect.fromLTWH(.38, 0, .62, 1)],
  ],
  [
    [Rect.fromLTWH(0, 0, .58, 1), Rect.fromLTWH(.58, 0, .42, .5), Rect.fromLTWH(.58, .5, .42, .5)],
    [Rect.fromLTWH(0, 0, .42, .5), Rect.fromLTWH(0, .5, .42, .5), Rect.fromLTWH(.42, 0, .58, 1)],
    [Rect.fromLTWH(0, 0, 1, .58), Rect.fromLTWH(0, .58, .5, .42), Rect.fromLTWH(.5, .58, .5, .42)],
    [Rect.fromLTWH(0, 0, .5, .42), Rect.fromLTWH(.5, 0, .5, .42), Rect.fromLTWH(0, .42, 1, .58)],
    [Rect.fromLTWH(0, 0, .34, 1), Rect.fromLTWH(.34, 0, .33, 1), Rect.fromLTWH(.67, 0, .33, 1)],
  ],
  [
    [
      Rect.fromLTWH(0, 0, .5, .5), Rect.fromLTWH(.5, 0, .5, .5),
      Rect.fromLTWH(0, .5, .5, .5), Rect.fromLTWH(.5, .5, .5, .5),
    ],
    [
      Rect.fromLTWH(0, 0, .55, 1), Rect.fromLTWH(.55, 0, .45, .34),
      Rect.fromLTWH(.55, .34, .45, .33), Rect.fromLTWH(.55, .67, .45, .33),
    ],
    [
      Rect.fromLTWH(0, 0, 1, .55), Rect.fromLTWH(0, .55, .34, .45),
      Rect.fromLTWH(.34, .55, .33, .45), Rect.fromLTWH(.67, .55, .33, .45),
    ],
    [
      Rect.fromLTWH(0, 0, .4, .6), Rect.fromLTWH(.4, 0, .6, .6),
      Rect.fromLTWH(0, .6, .6, .4), Rect.fromLTWH(.6, .6, .4, .4),
    ],
  ],
  [
    [
      Rect.fromLTWH(0, 0, .5, 1), Rect.fromLTWH(.5, 0, .25, .5), Rect.fromLTWH(.75, 0, .25, .5),
      Rect.fromLTWH(.5, .5, .25, .5), Rect.fromLTWH(.75, .5, .25, .5),
    ],
    [
      Rect.fromLTWH(0, 0, .6, .6), Rect.fromLTWH(.6, 0, .4, .6), Rect.fromLTWH(0, .6, .34, .4),
      Rect.fromLTWH(.34, .6, .33, .4), Rect.fromLTWH(.67, .6, .33, .4),
    ],
    [
      Rect.fromLTWH(0, 0, .34, .5), Rect.fromLTWH(.34, 0, .33, .5), Rect.fromLTWH(.67, 0, .33, .5),
      Rect.fromLTWH(0, .5, .5, .5), Rect.fromLTWH(.5, .5, .5, .5),
    ],
  ],
  [
    [
      Rect.fromLTWH(0, 0, .34, .5), Rect.fromLTWH(.34, 0, .33, .5), Rect.fromLTWH(.67, 0, .33, .5),
      Rect.fromLTWH(0, .5, .34, .5), Rect.fromLTWH(.34, .5, .33, .5), Rect.fromLTWH(.67, .5, .33, .5),
    ],
    [
      Rect.fromLTWH(0, 0, .5, .6), Rect.fromLTWH(.5, 0, .5, .3), Rect.fromLTWH(.5, .3, .25, .3),
      Rect.fromLTWH(.75, .3, .25, .3), Rect.fromLTWH(0, .6, .5, .4), Rect.fromLTWH(.5, .6, .5, .4),
    ],
    [
      Rect.fromLTWH(0, 0, .4, .5), Rect.fromLTWH(0, .5, .4, .5), Rect.fromLTWH(.4, 0, .3, .5),
      Rect.fromLTWH(.7, 0, .3, .5), Rect.fromLTWH(.4, .5, .3, .5), Rect.fromLTWH(.7, .5, .3, .5),
    ],
  ],
];
