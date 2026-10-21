import 'package:flutter/painting.dart';

/// The colours of the moment badge: its paper, and the shade under its writing.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class MomentPalette {
  MomentPalette._();

  static const Color blackA60 = Color(0x99000000);
  static const Color paper = Color(0xFFFBF3E4);
}
