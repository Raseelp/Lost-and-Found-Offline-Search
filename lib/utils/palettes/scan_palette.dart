import 'package:flutter/painting.dart';

/// The colours of the square scan picture on the Library tab: its patches, lifts and face matches.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class ScanPalette {
  ScanPalette._();

  static const Color black = Color(0xFF000000);
  static const Color blue500 = Color(0xFF70689E);
  static const Color glow = Color(0xFF7FE3CC);
  static const Color gold150 = Color(0xFFFFF1B8);
  static const Color gold350 = Color(0xFFE9C65C);
  static const Color gold400 = Color(0xFFD6B85A);
  static const Color gold450 = Color(0xFFD9A93A);
  static const Color gray500 = Color(0xFF808080);
  static const Color indigo800 = Color(0xFF1E1446);
  static const Color indigo850 = Color(0xFF181234);
  static const Color mint950 = Color(0xFF0B1210);
  static const Color orange150 = Color(0xFFFFD2B0);
  static const Color orange400 = Color(0xFFD98F5E);
  static const Color white = Color(0xFFFFFFFF);
}
