import 'package:flutter/painting.dart';

/// The colours the People timeline gives each person, so every row of it has its own.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class PeoplePalette {
  PeoplePalette._();

  static const Color gold550 = Color(0xFFA39A45);
  static const Color green450 = Color(0xFF7C9F76);
  static const Color indigo450 = Color(0xFF8C6CA6);
  static const Color red400 = Color(0xFFC4707F);
  static const Color red450 = Color(0xFFC8694A);
  static const Color sky450 = Color(0xFF6E8DB5);
}
