import 'package:flutter/material.dart';

/// One accent, everywhere. Depth comes from moving between the three surface tones, [canvas], [parchment] and
/// [pearl], never from a shadow or a second color. See [AppRadius] and AppSpacing for the rest of the system.
class AppColors {
  AppColors._();

  /// The only interactive color: links, primary actions, focus, progress fills and selection. Nothing else in the app
  /// uses it decoratively.
  static const Color primary = Color(0xFF165E59);
  static const Color primaryFocus = Color(0xFF1F7A73);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Text is a warm near-black, not pure black.
  static const Color ink = Color(0xFF1A1D1C);
  static const Color ink80 = Color(0xFF3D4240);
  static const Color ink48 = Color(0xFF7C8280);

  /// The only separators. Never a heavy border.
  static const Color hairline = Color(0xFFE2E4E1);
  static const Color dividerSoft = Color(0xFFEFF1EE);

  /// The three surface tones that sections move between.
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color parchment = Color(0xFFF4F6F3);
  static const Color pearl = Color(0xFFFAFBFA);

  /// For state only, never as decoration or a second brand color.
  static const Color danger = Color(0xFFB14032);

  /// Nothing: a fade that ends in no colour, or a surface that is not painted.
  static const Color transparent = Color(0x00000000);

  /// Behind a photo or video, and the bars round it.
  ///
  /// The colors from here to [shadow] are laid over pictures: the full-screen photo and video viewers, and the labels,
  /// badges and shades on a picture. A picture can be any colour, so they do not follow the surfaces above and are
  /// the same wherever a picture is underneath. Dim one with `.withValues(alpha: ...)`.
  static const Color mediaBackdrop = Color(
    0xFF000000,
  );
  /// Writing, icons and outlines on a picture.
  static const Color onMedia = Color(
    0xFFFFFFFF,
  );
  static const Color onMedia70 = Color(0xB3FFFFFF);
  static const Color onMedia24 = Color(0x3DFFFFFF);
  /// A dark shade over a picture, or over the screen behind a dialog.
  static const Color scrim = Color(
    0xFF000000,
  );
  static const Color scrim54 = Color(0x8A000000);
  /// Drop shadows.
  static const Color shadow = Color(0xFF000000);

  /// The viewers' dark chrome has this one accent, and the panels after it.
  static const Color mediaAccent = Color(0xFF5FE0CF);
  static const Color mediaAccentSoft = Color(0xFF9FF0E4);
  static const Color mediaSurface = Color(0xEE15171A);
  static const Color mediaPanel = Color(0xCC121413);
  static const Color mediaInk = Color(0xFF121413);

  /// A starred moment. Small touches of colour like this one are not the accent.
  static const Color honey = Color(0xFFD59A3E);
  /// The lit end of a teal gradient.
  static const Color primaryGlow = Color(
    0xFF1F7A70,
  );
  /// Faces, where the library's orbit marks them.
  static const Color faceAccent = Color(
    0xFF6C63B5,
  );
}
