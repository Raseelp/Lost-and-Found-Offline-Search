import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/settings/models/report_attachment.dart';

/// Reading the app's log and sending a problem report from Settings.
class SettingsService {
  /// The app's recent log, as text.
  Future<String> appLogs() async =>
      await nativeChannel.invokeMethod<String>('appLogs') ?? '';

  /// Opens the system picker for screenshots and screen recordings. Empty when nothing was chosen.
  Future<List<ReportAttachment>> pickReportFiles() async {
    final picked = await nativeChannel.invokeListMethod<Map<Object?, Object?>>(
      'pickReportFiles',
    );
    return [for (final item in picked ?? const []) ReportAttachment.fromMap(item)];
  }

  /// Opens the person's mail app with the report filled in, and they press Send there. Answers 'opened', or
  /// 'no_mail_app' when the phone has no mail app.
  Future<String> sendReport({
    required String to,
    required String message,
    required List<ReportAttachment> attachments,
    required bool includeLogs,
  }) async {
    final answer = await nativeChannel.invokeMethod<String>('sendReport', {
      'to': to,
      'message': message,
      'uris': [for (final a in attachments) a.uri],
      'includeLogs': includeLogs,
    });
    return answer ?? 'opened';
  }
}
