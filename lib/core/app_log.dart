import 'package:flutter/foundation.dart';
import 'package:lost_and_found/core/native/native_channel.dart';

String? _last;
DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Adds a line to the app's own log, the file a problem report carries (see LogDump on the native side). The same line
/// again within a second is left out, so something that fails in a loop does not fill the log.
void logToApp(String message) {
  final now = DateTime.now();
  if (message == _last && now.difference(_lastAt) < const Duration(seconds: 1)) return;
  _last = message;
  _lastAt = now;
  nativeChannel.invokeMethod<void>('logLine', {'message': message}).catchError((_) {});
}

/// Makes what the Dart side prints and the errors nobody caught end up in the app's log too, so a problem report
/// shows them. Everything still goes where it went before.
void installAppLog() {
  final print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    print(message, wrapWidth: wrapWidth);
    if (message != null) logToApp(message);
  };

  final present = FlutterError.onError;
  FlutterError.onError = (details) {
    present?.call(details);
    logToApp('Flutter error: ${details.exceptionAsString()}\n${_trace(details.stack)}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logToApp('Uncaught error: $error\n${_trace(stack)}');
    return false;
  };
}

String _trace(StackTrace? stack) => (stack?.toString() ?? '').split('\n').take(15).join('\n');
