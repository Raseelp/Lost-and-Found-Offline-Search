import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/export/controllers/export_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/widgets/app_search_field.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/library/view/widgets/nothing_indexed.dart';
import 'package:lost_and_found/features/export/view/widgets/zip_art.dart';
import 'package:lost_and_found/features/export/view/widgets/zip_progress.dart';
import 'package:lost_and_found/features/export/models/export_models.dart';
import 'package:lost_and_found/features/export/services/export_service.dart';
part 'export_zip_screen/shared.dart';
part 'export_zip_screen/builder_view.dart';
part 'export_zip_screen/settings_view.dart';
part 'export_zip_screen/search_field.dart';
part 'export_zip_screen/album_row.dart';
part 'export_zip_screen/zip_file_card.dart';
part 'export_zip_screen/split_card.dart';
part 'export_zip_screen/files_preview.dart';
part 'export_zip_screen/inside_card.dart';
part 'export_zip_screen/summary_bar.dart';
part 'export_zip_screen/primary_button.dart';
part 'export_zip_screen/progress_view.dart';
part 'export_zip_screen/done_view.dart';
part 'export_zip_screen/message_view.dart';

/// Choose albums, see what the zip would be, choose how to split it, make it, watch it being
/// made, and send it on.
///
/// The albums are set up before the first frame, so the screen never shows the last visit's. Back from the settings
/// goes back to the albums and not out of the screen. The progress view stays also once the zip is made, until the
/// show of it has played out.
class ExportZipScreen extends StatefulWidget {
  const ExportZipScreen({super.key, this.select = const {}});

  final Set<String> select;

  @override
  State<ExportZipScreen> createState() => _ExportZipScreenState();
}

class _ExportZipScreenState extends State<ExportZipScreen> {
  late final ExportController _export = Get.find<ExportController>();

  @override
  void initState() {
    super.initState();
    _export.prepare(select: widget.select);
    WidgetsBinding.instance.addPostFrameCallback((_) => _export.open());
  }

  @override
  void dispose() {
    _export.closeScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: GetBuilder<ExportController>(
          builder: (c) {
            final phase = c.status.phase;
            final Widget body;
            if (phase == 'idle') {
              body = PopScope(
                key: ValueKey('builder-${c.step}'),
                canPop: c.step == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) c.setStep(0);
                },
                child: c.step == 0 ? _BuilderView(c: c) : _SettingsView(c: c),
              );
            } else if (phase != 'failed' &&
                phase != 'cancelled' &&
                (c.status.running || c.playing)) {
              body = _ProgressView(key: const ValueKey('progress'), c: c);
            } else if (phase == 'done') {
              body = _DoneView(key: const ValueKey('done'), c: c);
            } else if (phase == 'cancelled') {
              body = _MessageView(
                key: const ValueKey('cancelled'),
                c: c,
                icon: Icons.block_rounded,
                title: 'Cancelled',
                message:
                    'Nothing was kept. Your photos and videos are untouched.',
              );
            } else {
              body = _MessageView(
                key: const ValueKey('failed'),
                c: c,
                icon: Icons.error_outline_rounded,
                title: 'The zip could not be made',
                message: c.status.error.isEmpty
                    ? 'Something went wrong.'
                    : c.status.error,
              );
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.05, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: body,
            );
          },
        ),
      ),
    );
  }
}
