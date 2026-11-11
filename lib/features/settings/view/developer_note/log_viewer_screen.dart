import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/features/settings/services/settings_service.dart';
import 'package:lost_and_found/features/settings/view/developer_note/page_bar.dart';

/// The app's recent log, the same text that is attached to a problem report. It can be copied from here.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  late final Future<String> _log = SettingsService().appLogs();

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.show('Logs copied.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _log,
          builder: (context, snapshot) {
            final text = snapshot.data;
            return Column(
              children: [
                PageBar(
                  title: 'Logs',
                  actions: [
                    IconButton(
                      tooltip: 'Copy logs',
                      icon: const Icon(
                        Icons.content_copy_rounded,
                        size: 20,
                        color: AppColors.ink,
                      ),
                      onPressed: text == null || text.isEmpty
                          ? null
                          : () => _copy(text),
                    ),
                  ],
                ),
                Expanded(child: _body(context, snapshot, text)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncSnapshot<String> snapshot,
    String? text,
  ) {
    if (snapshot.hasError) return const _Message("Couldn't read the log.");
    if (text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (text.isEmpty) return const _Message('There is no log yet.');

    final lines = text.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.xl,
      ),
      itemCount: lines.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'This is what is attached to your report. It holds what the app was doing.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.ink48,
                height: 1.4,
              ),
            ),
          );
        }
        return Text(
          lines[index - 1],
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.35,
            color: AppColors.ink80,
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.ink48),
      ),
    );
  }
}
