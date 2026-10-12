import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/view/home_screen.dart';
import 'package:lost_and_found/view/model_download_screen.dart';

/// Shows the download screen until every model is on the device, then the app.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NativeController>(
      builder: (controller) {
        if (controller.isCheckingModels) {
          return const Scaffold(
            backgroundColor: AppColors.canvas,
            body: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          );
        }

        // The search models are the only ones downloaded.
        if (!controller.modelsReady) {
          return const ModelDownloadScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
