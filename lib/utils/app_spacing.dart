/// An 8pt-ish spacing scale in logical pixels.
///
/// Structural layout snaps to sm, md, base, lg and xl. Prefer gaps (a SizedBox between children) over padding on each
/// widget, so the rhythm stays the same from screen to screen.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}
