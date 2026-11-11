import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/route_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lost_and_found/app/init_bindings.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/app_log.dart';
import 'package:lost_and_found/core/bundled_licenses.dart';
import 'package:lost_and_found/app/app_gate.dart';
import 'package:lost_and_found/features/home/features/splash/view/splash_overlay.dart';

/// System bars for the app's light screens.
///
/// The app draws behind them and paints the navigation bar in the canvas colour, so it reads as part of the screen.
/// The colour is set explicitly because some OEM skins paint the bar opaque black in 3-button navigation when it is
/// transparent. The icons are dark.
const SystemUiOverlayStyle kAppOverlayStyle = SystemUiOverlayStyle(
  systemNavigationBarColor: AppColors.canvas,
  systemNavigationBarDividerColor: AppColors.canvas,
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.dark,
  statusBarColor: AppColors.transparent,
  statusBarIconBrightness: Brightness.dark,
);

/// Starts the app. The fonts are in assets/fonts, so the app never fetches them from the internet.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  installAppLog();
  registerBundledLicenses();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(kAppOverlayStyle);
  runApp(const LostAndFoundApp());
}

/// The app root.
/// Every text role is pinned to weight 400, 600 or 700, because Material's default text theme uses 500, a weight this
/// app never uses. Every screen gets [kAppOverlayStyle] as a fallback, because Flutter re-applies a style only while a
/// region is on screen, and the light icons of the black photo and video viewers would otherwise stay after closing
/// them. The viewers wrap themselves in an inner region, which wins there. The splash animation is laid over the
/// navigator, so the app is built under it when it clears.
class LostAndFoundApp extends StatelessWidget {
  const LostAndFoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.primary,
          surface: AppColors.canvas,
          error: AppColors.danger,
        );

    final baseText = GoogleFonts.spaceGroteskTextTheme();
    final textTheme = baseText
        .copyWith(
          displayLarge: baseText.displayLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          displayMedium: baseText.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          displaySmall: baseText.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          headlineLarge: baseText.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: baseText.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: baseText.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleLarge: baseText.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: baseText.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: baseText.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: baseText.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
          bodyMedium: baseText.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
          ),
          bodySmall: baseText.bodySmall?.copyWith(fontWeight: FontWeight.w400),
          labelLarge: baseText.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelMedium: baseText.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelSmall: baseText.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    return GetMaterialApp(
      builder: (context, child) => SplashHost(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kAppOverlayStyle,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      initialBinding: InitBindings(),
      home: const AppGate(),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.canvas,
        colorScheme: colorScheme,
        textTheme: textTheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: AppColors.ink,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: AppColors.hairline,
          thumbColor: AppColors.primary,
          overlayColor: AppColors.primary.withValues(alpha: 0.12),
          trackHeight: 4,
        ),
      ),
    );
  }
}
