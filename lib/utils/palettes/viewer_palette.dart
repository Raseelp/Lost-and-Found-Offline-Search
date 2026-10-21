import 'package:flutter/painting.dart';

/// Colours of the photo and video viewers that no other screen uses (the rest are AppColors).
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class ViewerPalette {
  ViewerPalette._();

  static const Color indigo250 = Color(0xFFB388FF);
  static const Color orange300 = Color(0xFFFFC46B);
  static const Color pink250 = Color(0xFFFF8AD8);
  static const Color sky250 = Color(0xFF7AD7FF);
  static const Color whiteA54 = Color(0x8AFFFFFF);
}
