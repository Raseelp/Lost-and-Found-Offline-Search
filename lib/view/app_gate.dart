import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/controllers/tour_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/view/home_screen.dart';
import 'package:lost_and_found/view/model_download_screen.dart';
import 'package:lost_and_found/view/tour/first_run_tour.dart';

/// On a fresh install: the tour (which starts the download), then the app. Otherwise the download screen until
/// every model is on the device, then the app.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<TourController>(
      builder: (tour) => GetBuilder<NativeController>(
        builder: (controller) {
          if (controller.isCheckingModels || !tour.loaded) {
            return const Scaffold(
              backgroundColor: AppColors.canvas,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          // A fresh install is shown the tour first. It stays up until it is finished, also when
          // the download behind it ends.
          if (tour.shouldShow(modelsReady: controller.modelsReady)) {
            return const FirstRunTour();
          }

          // The search models are the only ones downloaded.
          if (!controller.modelsReady) {
            return const ModelDownloadScreen();
          }

          return const HomeScreen();
        },
      ),
    );
  }
}
