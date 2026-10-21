import 'package:flutter/painting.dart';

/// The colours of the first-run tour: its page, its text, and the pictures drawn on its pages.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class TourPalette {
  TourPalette._();

  static const Color black = Color(0xFF000000);
  static const Color bottom = Color(0xFFE8F1EE);
  static const Color glow = Color(0xFF7FE3CC);
  static const Color gray600 = Color(0xFF656B69);
  static const Color gray900 = Color(0xFF1A1D1C);
  static const Color line = Color(0xFFDBE3E1);
  static const Color mint = Color(0xFFBFE9E0);
  static const Color mint900 = Color(0xFF102220);
  static const Color mint900A10 = Color(0x1A102220);
  static const Color mint900A14 = Color(0x2410211F);
  static const Color mint900A8 = Color(0x14102220);
  static const Color peach = Color(0xFFFFD9C4);
  static const Color red550 = Color(0xFFB14032);
  static const Color slate250 = Color(0xFFB8C8C4);
  static const Color teal = Color(0xFF165E59);
  static const Color teal750A7 = Color(0x12165E59);
  static const Color text = Color(0xFF10211F);
  static const Color text60 = Color(0xFF5D6E6B);
  static const Color text80 = Color(0xFF3F504D);
  static const Color top = Color(0xFFFBFDFC);
  static const Color white = Color(0xFFFFFFFF);
}
