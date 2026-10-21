import 'package:flutter/painting.dart';

/// The colours of the face outlines and labels drawn over a photo.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class FacePalette {
  FacePalette._();

  static const Color black = Color(0xFF000000);
  static const Color indigo250 = Color(0xFFB388FF);
  static const Color mint200 = Color(0xFF9FF0E4);
  static const Color mint350 = Color(0xFF5FE0CF);
  static const Color orange300 = Color(0xFFFFC46B);
  static const Color pink100 = Color(0xFFFFD0F0);
  static const Color pink250 = Color(0xFFFF8AD8);
  static const Color sky250 = Color(0xFF7AD7FF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color whiteA78 = Color(0xC8FFFFFF);
}
