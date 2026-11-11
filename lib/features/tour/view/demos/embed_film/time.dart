part of '../embed_film.dart';

/// When each thing happens, in seconds. The whole film is a function of this clock, so it can be run, paused or shown
/// at any second.
class _Time {
  /// The finger presses the chip.
  static const double tap = 1.0;

  /// The scan starts.
  static const double scan = 1.25;

  /// The first photo is read.
  static const double firstPhoto = 2.75;

  /// The chip is still reading as the camera pulls away.
  static const double moreFeed = 6.4;

  static const double pullStart = 6.6;
  static const double pullEnd = 10.2;
  static const double heroFadeStart = 8.4;
  static const double heroFadeEnd = 9.6;
  static const double heroGone = 9.8;

  /// Every photo is read, from the middle outwards.
  static const double waveStart = 7.4;

  /// The bar comes in while the last photos are still settling.
  static const double barIn = 10.9;

  static const double fingerIn = 11.2;
  static const double tapBar = 11.8;
  static const double typeStart = 12.1;
  static const double typeLength = 1.0;
  static const double tapSend = 13.5;
  /// The words leave the bar.
  static const double chipFly = 13.6;

  /// The words land among the photos.
  static const double queryLands = 14.5;

  static const double compareStart = 14.9;
  /// How long the ring takes to reach the farthest best match.
  static const double ringSeconds = 1.7;

  static const double othersFade = 17.1;
  static const double flightStart = 17.3;
  static const double bestLabel = 19.2;
  static const double pillsOut = 22.2;
  static const double end = 26.5;
}
