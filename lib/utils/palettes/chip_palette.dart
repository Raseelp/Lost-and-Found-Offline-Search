import 'package:flutter/painting.dart';

/// The colours of the scanning chip drawn on the Library tab: the board, the die, the pins.
///
/// Named by hue and lightness (a higher number is darker; an `A` and a number is how opaque it is).
/// Everything here belongs to a picture that is drawn in code, so it does not follow the theme in
/// AppColors - which is for the screens themselves.
class ChipPalette {
  ChipPalette._();

  static const Color black = Color(0xFF000000);
  static const Color gold = Color(0xFFF2D272);
  static const Color gold350 = Color(0xFFCDB98A);
  static const Color gold400 = Color(0xFFD8B35A);
  static const Color gold450A18 = Color(0x2EC2A24E);
  static const Color gold400a = Color(0xFFD6B85A);
  static const Color goldDull = Color(0xFF8E7A3C);
  static const Color goldDullLight = Color(0xFFB59F58);
  static const Color gray50 = Color(0xFFFAFBFC);
  static const Color gray250 = Color(0xFFB7BDBB);
  static const Color gray650 = Color(0xFF4F5A52);
  static const Color gray900 = Color(0xFF1A1D1C);
  static const Color green350 = Color(0xFF9FB8AB);
  static const Color indigo400A18 = Color(0x2E8A6BC4);
  static const Color mint750 = Color(0xFF2A604B);
  static const Color mint800 = Color(0xFF1B4535);
  static const Color mint900 = Color(0xFF0E2A20);
  static const Color mint800a = Color(0xFF1F3F33);
  static const Color mint900a = Color(0xFF10261D);
  static const Color mint900b = Color(0xFF13281F);
  static const Color pink450A18 = Color(0x2EB26A8E);
  static const Color sky50 = Color(0xFFF2F4F6);
  static const Color sky800 = Color(0xFF2A3138);
  static const Color sky850 = Color(0xFF1E252B);
  static const Color sky950 = Color(0xFF0E1214);
  static const Color sky50a = Color(0xFFEBEEF0);
  static const Color slate100 = Color(0xFFE4E7EA);
  static const Color slate200 = Color(0xFFC9CFD4);
  static const Color slate250 = Color(0xFFB4BAC1);
  static const Color slate300 = Color(0xFFB0B7BE);
  static const Color slate350 = Color(0xFF9AA2A9);
  static const Color slate400 = Color(0xFF8F969D);
  static const Color slate450 = Color(0xFF858C94);
  static const Color slate600 = Color(0xFF58606A);
  static const Color slate650 = Color(0xFF50575E);
  static const Color slate750 = Color(0xFF3B4147);
  static const Color slate800 = Color(0xFF30363D);
  static const Color slate900 = Color(0xFF14181A);
  static const Color slate100a = Color(0xFFDDE1E5);
  static const Color slate200a = Color(0xFFC7CDD3);
  static const Color slate250a = Color(0xFFB9C1C8);
  static const Color slate450a = Color(0xFF8A9198);
  static const Color slate600a = Color(0xFF5B626A);
  static const Color slate600b = Color(0xFF59616A);
  static const Color teal500A18 = Color(0x2E4FA6A3);
  static const Color white = Color(0xFFFFFFFF);
  static const Color whiteA90 = Color(0xE6FFFFFF);
}
