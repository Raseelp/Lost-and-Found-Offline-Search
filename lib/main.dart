import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twentyonevision/bindings/init_bindings.dart';
import 'package:twentyonevision/utils/app_colors.dart';
import 'package:twentyonevision/view/app_gate.dart';

void main() {
  runApp(const TwentyOneVision());
}

class TwentyOneVision extends StatelessWidget {
  const TwentyOneVision({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primarybuttonColor,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primarybuttonColor,
          secondary: AppColors.secondoryButtonColor,
          surface: AppColors.surfaceColor,
          error: AppColors.dangerColor,
        );

    return GetMaterialApp(
      initialBinding: InitBindings(),
      home: const AppGate(),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.backGroundColor,
        colorScheme: colorScheme,
        textTheme: GoogleFonts.spaceGroteskTextTheme().apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: AppColors.textPrimary,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primarybuttonColor,
          inactiveTrackColor: AppColors.surfaceAccent,
          thumbColor: AppColors.accentColor,
          overlayColor: AppColors.accentColor.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}
