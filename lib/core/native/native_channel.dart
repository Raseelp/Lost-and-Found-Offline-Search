import 'package:flutter/services.dart';

/// The one method channel to the Android side. Every service sends its calls through it.
const MethodChannel nativeChannel = MethodChannel('lostandfound/native');

/// Thrown when a native call fails because the search models are not downloaded or verified yet, so callers can
/// send the person to the download screen.
class ModelsNotReadyError implements Exception {
  const ModelsNotReadyError();
}
