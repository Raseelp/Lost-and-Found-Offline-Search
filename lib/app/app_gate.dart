import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/tour/controllers/tour_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/features/home/view/home_screen.dart';
import 'package:lost_and_found/features/model_download/view/model_download_screen.dart';
import 'package:lost_and_found/features/home/features/splash/view/splash_overlay.dart';
import 'package:lost_and_found/features/tour/view/first_run_tour.dart';
import 'package:lost_and_found/features/model_download/controllers/model_download_controller.dart';

/// On a fresh install: the tour (which starts the download), then the app. Otherwise the download screen until
/// every model is on the device, then the app.
///
/// While the splash animation plays the screens are not built, so that building them cannot make it stutter. The
/// tour stays up until it is finished, also when the download behind it ends.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SplashGate.released,
      builder: (context, released, _) => released ? _screens() : const ColoredBox(color: AppColors.canvas),
    );
  }

  Widget _screens() {
    return GetBuilder<TourController>(
      builder: (tour) => GetBuilder<ModelDownloadController>(
        builder: (controller) {
          if (controller.isCheckingModels || !tour.loaded) {
            return const Scaffold(
              backgroundColor: AppColors.canvas,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          if (tour.shouldShow(modelsReady: controller.modelsReady)) {
            return const FirstRunTour();
          }

          if (!controller.modelsReady) {
            return const ModelDownloadScreen();
          }

          return const HomeScreen();
        },
      ),
    );
  }
}
